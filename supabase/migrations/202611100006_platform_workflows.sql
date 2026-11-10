-- Complete account provisioning, trial entitlements, opportunity publishing,
-- event ticket issuance and private check-in workflows.
begin;

-- Every Member and Client gets a role-specific profile and a seven-day trial.
-- Plan names/prices remain Admin-managed and are deliberately not invented here.
create or replace function public.provision_ccb_account()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  trial_id uuid;
begin
  if new.account_type = 'member' then
    insert into public.member_profiles (user_id)
    values (new.id)
    on conflict (user_id) do nothing;
  elsif new.account_type = 'client' then
    insert into public.client_profiles (user_id, company_name)
    values (new.id, coalesce(nullif(new.display_name, ''), 'Complete your company profile'))
    on conflict (user_id) do nothing;
  else
    return new;
  end if;

  if not exists (
    select 1 from public.subscriptions s
    where s.user_id = new.id and s.status in ('trial', 'active')
  ) then
    insert into public.subscriptions (user_id, status, trial_starts_at, trial_ends_at)
    values (new.id, 'trial', now(), now() + interval '7 days')
    returning id into trial_id;

    if new.account_type = 'member' then
      insert into public.subscription_entitlements (subscription_id, feature_key, enabled)
      values (trial_id, 'view_opportunities', true), (trial_id, 'apply_opportunities', true)
      on conflict (subscription_id, feature_key) do nothing;
    else
      insert into public.subscription_entitlements (subscription_id, feature_key, enabled)
      values (trial_id, 'discover_members', true), (trial_id, 'publish_opportunities', true), (trial_id, 'view_social_insights', true)
      on conflict (subscription_id, feature_key) do nothing;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists provision_ccb_account on public.user_profiles;
create trigger provision_ccb_account
  after insert or update on public.user_profiles
  for each row execute function public.provision_ccb_account();

-- Repair existing accounts without inventing plans or prices.
insert into public.member_profiles (user_id)
select id from public.user_profiles where account_type = 'member'
on conflict (user_id) do nothing;
insert into public.client_profiles (user_id, company_name)
select id, coalesce(nullif(display_name, ''), 'Complete your company profile')
from public.user_profiles where account_type = 'client'
on conflict (user_id) do nothing;
do $$
declare
  account record;
  trial_id uuid;
begin
  for account in select id, account_type from public.user_profiles where account_type in ('member', 'client') loop
    if not exists (select 1 from public.subscriptions s where s.user_id = account.id and s.status in ('trial', 'active')) then
      insert into public.subscriptions (user_id, status, trial_starts_at, trial_ends_at)
      values (account.id, 'trial', now(), now() + interval '7 days') returning id into trial_id;
      if account.account_type = 'member' then
        insert into public.subscription_entitlements (subscription_id, feature_key, enabled)
        values (trial_id, 'view_opportunities', true), (trial_id, 'apply_opportunities', true);
      else
        insert into public.subscription_entitlements (subscription_id, feature_key, enabled)
        values (trial_id, 'discover_members', true), (trial_id, 'publish_opportunities', true), (trial_id, 'view_social_insights', true);
      end if;
    end if;
  end loop;
end;
$$;

-- Entitled clients can publish a valid draft and move it through its lifecycle.
create or replace function public.set_opportunity_status(p_opportunity_id uuid, p_status text)
returns public.work_opportunities
language plpgsql
security definer
set search_path = ''
as $$
declare
  item public.work_opportunities;
  allowed boolean := false;
begin
  if (select public.current_account_type()) <> 'client'
    or not (select public.has_entitlement('publish_opportunities')) then
    raise exception 'Client opportunity access is not active.' using errcode = '42501';
  end if;
  select * into item from public.work_opportunities
  where id = p_opportunity_id and client_id = (select auth.uid()) for update;
  if not found then raise exception 'Opportunity not found.' using errcode = 'P0002'; end if;

  allowed := (item.status = 'draft' and p_status = 'published')
    or (item.status = 'published' and p_status in ('applications_closed', 'in_progress', 'cancelled'))
    or (item.status = 'applications_closed' and p_status in ('published', 'in_progress', 'cancelled'))
    or (item.status = 'in_progress' and p_status in ('completed', 'cancelled'));
  if not allowed then raise exception 'This opportunity status transition is not allowed.' using errcode = '22023'; end if;
  if p_status = 'published' and (length(trim(item.title)) < 3 or length(trim(item.description)) < 20) then
    raise exception 'Add a clear title and at least 20 characters of description before publishing.' using errcode = '22023';
  end if;

  update public.work_opportunities
  set status = p_status,
      published_at = case when p_status = 'published' then coalesce(published_at, now()) else published_at end,
      updated_at = now()
  where id = p_opportunity_id returning * into item;
  return item;
end;
$$;
revoke all on function public.set_opportunity_status(uuid, text) from public, anon;
grant execute on function public.set_opportunity_status(uuid, text) to authenticated;

-- Authenticated event registration is transactional and returns an opaque QR
-- token once. Only a hash is stored in the database.
create or replace function public.register_for_event(
  p_event_id uuid,
  p_attendee_name text,
  p_attendee_email text,
  p_attendee_phone text default null,
  p_form_responses jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  event_row public.events;
  registration_id uuid;
  registration_status text;
  ticket_token text;
  used_capacity bigint;
  field_row record;
  field_value jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in to register for an event.' using errcode = '42501'; end if;
  if length(trim(coalesce(p_attendee_name, ''))) < 2 or length(trim(coalesce(p_attendee_email, ''))) < 5 then
    raise exception 'Enter your name and a valid email address.' using errcode = '22023';
  end if;
  select * into event_row from public.events where id = p_event_id and status = 'published' for update;
  if not found then raise exception 'Event is not available for registration.' using errcode = 'P0002'; end if;
  if event_row.registration_policy = 'invite_only' then
    raise exception 'This event requires an invitation.' using errcode = '42501';
  end if;
  if event_row.registration_opens_at is not null and event_row.registration_opens_at > now() then
    raise exception 'Registration has not opened yet.' using errcode = '22023';
  end if;
  if event_row.registration_closes_at is not null and event_row.registration_closes_at < now() then
    raise exception 'Registration is closed.' using errcode = '22023';
  end if;
  if jsonb_typeof(coalesce(p_form_responses, '{}'::jsonb)) <> 'object' then
    raise exception 'Event form responses must be an object.' using errcode = '22023';
  end if;
  if exists (
    select 1 from jsonb_object_keys(coalesce(p_form_responses, '{}'::jsonb)) submitted(key)
    where not exists (select 1 from public.event_form_fields f where f.event_id = p_event_id and f.field_key = submitted.key)
  ) then raise exception 'Unexpected event form fields were submitted.' using errcode = '22023'; end if;
  for field_row in select f.field_key, f.field_type, f.is_required, f.options from public.event_form_fields f where f.event_id = p_event_id loop
    field_value := coalesce(p_form_responses, '{}'::jsonb) -> field_row.field_key;
    if field_row.is_required and (field_value is null or field_value = 'null'::jsonb or (field_row.field_type = 'checkbox' and field_value <> 'true'::jsonb)) then
      raise exception 'Complete the required event form fields.' using errcode = '22023';
    end if;
    if field_value is null or field_value = 'null'::jsonb then continue; end if;
    if field_row.field_type in ('text', 'textarea', 'email', 'phone') then
      if jsonb_typeof(field_value) <> 'string' or length(field_value #>> '{}') > 5000 then
        raise exception 'An event form response is invalid.' using errcode = '22023';
      end if;
      if field_row.field_type = 'email' and (field_value #>> '{}') !~* '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$' then
        raise exception 'Enter a valid email in the event form.' using errcode = '22023';
      end if;
    elsif field_row.field_type = 'number' then
      if jsonb_typeof(field_value) <> 'number' then raise exception 'An event form response is invalid.' using errcode = '22023'; end if;
    elsif field_row.field_type = 'checkbox' then
      if jsonb_typeof(field_value) <> 'boolean' then raise exception 'An event form response is invalid.' using errcode = '22023'; end if;
    elsif field_row.field_type = 'date' then
      if jsonb_typeof(field_value) <> 'string' or (field_value #>> '{}') !~ '^\d{4}-\d{2}-\d{2}$' then raise exception 'An event form response is invalid.' using errcode = '22023'; end if;
    elsif field_row.field_type = 'select' then
      if jsonb_typeof(field_value) <> 'string' or not exists (
        select 1 from jsonb_array_elements_text(field_row.options) choice(value) where choice.value = field_value #>> '{}'
      ) then raise exception 'Choose a valid event form option.' using errcode = '22023'; end if;
    end if;
  end loop;
  if exists (select 1 from public.event_registrations r where r.event_id = p_event_id and r.user_id = auth.uid()) then
    raise exception 'You are already registered for this event.' using errcode = '23505';
  end if;
  select count(*) into used_capacity from public.event_registrations r
  where r.event_id = p_event_id and r.status in ('registered', 'pending');
  if event_row.capacity is not null and used_capacity >= event_row.capacity then
    registration_status := 'waitlisted';
  elsif event_row.registration_policy = 'approval_required' then
    registration_status := 'pending';
  else
    registration_status := 'registered';
  end if;

  insert into public.event_registrations (event_id, user_id, attendee_name, attendee_email, attendee_phone, form_responses, status)
  values (p_event_id, auth.uid(), trim(p_attendee_name), lower(trim(p_attendee_email)), nullif(trim(coalesce(p_attendee_phone, '')), ''), coalesce(p_form_responses, '{}'::jsonb), registration_status)
  returning id into registration_id;

  if registration_status = 'registered' and event_row.qr_check_in_enabled then
    ticket_token := encode(extensions.gen_random_bytes(16), 'hex');
    insert into public.event_tickets (registration_id, token_hash)
    values (registration_id, encode(extensions.digest(ticket_token, 'sha256'), 'hex'));
  end if;
  return jsonb_build_object('registration_id', registration_id, 'status', registration_status, 'ticket_token', ticket_token);
end;
$$;
revoke all on function public.register_for_event(uuid, text, text, text, jsonb) from public, anon;
grant execute on function public.register_for_event(uuid, text, text, text, jsonb) to authenticated;

-- Reissue a lost ticket by replacing the stored hash; the former QR stops working.
create or replace function public.refresh_event_ticket(p_registration_id uuid)
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  token text;
begin
  if not exists (
    select 1 from public.event_registrations r join public.events e on e.id = r.event_id
    where r.id = p_registration_id and r.user_id = auth.uid() and r.status = 'registered' and e.qr_check_in_enabled
  ) then raise exception 'Ticket cannot be issued for this registration.' using errcode = '42501'; end if;
  token := encode(extensions.gen_random_bytes(16), 'hex');
  update public.event_tickets set token_hash = encode(extensions.digest(token, 'sha256'), 'hex'), revoked_at = null
  where registration_id = p_registration_id;
  if not found then
    insert into public.event_tickets (registration_id, token_hash)
    values (p_registration_id, encode(extensions.digest(token, 'sha256'), 'hex'));
  end if;
  return token;
end;
$$;
revoke all on function public.refresh_event_ticket(uuid) from public, anon;
grant execute on function public.refresh_event_ticket(uuid) to authenticated;

-- Admin-only API calls this function after validating the separate Admin session.
create or replace function public.check_in_event_ticket(p_ticket_token text, p_checked_in_by uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  ticket_row public.event_tickets;
  result jsonb;
begin
  if length(coalesce(p_ticket_token, '')) <> 32 then raise exception 'Invalid ticket.' using errcode = '22023'; end if;
  select t.* into ticket_row from public.event_tickets t
  where t.token_hash = encode(extensions.digest(p_ticket_token, 'sha256'), 'hex')
    and t.revoked_at is null for update;
  if not found then raise exception 'Ticket is invalid or revoked.' using errcode = 'P0002'; end if;
  if exists (select 1 from public.attendance_records a where a.registration_id = ticket_row.registration_id) then
    raise exception 'This ticket has already been checked in.' using errcode = '23505';
  end if;
  if not exists (
    select 1 from public.event_registrations r join public.events e on e.id = r.event_id
    where r.id = ticket_row.registration_id and r.status = 'registered' and e.qr_check_in_enabled
  ) then raise exception 'Registration is not eligible for check-in.' using errcode = '42501'; end if;
  insert into public.attendance_records (registration_id, checked_in_by, check_in_method)
  values (ticket_row.registration_id, p_checked_in_by, 'qr');
  select jsonb_build_object('attendee_name', r.attendee_name, 'attendee_email', r.attendee_email, 'event_title', e.title, 'checked_in_at', a.checked_in_at)
  into result from public.attendance_records a
  join public.event_registrations r on r.id = a.registration_id
  join public.events e on e.id = r.event_id
  where a.registration_id = ticket_row.registration_id;
  return result;
end;
$$;
revoke all on function public.check_in_event_ticket(text, uuid) from public, anon, authenticated;
grant execute on function public.check_in_event_ticket(text, uuid) to service_role;

-- In-app notifications keep workflows visible even before an email provider is selected.
create or replace function public.notify_opportunity_application()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  recipient uuid;
  opportunity_title text;
begin
  select o.client_id, o.title into recipient, opportunity_title
  from public.work_opportunities o where o.id = new.opportunity_id;
  if tg_op = 'INSERT' then
    insert into public.notifications (user_id, notification_type, title, message, target_url)
    values (recipient, 'application_received', 'New opportunity application', 'A Member applied to “' || opportunity_title || '”.', '/client/dashboard?section=applications');
  elsif old.status is distinct from new.status then
    insert into public.notifications (user_id, notification_type, title, message, target_url)
    values (new.member_id, 'application_status', 'Application status updated', 'Your application for “' || opportunity_title || '” is now ' || replace(new.status, '_', ' ') || '.', '/member/dashboard?section=applications');
  end if;
  return new;
end;
$$;
drop trigger if exists application_notifications on public.applications;
create trigger application_notifications after insert or update on public.applications
for each row execute function public.notify_opportunity_application();

create or replace function public.stamp_application_status_change()
returns trigger language plpgsql set search_path = '' as $$
begin
  if old.status is distinct from new.status then new.status_updated_at := now(); end if;
  return new;
end;
$$;
drop trigger if exists stamp_application_status_change on public.applications;
create trigger stamp_application_status_change before update on public.applications
for each row execute function public.stamp_application_status_change();

create or replace function public.notify_event_registration_status()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status is distinct from new.status and new.user_id is not null then
    insert into public.notifications (user_id, notification_type, title, message, target_url)
    select new.user_id, 'event_registration_status', 'Event registration updated', 'Your registration for “' || e.title || '” is now ' || replace(new.status, '_', ' ') || '.', '/member/dashboard?section=events'
    from public.events e where e.id = new.event_id;
  end if;
  return new;
end;
$$;
drop trigger if exists event_registration_notifications on public.event_registrations;
create trigger event_registration_notifications after update on public.event_registrations
for each row execute function public.notify_event_registration_status();

create or replace function public.notify_client_service_status()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status is distinct from new.status then
    insert into public.notifications (user_id, notification_type, title, message, target_url)
    values (new.client_id, 'service_request_status', 'CCB service request updated', 'Your request “' || new.subject || '” is now ' || replace(new.status, '_', ' ') || '.', '/client/dashboard?section=requests');
  end if;
  return new;
end;
$$;
drop trigger if exists service_request_notifications on public.client_service_requests;
create trigger service_request_notifications after update on public.client_service_requests
for each row execute function public.notify_client_service_status();

create or replace function public.notify_membership_application_status()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if old.status is distinct from new.status and new.user_id is not null then
    insert into public.notifications (user_id, notification_type, title, message, target_url)
    values (new.user_id, 'membership_application_status', 'Membership application updated', 'Your CCB membership application is now ' || replace(new.status, '_', ' ') || '.', '/member/dashboard?section=notifications');
  end if;
  return new;
end;
$$;
drop trigger if exists membership_application_notifications on public.membership_applications;
create trigger membership_application_notifications after update on public.membership_applications
for each row execute function public.notify_membership_application_status();

commit;

begin;

-- Directory queries expose only public presentation fields for eligible clients.
drop policy if exists user_profiles_read_public_members on public.user_profiles;
create policy user_profiles_read_public_members on public.user_profiles
for select to authenticated using (
  (select public.current_account_type()) = 'client'
  and (select public.has_entitlement('discover_members'))
  and exists (select 1 from public.member_profiles m where m.user_id = public.user_profiles.id and m.is_public)
);
drop policy if exists user_profiles_read_published_clients on public.user_profiles;
create policy user_profiles_read_published_clients on public.user_profiles
for select to authenticated using (
  (select public.current_account_type()) = 'member'
  and (select public.has_entitlement('view_opportunities'))
  and exists (select 1 from public.work_opportunities o where o.client_id = public.user_profiles.id and o.status = 'published')
);

drop policy if exists media_assets_read_discoverable_member_media on public.media_assets;
create policy media_assets_read_discoverable_member_media on public.media_assets
for select to authenticated using (
  (select public.current_account_type()) = 'client'
  and (select public.has_entitlement('discover_members'))
  and (
    exists (select 1 from public.member_profiles m where m.profile_media_id = public.media_assets.id and m.is_public)
    or exists (
      select 1 from public.portfolio_item_media pm
      join public.portfolio_items p on p.id = pm.portfolio_item_id
      join public.member_profiles m on m.user_id = p.member_id
      where pm.media_asset_id = public.media_assets.id and p.visibility = 'public' and m.is_public
    )
  )
);

drop policy if exists member_profiles_read_application_participant on public.member_profiles;
create policy member_profiles_read_application_participant on public.member_profiles
for select to authenticated using (
  exists (
    select 1 from public.applications a
    join public.work_opportunities o on o.id = a.opportunity_id
    where a.member_id = public.member_profiles.user_id and o.client_id = (select auth.uid())
  )
);

drop policy if exists user_profiles_read_application_participant on public.user_profiles;
create policy user_profiles_read_application_participant on public.user_profiles
for select to authenticated using (
  exists (
    select 1 from public.applications a
    join public.work_opportunities o on o.id = a.opportunity_id
    where a.member_id = public.user_profiles.id and o.client_id = (select auth.uid())
  )
);

grant insert (opportunity_id, reviewer_user_id, reviewed_user_id, rating, review_text) on public.reviews to authenticated;

-- Keep Member enquiries visible to both participants and notify the recipient.
create or replace function public.notify_member_enquiry()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.notifications (user_id, notification_type, title, message, target_url)
  values (new.member_id, 'member_enquiry', 'New client enquiry', 'A CCB Client sent you a message: ' || left(new.subject, 180), '/member/dashboard?section=enquiries');
  return new;
end;
$$;
drop trigger if exists member_enquiry_notifications on public.member_enquiries;
create trigger member_enquiry_notifications after insert on public.member_enquiries
for each row execute function public.notify_member_enquiry();

commit;
