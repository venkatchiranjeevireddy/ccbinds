-- CCB India: setup for the existing base schema shown in the Supabase screenshots.
-- Paste this entire file into Supabase SQL Editor and run once.
-- Includes migrations 003 and 005-017. Deliberately omits 001-002 (base schema already exists)
-- and 004 (legacy Admin roster stage; migration 005 handles the final static Admin schema).
-- Everything runs in one transaction: any error rolls the complete setup back.
-- Historical event_form_fields, event_registrations, event_tickets and attendance_records are preserved.
-- If admin_accounts still contains old Supabase-Auth roster rows, this script stops before conversion.

begin;

do $$
declare
  missing_tables text;
  has_admin_id boolean;
  has_password_hash boolean;
  has_admin_rows boolean;
begin
  select string_agg(required.name, ', ' order by required.name)
    into missing_tables
  from (values
    ('user_profiles'), ('member_profiles'), ('client_profiles'),
    ('professional_categories'), ('skills'), ('media_assets'),
    ('work_opportunities'), ('applications'), ('programs'), ('events'),
    ('event_media'), ('admin_accounts')
  ) as required(name)
  where to_regclass('public.' || required.name) is null;

  if missing_tables is not null then
    raise exception 'Base schema check failed. Missing public tables: %. Run the existing base schema first.', missing_tables;
  end if;

  select exists (select 1 from information_schema.columns where table_schema='public' and table_name='admin_accounts' and column_name='admin_id') into has_admin_id;
  select exists (select 1 from information_schema.columns where table_schema='public' and table_name='admin_accounts' and column_name='password_hash') into has_password_hash;
  if not (has_admin_id and has_password_hash) then
    execute 'select exists (select 1 from public.admin_accounts)' into has_admin_rows;
    if has_admin_rows then
      raise exception 'admin_accounts has legacy rows. Back them up and inspect before converting to static Admin IDs/password hashes.';
    end if;
  end if;
end;
$$;


-- ===== Source migration: 202611100003_profile_image_references.sql =====
-- Apply after 202611100002_ccb_platform_schema.sql.
-- Adds links from Member/Client profiles to R2 media metadata records.

alter table public.member_profiles
  add column if not exists profile_media_id uuid references public.media_assets (id) on delete set null;

alter table public.client_profiles
  add column if not exists logo_media_id uuid references public.media_assets (id) on delete set null;

create index if not exists member_profiles_media_idx
  on public.member_profiles (profile_media_id);
create index if not exists client_profiles_logo_idx
  on public.client_profiles (logo_media_id);

drop policy if exists member_profile_insert_own on public.member_profiles;
create policy member_profile_insert_own on public.member_profiles
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and (select public.current_account_type()) = 'member'
    and (
      profile_media_id is null
      or exists (
        select 1 from public.media_assets a
        where a.id = profile_media_id and a.owner_user_id = (select auth.uid())
      )
    )
  );

drop policy if exists member_profile_update_own on public.member_profiles;
create policy member_profile_update_own on public.member_profiles
  for update to authenticated
  using (
    user_id = (select auth.uid())
    and (select public.current_account_type()) = 'member'
  )
  with check (
    user_id = (select auth.uid())
    and (select public.current_account_type()) = 'member'
    and (
      profile_media_id is null
      or exists (
        select 1 from public.media_assets a
        where a.id = profile_media_id and a.owner_user_id = (select auth.uid())
      )
    )
  );

drop policy if exists client_profile_insert_own on public.client_profiles;
create policy client_profile_insert_own on public.client_profiles
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and (select public.current_account_type()) = 'client'
    and (
      logo_media_id is null
      or exists (
        select 1 from public.media_assets a
        where a.id = logo_media_id and a.owner_user_id = (select auth.uid())
      )
    )
  );

drop policy if exists client_profile_update_own on public.client_profiles;
create policy client_profile_update_own on public.client_profiles
  for update to authenticated
  using (
    user_id = (select auth.uid())
    and (select public.current_account_type()) = 'client'
  )
  with check (
    user_id = (select auth.uid())
    and (select public.current_account_type()) = 'client'
    and (
      logo_media_id is null
      or exists (
        select 1 from public.media_assets a
        where a.id = logo_media_id and a.owner_user_id = (select auth.uid())
      )
    )
  );

grant insert (user_id, headline, bio, location, country_code, years_experience,
  availability, professional_interests, contact_preference, portfolio_website,
  is_public, insights_sharing_enabled, profile_media_id)
  on public.member_profiles to authenticated;
grant update (headline, bio, location, country_code, years_experience, availability,
  professional_interests, contact_preference, portfolio_website, is_public,
  insights_sharing_enabled, profile_media_id)
  on public.member_profiles to authenticated;

grant insert (user_id, company_name, organization_type, industry, description,
  website_url, location, country_code, business_email, business_phone, logo_media_id)
  on public.client_profiles to authenticated;
grant update (company_name, organization_type, industry, description, website_url,
  location, country_code, business_email, business_phone, logo_media_id)
  on public.client_profiles to authenticated;

-- ===== Source migration: 202611100005_static_admin_credentials.sql =====
-- Admins use private Admin IDs and passwords, separate from Supabase Auth.
-- Run once after 202611100004_admin_accounts.sql. Legacy Auth-user roster rows
-- are discarded during conversion; existing static admin_id/password_hash rows
-- are preserved. Add any missing Admins with the INSERT example below.

create extension if not exists pgcrypto with schema extensions;

-- Close the old Supabase-Auth-based Admin check before changing its source table.
-- Admin API routes use the signed zadmin session and the server-only service key.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select false
$$;

create table if not exists public.admin_accounts (
  admin_id text primary key,
  password_hash text not null
);

alter table public.admin_accounts disable row level security;

do $$
declare
  has_admin_id boolean;
  has_password_hash boolean;
  primary_key_name text;
  has_admin_id_primary_key boolean;
begin
  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'admin_accounts' and column_name = 'admin_id'
  ) into has_admin_id;
  select exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'admin_accounts' and column_name = 'password_hash'
  ) into has_password_hash;

  if has_admin_id and has_password_hash then
    -- Keep manually entered static credentials if the table was already converted.
    alter table public.admin_accounts
      drop column if exists user_id cascade,
      drop column if exists status cascade,
      drop column if exists invited_by cascade,
      drop column if exists created_at cascade,
      drop column if exists updated_at cascade;
  else
    -- Old Auth-user roster rows cannot be mapped to static IDs/passwords.
    delete from public.admin_accounts;
    alter table public.admin_accounts
      drop column if exists user_id cascade,
      drop column if exists status cascade,
      drop column if exists invited_by cascade,
      drop column if exists created_at cascade,
      drop column if exists updated_at cascade,
      drop column if exists admin_id cascade,
      drop column if exists password_hash cascade,
      add column admin_id text not null,
      add column password_hash text not null;
  end if;

  select c.conname
    into primary_key_name
    from pg_constraint c
   where c.conrelid = 'public.admin_accounts'::regclass and c.contype = 'p';

  select exists (
    select 1
      from pg_constraint c
      join unnest(c.conkey) with ordinality as k(attnum, ord) on true
      join pg_attribute a on a.attrelid = c.conrelid and a.attnum = k.attnum
     where c.conrelid = 'public.admin_accounts'::regclass
       and c.contype = 'p'
     group by c.oid
    having count(*) = 1 and max(a.attname) = 'admin_id'
  ) into has_admin_id_primary_key;

  if not has_admin_id_primary_key then
    if primary_key_name is not null then
      execute format('alter table public.admin_accounts drop constraint %I', primary_key_name);
    end if;
    alter table public.admin_accounts add constraint admin_accounts_pkey primary key (admin_id);
  end if;
end;
$$;

alter table public.admin_accounts enable row level security;
revoke all on public.admin_accounts from public, anon, authenticated;
grant all on public.admin_accounts to service_role;

-- Remove the unused duplicate table from the earlier draft, if it was created.
drop table if exists public.admin_credentials;

create or replace function public.verify_admin_credentials(p_admin_id text, p_password text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.admin_accounts a
    where a.admin_id = p_admin_id
      and a.password_hash = extensions.crypt(p_password, a.password_hash)
  )
$$;

revoke all on function public.verify_admin_credentials(text, text) from public, anon, authenticated;
grant execute on function public.verify_admin_credentials(text, text) to service_role;

-- Provision each Admin manually in the SQL Editor. Repeat with a unique Admin ID:
-- insert into public.admin_accounts (admin_id, password_hash)
-- values ('your-admin-id', extensions.crypt('your-password', extensions.gen_salt('bf')));

-- ===== Source migration: 202611100006_platform_workflows.sql =====
-- Complete account provisioning, trial entitlements, opportunity publishing,
-- event ticket issuance and private check-in workflows.

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

-- ===== Source migration: 202611100007_account_and_registration_workflows.sql =====

-- Let signed-in Members and Clients edit their display name without opening
-- writes to role assignment or other identity fields.
drop policy if exists user_profiles_update_display_name on public.user_profiles;
create policy user_profiles_update_display_name on public.user_profiles
for update to authenticated
using (id = (select auth.uid()) and account_type in ('member', 'client'))
with check (id = (select auth.uid()) and account_type in ('member', 'client'));
grant update (display_name) on public.user_profiles to authenticated;

-- A registrant can cancel only their own active/pending/waitlisted registration.
-- Revoke any issued ticket in the same transaction so it cannot be checked in.
create or replace function public.cancel_event_registration(p_registration_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  registration_row public.event_registrations;
begin
  if auth.uid() is null then
    raise exception 'Sign in to manage your event registration.' using errcode = '42501';
  end if;

  select * into registration_row
  from public.event_registrations
  where id = p_registration_id and user_id = auth.uid()
  for update;

  if not found then
    raise exception 'Registration not found.' using errcode = 'P0002';
  end if;
  if registration_row.status not in ('pending', 'registered', 'waitlisted') then
    raise exception 'This registration cannot be cancelled.' using errcode = '22023';
  end if;
  if exists (select 1 from public.attendance_records where registration_id = p_registration_id) then
    raise exception 'An attended event registration cannot be cancelled.' using errcode = '22023';
  end if;

  update public.event_registrations set status = 'cancelled', updated_at = now()
  where id = p_registration_id;
  update public.event_tickets set revoked_at = now()
  where registration_id = p_registration_id and revoked_at is null;
end;
$$;
revoke all on function public.cancel_event_registration(uuid) from public, anon;
grant execute on function public.cancel_event_registration(uuid) to authenticated;
revoke update (status) on public.event_registrations from authenticated;

create or replace function public.revoke_cancelled_event_ticket()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'cancelled' and old.status is distinct from new.status then
    update public.event_tickets set revoked_at = now()
    where registration_id = new.id and revoked_at is null;
  end if;
  return new;
end;
$$;
drop trigger if exists revoke_cancelled_event_ticket on public.event_registrations;
create trigger revoke_cancelled_event_ticket
before update of status on public.event_registrations
for each row execute function public.revoke_cancelled_event_ticket();

-- ===== Source migration: 202611100008_application_deadline_enforcement.sql =====

-- Enforce the closing window at the database boundary so a stale browser or a
-- direct PostgREST insert cannot apply after the configured deadline.
drop policy if exists applications_submit_member on public.applications;
create policy applications_submit_member on public.applications
for insert to authenticated
with check (
  member_id = (select auth.uid())
  and (select public.current_account_type()) = 'member'
  and (select public.has_entitlement('apply_opportunities'))
  and exists (
    select 1 from public.work_opportunities o
    where o.id = opportunity_id
      and o.status = 'published'
      and (o.application_deadline is null or o.application_deadline > now())
      and (o.deadline is null or o.deadline >= current_date)
  )
);

-- ===== Source migration: 202611100009_application_status_workflow.sql =====

create table if not exists public.application_status_history (
  id uuid primary key default gen_random_uuid(),
  application_id uuid not null references public.applications (id) on delete cascade,
  actor_user_id uuid references public.user_profiles (id) on delete set null,
  from_status text not null,
  to_status text not null,
  change_note text,
  changed_at timestamptz not null default now()
);
alter table public.application_status_history enable row level security;
create index if not exists application_status_history_application_changed_idx
  on public.application_status_history (application_id, changed_at desc);
drop policy if exists application_status_history_read_participants on public.application_status_history;
create policy application_status_history_read_participants on public.application_status_history
for select to authenticated using (
  exists (
    select 1 from public.applications a
    left join public.work_opportunities o on o.id = a.opportunity_id
    where a.id = application_id
      and (a.member_id = (select auth.uid()) or o.client_id = (select auth.uid()) or (select public.is_admin()))
  )
);
grant select on public.application_status_history to authenticated;

create or replace function public.record_application_status_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.status is distinct from new.status then
    insert into public.application_status_history (application_id, actor_user_id, from_status, to_status)
    values (new.id, (select auth.uid()), old.status, new.status);
  end if;
  return new;
end;
$$;
drop trigger if exists application_status_history_record on public.applications;
create trigger application_status_history_record after update on public.applications
for each row execute function public.record_application_status_change();

create or replace function public.set_application_status(
  p_application_id uuid,
  p_status text,
  p_client_message text default null
)
returns public.applications
language plpgsql
security definer
set search_path = ''
as $$
declare
  application_row public.applications;
  account_type text;
  owns_application boolean := false;
  allowed_transition boolean := false;
begin
  account_type := (select public.current_account_type());
  if account_type is null or account_type not in ('member', 'client') or auth.uid() is null then
    raise exception 'Sign in with a Member or Client account.' using errcode = '42501';
  end if;

  select a.* into application_row
  from public.applications a
  where a.id = p_application_id
  for update;
  if not found then raise exception 'Application not found.' using errcode = 'P0002'; end if;

  if account_type = 'member' then
    if application_row.member_id <> auth.uid() then raise exception 'Application not found.' using errcode = 'P0002'; end if;
    allowed_transition := application_row.status = 'submitted' and p_status = 'withdrawn';
  else
    select exists (
      select 1 from public.work_opportunities o
      where o.id = application_row.opportunity_id and o.client_id = auth.uid()
    ) into owns_application;
    if not owns_application then raise exception 'Application not found.' using errcode = 'P0002'; end if;
    allowed_transition := (application_row.status = 'submitted' and p_status in ('under_review', 'shortlisted', 'rejected'))
      or (application_row.status = 'under_review' and p_status in ('shortlisted', 'selected', 'rejected'))
      or (application_row.status = 'shortlisted' and p_status in ('under_review', 'selected', 'rejected'));
  end if;
  if not allowed_transition then
    raise exception 'This application status transition is not allowed.' using errcode = '22023';
  end if;
  if p_client_message is not null and length(p_client_message) > 3000 then
    raise exception 'Client message must be 3000 characters or fewer.' using errcode = '22023';
  end if;

  update public.applications
  set status = p_status,
      client_message = case when account_type = 'client' and p_client_message is not null then nullif(trim(p_client_message), '') else client_message end,
      status_updated_at = now()
  where id = p_application_id
  returning * into application_row;
  return application_row;
end;
$$;
revoke all on function public.set_application_status(uuid, text, text) from public, anon;
grant execute on function public.set_application_status(uuid, text, text) to authenticated;
revoke update (status, client_message) on public.applications from authenticated;

-- ===== Source migration: 202611100010_discovery_entitlement_rls.sql =====

-- A guessed Member UUID must not bypass discovery entitlement checks.
drop policy if exists member_enquiries_create_client on public.member_enquiries;
create policy member_enquiries_create_client on public.member_enquiries
for insert to authenticated
with check (
  client_id = (select auth.uid())
  and (select public.current_account_type()) = 'client'
  and (select public.has_entitlement('discover_members'))
  and exists (
    select 1 from public.member_profiles m
    where m.user_id = member_id and m.is_public
  )
);

-- Keep a Client's saved/search history readable/removable if access expires,
-- while preventing discovery writes without the matching entitlement.
drop policy if exists saved_members_manage_client on public.saved_members;
create policy saved_members_read_own on public.saved_members
for select to authenticated using (client_id = (select auth.uid()) or (select public.is_admin()));
create policy saved_members_create_entitled on public.saved_members
for insert to authenticated with check (
  client_id = (select auth.uid())
  and (select public.current_account_type()) = 'client'
  and (select public.has_entitlement('discover_members'))
  and exists (select 1 from public.member_profiles m where m.user_id = member_id and m.is_public)
);
create policy saved_members_remove_own on public.saved_members
for delete to authenticated using (client_id = (select auth.uid()) or (select public.is_admin()));

drop policy if exists search_history_manage_client on public.client_search_history;
create policy search_history_read_own on public.client_search_history
for select to authenticated using (client_id = (select auth.uid()) or (select public.is_admin()));
create policy search_history_create_entitled on public.client_search_history
for insert to authenticated with check (
  client_id = (select auth.uid())
  and (select public.current_account_type()) = 'client'
  and (select public.has_entitlement('discover_members'))
);
create policy search_history_remove_own on public.client_search_history
for delete to authenticated using (client_id = (select auth.uid()) or (select public.is_admin()));

-- ===== Source migration: 202611100011_event_registration_rpc_only.sql =====

-- Registration must pass capacity, date-window, policy, duplicate and custom
-- form validation in register_for_event; direct row inserts bypass those checks.
drop policy if exists event_registrations_create on public.event_registrations;
revoke insert (event_id, user_id, attendee_name, attendee_email, attendee_phone, form_responses)
  on public.event_registrations from anon, authenticated;
revoke insert (event_id, attendee_name, attendee_email, attendee_phone, form_responses)
  on public.event_registrations from anon;

-- ===== Source migration: 202611100012_portfolio_media_ownership_rls.sql =====
-- Keep portfolio media and application attachments within the owning Member's
-- account. Admin access continues through the existing admin policies.

drop policy if exists portfolio_item_media_manage on public.portfolio_item_media;

create policy portfolio_item_media_insert_own on public.portfolio_item_media
for insert to authenticated with check (
  exists (
    select 1
    from public.portfolio_items p
    join public.media_assets m on m.id = media_asset_id
    where p.id = portfolio_item_id
      and p.member_id = (select auth.uid())
      and m.owner_user_id = (select auth.uid())
  )
);

create policy portfolio_item_media_delete_own on public.portfolio_item_media
for delete to authenticated using (
  exists (
    select 1 from public.portfolio_items p
    where p.id = portfolio_item_id and p.member_id = (select auth.uid())
  )
);

drop policy if exists application_portfolio_manage_member on public.application_portfolio_items;

create policy application_portfolio_insert_own on public.application_portfolio_items
for insert to authenticated with check (
  exists (
    select 1
    from public.applications a
    join public.portfolio_items p on p.id = portfolio_item_id
    where a.id = application_id
      and a.member_id = (select auth.uid())
      and p.member_id = a.member_id
  )
);

create policy application_portfolio_delete_own on public.application_portfolio_items
for delete to authenticated using (
  exists (
    select 1 from public.applications a
    where a.id = application_id and a.member_id = (select auth.uid())
  )
);

-- ===== Source migration: 202611100013_public_member_identity_rls.sql =====
-- Make the identity fields embedded in public Member profiles readable to
-- entitled Clients without exposing other account identities.
create policy user_profiles_read_discoverable_member_identity
on public.user_profiles for select to authenticated using (
  account_type = 'member'
  and (select public.current_account_type()) = 'client'
  and (select public.has_entitlement('discover_members'))
  and exists (
    select 1 from public.member_profiles m
    where m.user_id = public.user_profiles.id and m.is_public
  )
);

-- Participants in an opportunity engagement can see the other party's basic
-- display identity even if the Member is not listed publicly.
create policy user_profiles_read_application_participants
on public.user_profiles for select to authenticated using (
  exists (
    select 1
    from public.applications a
    join public.work_opportunities o on o.id = a.opportunity_id
    where (a.member_id = public.user_profiles.id and o.client_id = (select auth.uid()))
       or (o.client_id = public.user_profiles.id and a.member_id = (select auth.uid()))
  )
);

-- ===== Source migration: 202611100014_event_scanner_selected_event.sql =====
-- Require Admin scanners to select an event and bind ticket validation to it.
drop function if exists public.check_in_event_ticket(text, uuid);

create function public.check_in_event_ticket(
  p_ticket_token text,
  p_event_id uuid,
  p_checked_in_by uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  ticket_row public.event_tickets;
  result jsonb;
begin
  if p_event_id is null then raise exception 'Select an event before check-in.' using errcode = '22023'; end if;
  if length(coalesce(p_ticket_token, '')) <> 32 then
    raise exception 'Invalid ticket.' using errcode = '22023';
  end if;

  select t.* into ticket_row
  from public.event_tickets t
  where t.token_hash = encode(extensions.digest(p_ticket_token, 'sha256'), 'hex')
    and t.revoked_at is null
  for update;
  if not found then raise exception 'Ticket is invalid or revoked.' using errcode = 'P0002'; end if;

  if not exists (
    select 1 from public.event_registrations r
    where r.id = ticket_row.registration_id and r.event_id = p_event_id
  ) then raise exception 'Ticket belongs to another event.' using errcode = '22023'; end if;

  if exists (select 1 from public.attendance_records a where a.registration_id = ticket_row.registration_id) then
    raise exception 'This ticket has already been checked in.' using errcode = '23505';
  end if;
  if not exists (
    select 1 from public.event_registrations r join public.events e on e.id = r.event_id
    where r.id = ticket_row.registration_id and r.status = 'registered'
      and e.id = p_event_id and e.qr_check_in_enabled
  ) then raise exception 'Registration is not eligible for check-in.' using errcode = '42501'; end if;

  insert into public.attendance_records (registration_id, checked_in_by, check_in_method)
  values (ticket_row.registration_id, p_checked_in_by, 'qr');
  select jsonb_build_object('attendee_name', r.attendee_name, 'attendee_email', r.attendee_email,
      'event_title', e.title, 'checked_in_at', a.checked_in_at)
  into result from public.attendance_records a
  join public.event_registrations r on r.id = a.registration_id
  join public.events e on e.id = r.event_id
  where a.registration_id = ticket_row.registration_id;
  return result;
end;
$$;

revoke all on function public.check_in_event_ticket(text, uuid, uuid) from public, anon, authenticated;
grant execute on function public.check_in_event_ticket(text, uuid, uuid) to service_role;

-- ===== Source migration: 202611100015_public_content_featured_media.sql =====
-- Public content references media metadata; the image bytes remain in private R2.
alter table public.events
  add column if not exists featured_media_id uuid references public.media_assets (id) on delete set null;

alter table public.programs
  add column if not exists featured_media_id uuid references public.media_assets (id) on delete set null;

-- ===== Source migration: 202611100016_external_event_rsvp.sql =====
-- CCB publishes events and links to external RSVP providers. Existing native
-- registration records are preserved for history, while the native write/RPC
-- paths are retired for the current version.
alter table public.events
  add column if not exists event_category text,
  add column if not exists target_audience text[] not null default '{}',
  add column if not exists event_visibility text not null default 'public',
  add column if not exists external_rsvp_url text,
  add column if not exists rsvp_closed boolean not null default false,
  add column if not exists announcement_audience text[] not null default '{}';

alter table public.events drop constraint if exists events_event_visibility_check;
alter table public.events add constraint events_event_visibility_check
  check (event_visibility in ('public', 'unlisted', 'private'));
alter table public.events drop constraint if exists events_external_rsvp_url_check;
alter table public.events add constraint events_external_rsvp_url_check
  check (external_rsvp_url is null or external_rsvp_url ~* '^https://[^[:space:]]+$');
alter table public.events drop constraint if exists events_target_audience_check;
alter table public.events add constraint events_target_audience_check
  check (target_audience <@ array['members','clients','both']::text[]);
alter table public.events drop constraint if exists events_announcement_audience_check;
alter table public.events add constraint events_announcement_audience_check
  check (announcement_audience <@ array['members','clients']::text[]);

drop policy if exists read_published_events on public.events;
create policy read_published_events on public.events
for select to anon, authenticated using (
  (status = 'published' and event_visibility in ('public', 'unlisted'))
  or (select public.is_admin())
);

-- Keep historical event_registrations, event_tickets, attendance_records and
-- event_form_fields rows intact. Prevent future native ticket workflows.
revoke all on function public.register_for_event(uuid, text, text, text, jsonb) from public, anon, authenticated;
revoke all on function public.refresh_event_ticket(uuid) from public, anon, authenticated;
revoke all on function public.check_in_event_ticket(text, uuid, uuid) from public, anon, authenticated;

-- ===== Source migration: 202611100017_central_professional_taxonomy.sql =====
-- Extend the existing category/skill catalogue. Existing UUIDs and user
-- selections remain intact; roles and software tools are distinct concepts.
create table if not exists public.professional_roles (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  slug text not null unique,
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.professional_role_categories (
  id uuid not null default gen_random_uuid() unique,
  role_id uuid not null references public.professional_roles(id) on delete cascade,
  category_id uuid not null references public.professional_categories(id) on delete restrict,
  primary key (role_id, category_id)
);

create table if not exists public.skill_categories (
  id uuid not null default gen_random_uuid() unique,
  skill_id uuid not null references public.skills(id) on delete cascade,
  category_id uuid not null references public.professional_categories(id) on delete restrict,
  primary key (skill_id, category_id)
);

create table if not exists public.professional_tools (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  slug text not null unique,
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.professional_tool_categories (
  id uuid not null default gen_random_uuid() unique,
  tool_id uuid not null references public.professional_tools(id) on delete cascade,
  category_id uuid not null references public.professional_categories(id) on delete restrict,
  primary key (tool_id, category_id)
);

create table if not exists public.taxonomy_aliases (
  id uuid primary key default gen_random_uuid(),
  alias text not null unique,
  normalized_alias text generated always as (lower(btrim(alias))) stored,
  role_id uuid references public.professional_roles(id) on delete cascade,
  skill_id uuid references public.skills(id) on delete cascade,
  tool_id uuid references public.professional_tools(id) on delete cascade,
  created_at timestamptz not null default now(),
  check (num_nonnulls(role_id, skill_id, tool_id) = 1)
);
create index if not exists taxonomy_alias_search_idx on public.taxonomy_aliases (normalized_alias);
create unique index if not exists taxonomy_aliases_normalized_unique on public.taxonomy_aliases (normalized_alias);

alter table public.professional_categories add column if not exists search_document tsvector
  generated always as (to_tsvector('simple', coalesce(name,'') || ' ' || coalesce(description,''))) stored;
alter table public.skills add column if not exists search_document tsvector
  generated always as (to_tsvector('simple', coalesce(name,'') || ' ' || coalesce(description,''))) stored;
alter table public.professional_roles add column if not exists search_document tsvector
  generated always as (to_tsvector('simple', coalesce(name,'') || ' ' || coalesce(description,''))) stored;
alter table public.professional_tools add column if not exists search_document tsvector
  generated always as (to_tsvector('simple', coalesce(name,'') || ' ' || coalesce(description,''))) stored;
alter table public.taxonomy_aliases add column if not exists search_document tsvector
  generated always as (to_tsvector('simple', alias)) stored;
alter table public.member_profiles add column if not exists taxonomy_search_document tsvector
  generated always as (to_tsvector('simple', coalesce(headline,'') || ' ' || coalesce(bio,''))) stored;
create index if not exists categories_search_document_idx on public.professional_categories using gin(search_document);
create index if not exists skills_search_document_idx on public.skills using gin(search_document);
create index if not exists roles_search_document_idx on public.professional_roles using gin(search_document);
create index if not exists tools_search_document_idx on public.professional_tools using gin(search_document);
create index if not exists taxonomy_aliases_search_document_idx on public.taxonomy_aliases using gin(search_document);
create index if not exists member_profiles_taxonomy_search_idx on public.member_profiles using gin(taxonomy_search_document);

create table if not exists public.member_roles (
  member_id uuid not null references public.member_profiles(user_id) on delete cascade,
  role_id uuid not null references public.professional_roles(id) on delete restrict,
  primary key (member_id, role_id)
);
create table if not exists public.member_tools (
  member_id uuid not null references public.member_profiles(user_id) on delete cascade,
  tool_id uuid not null references public.professional_tools(id) on delete restrict,
  primary key (member_id, tool_id)
);
create table if not exists public.opportunity_roles (
  opportunity_id uuid not null references public.work_opportunities(id) on delete cascade,
  role_id uuid not null references public.professional_roles(id) on delete restrict,
  primary key (opportunity_id, role_id)
);
create table if not exists public.opportunity_tools (
  opportunity_id uuid not null references public.work_opportunities(id) on delete cascade,
  tool_id uuid not null references public.professional_tools(id) on delete restrict,
  primary key (opportunity_id, tool_id)
);

create table if not exists public.taxonomy_suggestions (
  id uuid primary key default gen_random_uuid(),
  submitted_by uuid references public.user_profiles(id) on delete set null,
  suggestion_type text not null check (suggestion_type in ('category','role','skill','tool')),
  name text not null check (length(btrim(name)) between 2 and 160),
  category_id uuid references public.professional_categories(id) on delete set null,
  description text,
  status text not null default 'submitted' check (status in ('submitted','under_review','approved','rejected')),
  admin_notes text,
  submitted_at timestamptz not null default now(),
  reviewed_at timestamptz
);

create table if not exists public.opportunity_interactions (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.member_profiles(user_id) on delete cascade,
  opportunity_id uuid not null references public.work_opportunities(id) on delete cascade,
  interaction_type text not null check (interaction_type in ('view','search','save','apply')),
  created_at timestamptz not null default now()
);

alter table public.member_profiles
  add column if not exists expected_rate_min numeric(12,2) check (expected_rate_min is null or expected_rate_min >= 0),
  add column if not exists expected_rate_max numeric(12,2) check (expected_rate_max is null or expected_rate_max >= expected_rate_min),
  add column if not exists expected_rate_period text check (expected_rate_period is null or expected_rate_period in ('project','hourly','daily','monthly')),
  add column if not exists rate_negotiable boolean not null default true,
  add column if not exists work_preferences text[] not null default '{}';

alter table public.work_opportunities
  add column if not exists budget_type text check (budget_type is null or budget_type in ('fixed','hourly','daily','monthly_salary')),
  add column if not exists budget_negotiable boolean not null default false,
  add column if not exists payment_terms text,
  add column if not exists work_type text check (work_type is null or work_type in ('project','freelance','contract','part_time','full_time','ongoing')),
  add column if not exists experience_max_years numeric(4,1) check (experience_max_years is null or experience_max_years >= experience_min_years),
  add column if not exists required_availability text check (required_availability is null or required_availability in ('available','limited','any')),
  add column if not exists skills_match_mode text not null default 'any' check (skills_match_mode in ('any','all'));

alter table public.work_opportunities drop constraint if exists work_opportunities_budget_range_check;
alter table public.work_opportunities add constraint work_opportunities_budget_range_check
  check (budget_min is null or budget_max is null or budget_max >= budget_min) not valid;

alter table public.event_media add column if not exists id uuid not null default gen_random_uuid();
create unique index if not exists event_media_id_unique on public.event_media(id);

alter table public.opportunity_skills
  add column if not exists is_mandatory boolean not null default false;

create table if not exists public.member_work_preferences (
  member_id uuid not null references public.member_profiles(user_id) on delete cascade,
  work_arrangement text not null check (work_arrangement in ('remote','hybrid','on_site')),
  primary key (member_id, work_arrangement)
);

alter table public.professional_categories enable row level security;
alter table public.skills enable row level security;
alter table public.professional_roles enable row level security;
alter table public.professional_role_categories enable row level security;
alter table public.skill_categories enable row level security;
alter table public.professional_tools enable row level security;
alter table public.professional_tool_categories enable row level security;
alter table public.taxonomy_aliases enable row level security;
alter table public.member_roles enable row level security;
alter table public.member_tools enable row level security;
alter table public.opportunity_roles enable row level security;
alter table public.opportunity_tools enable row level security;
alter table public.taxonomy_suggestions enable row level security;
alter table public.opportunity_interactions enable row level security;
alter table public.member_work_preferences enable row level security;

drop policy if exists read_active_categories on public.professional_categories;
drop policy if exists read_active_skills on public.skills;
create policy read_active_categories on public.professional_categories for select to anon, authenticated using (is_active or (select public.is_admin()));
create policy read_active_skills on public.skills for select to authenticated using (is_active or (select public.is_admin()));
create policy read_active_professional_roles on public.professional_roles for select to authenticated using (is_active or (select public.is_admin()));
create policy read_active_professional_tools on public.professional_tools for select to authenticated using (is_active or (select public.is_admin()));
create policy read_active_skill_categories on public.skill_categories for select to authenticated using (exists (select 1 from public.skills s where s.id = skill_id and s.is_active));
create policy read_active_role_categories on public.professional_role_categories for select to authenticated using (exists (select 1 from public.professional_roles r where r.id = role_id and r.is_active));
create policy read_active_tool_categories on public.professional_tool_categories for select to authenticated using (exists (select 1 from public.professional_tools t where t.id = tool_id and t.is_active));
create policy read_taxonomy_aliases on public.taxonomy_aliases for select to authenticated using (
  (role_id is not null and exists (select 1 from public.professional_roles r where r.id = role_id and r.is_active)) or
  (skill_id is not null and exists (select 1 from public.skills s where s.id = skill_id and s.is_active)) or
  (tool_id is not null and exists (select 1 from public.professional_tools t where t.id = tool_id and t.is_active))
);

create policy admin_manage_professional_roles on public.professional_roles for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy admin_manage_professional_role_categories on public.professional_role_categories for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy admin_manage_skill_categories on public.skill_categories for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy admin_manage_professional_tools on public.professional_tools for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy admin_manage_professional_tool_categories on public.professional_tool_categories for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy admin_manage_taxonomy_aliases on public.taxonomy_aliases for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy admin_manage_taxonomy_suggestions on public.taxonomy_suggestions for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy user_submit_taxonomy_suggestions on public.taxonomy_suggestions for insert to authenticated with check (submitted_by = (select auth.uid()) and status = 'submitted' and admin_notes is null);
create policy taxonomy_suggestions_read_submitter on public.taxonomy_suggestions for select to authenticated using (submitted_by = (select auth.uid()) or (select public.is_admin()));
create policy user_manage_member_roles on public.member_roles for all to authenticated using (member_id = (select auth.uid()) or (select public.is_admin())) with check (
  (member_id = (select auth.uid()) and (select public.current_account_type()) = 'member' and exists (select 1 from public.professional_roles r where r.id = role_id and r.is_active))
  or (select public.is_admin())
);
create policy member_roles_read_discovery on public.member_roles for select to authenticated using (
  member_id = (select auth.uid()) or (select public.is_admin()) or
  ((select public.current_account_type()) = 'client' and (select public.has_entitlement('discover_members'))
    and exists (select 1 from public.member_profiles m where m.user_id = member_id and m.is_public))
);
create policy user_manage_member_tools on public.member_tools for all to authenticated using (member_id = (select auth.uid()) or (select public.is_admin())) with check (
  (member_id = (select auth.uid()) and (select public.current_account_type()) = 'member' and exists (select 1 from public.professional_tools t where t.id = tool_id and t.is_active))
  or (select public.is_admin())
);
create policy member_tools_read_discovery on public.member_tools for select to authenticated using (
  member_id = (select auth.uid()) or (select public.is_admin()) or
  ((select public.current_account_type()) = 'client' and (select public.has_entitlement('discover_members'))
    and exists (select 1 from public.member_profiles m where m.user_id = member_id and m.is_public))
);
create policy user_manage_member_work_preferences on public.member_work_preferences for all to authenticated using (member_id = (select auth.uid()) or (select public.is_admin())) with check (member_id = (select auth.uid()) or (select public.is_admin()));

drop policy if exists member_categories_manage_own on public.member_categories;
create policy member_categories_insert_active_own on public.member_categories for insert to authenticated with check (
  member_id = (select auth.uid()) and (select public.current_account_type()) = 'member'
  and exists (select 1 from public.professional_categories c where c.id = category_id and c.is_active)
);
create policy member_categories_delete_own on public.member_categories for delete to authenticated using (member_id = (select auth.uid()));
create policy member_categories_admin_manage on public.member_categories for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
drop policy if exists member_skills_manage_own on public.member_skills;
create policy member_skills_insert_active_own on public.member_skills for insert to authenticated with check (
  member_id = (select auth.uid()) and (select public.current_account_type()) = 'member'
  and exists (select 1 from public.skills s where s.id = skill_id and s.is_active)
);
create policy member_skills_delete_own on public.member_skills for delete to authenticated using (member_id = (select auth.uid()));
create policy member_skills_admin_manage on public.member_skills for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
drop policy if exists opportunity_categories_manage_owner on public.opportunity_categories;
create policy opportunity_categories_insert_active on public.opportunity_categories for insert to authenticated with check (
  exists (select 1 from public.work_opportunities o join public.professional_categories c on c.id = category_id where o.id = opportunity_id and o.client_id = (select auth.uid()) and c.is_active)
  or (select public.is_admin())
);
create policy opportunity_categories_delete_owner on public.opportunity_categories for delete to authenticated using (
  exists (select 1 from public.work_opportunities o where o.id = opportunity_id and o.client_id = (select auth.uid())) or (select public.is_admin())
);
create policy opportunity_categories_admin_manage on public.opportunity_categories for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
drop policy if exists opportunity_skills_manage_owner on public.opportunity_skills;
create policy opportunity_skills_insert_active on public.opportunity_skills for insert to authenticated with check (
  exists (select 1 from public.work_opportunities o join public.skills s on s.id = skill_id where o.id = opportunity_id and o.client_id = (select auth.uid()) and s.is_active)
  or (select public.is_admin())
);
create policy opportunity_skills_delete_owner on public.opportunity_skills for delete to authenticated using (
  exists (select 1 from public.work_opportunities o where o.id = opportunity_id and o.client_id = (select auth.uid())) or (select public.is_admin())
);
create policy opportunity_skills_admin_manage on public.opportunity_skills for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

create policy opportunity_roles_read on public.opportunity_roles for select to authenticated using (
  exists (select 1 from public.work_opportunities o where o.id = opportunity_id and (o.client_id = (select auth.uid()) or (select public.is_admin()) or (o.status = 'published' and (select public.current_account_type()) = 'member' and (select public.has_entitlement('view_opportunities')))))
);
create policy opportunity_roles_manage_owner on public.opportunity_roles for all to authenticated using (exists (select 1 from public.work_opportunities o where o.id = opportunity_id and (o.client_id = (select auth.uid()) or (select public.is_admin())))) with check (exists (select 1 from public.work_opportunities o join public.professional_roles r on r.id = role_id where o.id = opportunity_id and (o.client_id = (select auth.uid()) or (select public.is_admin())) and (r.is_active or (select public.is_admin()))));
create policy opportunity_tools_read on public.opportunity_tools for select to authenticated using (
  exists (select 1 from public.work_opportunities o where o.id = opportunity_id and (o.client_id = (select auth.uid()) or (select public.is_admin()) or (o.status = 'published' and (select public.current_account_type()) = 'member' and (select public.has_entitlement('view_opportunities')))))
);
create policy opportunity_tools_manage_owner on public.opportunity_tools for all to authenticated using (exists (select 1 from public.work_opportunities o where o.id = opportunity_id and (o.client_id = (select auth.uid()) or (select public.is_admin())))) with check (exists (select 1 from public.work_opportunities o join public.professional_tools t on t.id = tool_id where o.id = opportunity_id and (o.client_id = (select auth.uid()) or (select public.is_admin())) and (t.is_active or (select public.is_admin()))));
create policy opportunity_interactions_owner on public.opportunity_interactions for all to authenticated using (member_id = (select auth.uid()) or (select public.is_admin())) with check (member_id = (select auth.uid()) and (select public.current_account_type()) = 'member');

grant select on public.professional_roles, public.professional_role_categories, public.skill_categories, public.professional_tools, public.professional_tool_categories, public.taxonomy_aliases to authenticated;
grant insert, update, delete on public.professional_categories, public.skills to authenticated;
grant insert, update, delete on public.professional_roles, public.professional_role_categories, public.skill_categories, public.professional_tools, public.professional_tool_categories, public.taxonomy_aliases to authenticated;
grant select, insert on public.taxonomy_suggestions to authenticated;
grant update on public.taxonomy_suggestions to authenticated;
grant select, insert, delete on public.member_roles, public.member_tools, public.member_work_preferences to authenticated;
grant select, insert on public.opportunity_roles, public.opportunity_tools to authenticated;
grant update (expected_rate_min, expected_rate_max, expected_rate_period, rate_negotiable, work_preferences)
  on public.member_profiles to authenticated;
grant insert (budget_type, budget_negotiable, payment_terms, work_type, experience_max_years, required_availability, skills_match_mode)
  on public.work_opportunities to authenticated;
grant update (budget_type, budget_negotiable, payment_terms, work_type, experience_max_years, required_availability, skills_match_mode)
  on public.work_opportunities to authenticated;
grant insert, update on public.member_work_preferences to authenticated;
grant insert on public.opportunity_interactions to authenticated;

create index if not exists member_roles_role_idx on public.member_roles(role_id, member_id);
create index if not exists member_tools_tool_idx on public.member_tools(tool_id, member_id);
create index if not exists opportunity_roles_role_idx on public.opportunity_roles(role_id, opportunity_id);
create index if not exists opportunity_tools_tool_idx on public.opportunity_tools(tool_id, opportunity_id);
create index if not exists member_profiles_experience_idx on public.member_profiles(years_experience);
create index if not exists opportunities_budget_type_idx on public.work_opportunities(budget_type, budget_min, budget_max);
create index if not exists opportunity_interactions_member_recent_idx on public.opportunity_interactions(member_id, created_at desc);
create index if not exists public_reviews_member_rating_idx on public.reviews(reviewed_user_id, rating) where status = 'published';

create or replace view public.admin_taxonomy_usage as
select 'category:' || c.id::text as id, 'category'::text as taxonomy_type, c.id as taxonomy_id, c.name, c.is_active,
  count(distinct mc.member_id) as member_count,
  count(distinct oc.opportunity_id) as opportunity_count
from public.professional_categories c
left join public.member_categories mc on mc.category_id=c.id
left join public.opportunity_categories oc on oc.category_id=c.id
group by c.id
union all
select 'role:' || r.id::text, 'role', r.id, r.name, r.is_active,
  count(distinct mr.member_id), count(distinct op.opportunity_id)
from public.professional_roles r
left join public.member_roles mr on mr.role_id=r.id
left join public.opportunity_roles op on op.role_id=r.id
group by r.id
union all
select 'skill:' || s.id::text, 'skill', s.id, s.name, s.is_active,
  count(distinct ms.member_id), count(distinct os.opportunity_id)
from public.skills s
left join public.member_skills ms on ms.skill_id=s.id
left join public.opportunity_skills os on os.skill_id=s.id
group by s.id
union all
select 'tool:' || t.id::text, 'tool', t.id, t.name, t.is_active,
  count(distinct mt.member_id), count(distinct ot.opportunity_id)
from public.professional_tools t
left join public.member_tools mt on mt.tool_id=t.id
left join public.opportunity_tools ot on ot.tool_id=t.id
group by t.id;
revoke all on public.admin_taxonomy_usage from public, anon, authenticated;
grant select on public.admin_taxonomy_usage to service_role;

-- Rule-based feed: required/mandatory skills and maximum experience are hard
-- filters; category, role, other skills, location, availability, preferences,
-- budget compatibility and recency contribute to ordering.
create or replace function public.get_personalized_opportunities(p_page integer default 0, p_page_size integer default 20)
returns table(opportunity_id uuid, relevance_score numeric, total_count bigint)
language sql stable security definer set search_path = '' as $$
  with member_data as (
    select m.user_id, m.location, m.years_experience, m.availability, m.expected_rate_min, m.expected_rate_max, m.expected_rate_period,
      coalesce(array_agg(distinct mc.category_id) filter (where mc.category_id is not null), '{}'::uuid[]) categories,
      coalesce((select array_agg(ms.skill_id) from public.member_skills ms where ms.member_id = m.user_id), '{}'::uuid[]) skills,
      coalesce((select array_agg(mr.role_id) from public.member_roles mr where mr.member_id = m.user_id), '{}'::uuid[]) roles,
      coalesce((select array_agg(mt.tool_id) from public.member_tools mt where mt.member_id = m.user_id), '{}'::uuid[]) tools,
      coalesce((select array_agg(mwp.work_arrangement) from public.member_work_preferences mwp where mwp.member_id = m.user_id), '{}'::text[]) arrangements
    from public.member_profiles m left join public.member_categories mc on mc.member_id = m.user_id
    where m.user_id = auth.uid()
      and public.current_account_type() = 'member'
      and public.has_entitlement('view_opportunities')
    group by m.user_id
  ), candidates as (
    select o.id,
      (select count(*) from public.opportunity_skills os join public.member_skills ms on ms.skill_id = os.skill_id and ms.member_id = md.user_id where os.opportunity_id = o.id)::numeric skill_matches,
      (select count(*) from public.opportunity_skills os where os.opportunity_id = o.id)::numeric total_skills,
      (select count(*) from public.opportunity_categories oc where oc.opportunity_id = o.id and oc.category_id = any(md.categories))::numeric category_matches,
      (select count(*) from public.opportunity_roles orl where orl.opportunity_id = o.id and orl.role_id = any(md.roles))::numeric role_matches,
      (select count(*) from public.opportunity_tools ot where ot.opportunity_id = o.id and ot.tool_id = any(md.tools))::numeric tool_matches,
      case when md.location is not null and (lower(coalesce(o.location,'')) = lower(md.location) or o.work_arrangement = 'remote') then 1 else 0 end::numeric location_match,
      case when cardinality(md.arrangements) = 0 or o.work_arrangement is null or o.work_arrangement = any(md.arrangements) then 1 else 0 end::numeric preference_match,
      case when o.budget_min is null or md.expected_rate_max is null or o.budget_max is null then 1
        when md.expected_rate_period is not null and o.budget_type is not null and md.expected_rate_period <> case o.budget_type when 'fixed' then 'project' when 'monthly_salary' then 'monthly' else o.budget_type end then 0
        when md.expected_rate_max >= o.budget_min then 1 else 0 end::numeric budget_match,
      greatest(0, 30 - extract(epoch from (now() - coalesce(o.published_at, o.created_at))) / 86400 / 3)::numeric recency_score,
      exists(select 1 from public.opportunity_skills os where os.opportunity_id = o.id and os.is_mandatory and not exists(select 1 from public.member_skills ms where ms.member_id = md.user_id and ms.skill_id = os.skill_id)) missing_mandatory,
      exists(select 1 from public.opportunity_skills os where os.opportunity_id = o.id and not exists(select 1 from public.member_skills ms where ms.member_id = md.user_id and ms.skill_id = os.skill_id)) missing_any_skill,
      md.availability, md.years_experience, o.experience_min_years, o.experience_max_years, o.required_availability
    from public.work_opportunities o cross join member_data md
    where o.status = 'published' and (o.application_deadline is null or o.application_deadline > now())
      and (o.deadline is null or o.deadline >= current_date)
  )
  select c.id,
    (c.skill_matches * 10 + c.role_matches * 8 + c.category_matches * 6 + c.tool_matches * 4 + c.location_match * 3 + c.preference_match * 2 + c.budget_match + c.recency_score)::numeric,
    count(*) over ()::bigint
  from candidates c
  where not c.missing_mandatory
    and (c.required_availability is null or c.required_availability = 'any' or c.availability = c.required_availability)
    and (c.experience_min_years is null or c.years_experience is null or c.years_experience >= c.experience_min_years)
    and (c.experience_max_years is null or c.years_experience is null or c.years_experience <= c.experience_max_years)
    and (c.total_skills = 0 or c.skill_matches > 0)
    and not (c.missing_any_skill and exists(select 1 from public.work_opportunities wo where wo.id = c.id and wo.skills_match_mode = 'all'))
  order by 2 desc, c.id
  limit greatest(1, least(coalesce(p_page_size,20),100)) offset greatest(0,coalesce(p_page,0)) * greatest(1,least(coalesce(p_page_size,20),100));
$$;
revoke all on function public.get_personalized_opportunities(integer,integer) from public, anon;
grant execute on function public.get_personalized_opportunities(integer,integer) to authenticated;

-- Shared role/skill/tool/category and alias-aware search for the Client directory.
create or replace function public.search_member_profiles(p_query text, p_minimum_rating numeric default null, p_minimum_reviews integer default null)
returns table(member_id uuid, average_rating numeric, review_count bigint)
language sql stable security definer set search_path = '' as $$
  with term as (select plainto_tsquery('simple', left(coalesce(p_query,''), 160)) q)
  select m.user_id, ratings.average_rating, ratings.review_count
  from public.member_profiles m cross join term
  left join lateral (
    select avg(r.rating)::numeric(3,2) average_rating, count(*)::bigint review_count
    from public.reviews r where r.reviewed_user_id=m.user_id and r.status='published'
  ) ratings on true
  where m.is_public and public.current_account_type() = 'client'
    and public.has_entitlement('discover_members')
    and (p_minimum_rating is null or coalesce(ratings.average_rating,0) >= p_minimum_rating)
    and (p_minimum_reviews is null or coalesce(ratings.review_count,0) >= p_minimum_reviews)
    and (btrim(coalesce(p_query,'')) = '' or (
      m.taxonomy_search_document @@ term.q
      or exists (select 1 from public.member_categories mc join public.professional_categories c on c.id=mc.category_id where mc.member_id=m.user_id and c.is_active and c.search_document @@ term.q)
      or exists (select 1 from public.member_skills ms join public.skills s on s.id=ms.skill_id where ms.member_id=m.user_id and s.is_active and (s.search_document @@ term.q or exists(select 1 from public.taxonomy_aliases a where a.skill_id=s.id and a.search_document @@ term.q)))
      or exists (select 1 from public.member_roles mr join public.professional_roles r on r.id=mr.role_id where mr.member_id=m.user_id and r.is_active and (r.search_document @@ term.q or exists(select 1 from public.taxonomy_aliases a where a.role_id=r.id and a.search_document @@ term.q)))
      or exists (select 1 from public.member_tools mt join public.professional_tools t on t.id=mt.tool_id where mt.member_id=m.user_id and t.is_active and (t.search_document @@ term.q or exists(select 1 from public.taxonomy_aliases a where a.tool_id=t.id and a.search_document @@ term.q)))
    ));
$$;
revoke all on function public.search_member_profiles(text,numeric,integer) from public, anon;
grant execute on function public.search_member_profiles(text,numeric,integer) to authenticated;


-- Seed supplied reference taxonomy without replacing existing IDs.
insert into public.professional_categories (name,slug,sort_order) values
  ('Video & Film Production','video-and-film-production',1),
  ('Graphic & Visual Design','graphic-and-visual-design',2),
  ('Photography','photography',3),
  ('Influencers & Social Media','influencers-and-social-media',4),
  ('Content Creation & Writing','content-creation-and-writing',5),
  ('Digital Marketing','digital-marketing',6),
  ('Animation & Motion Graphics','animation-and-motion-graphics',7),
  ('Web, Technology & Design','web-technology-and-design',8),
  ('Audio & Music Production','audio-and-music-production',9),
  ('Events & Production','events-and-production',10),
  ('Advertising & Branding','advertising-and-branding',11),
  ('AI & Emerging Technologies','ai-and-emerging-technologies',12),
  ('Fashion & Lifestyle','fashion-and-lifestyle',13),
  ('Public Relations & Communications','public-relations-and-communications',14),
  ('Business & Creative Consulting','business-and-creative-consulting',15),
  ('Journalism & Media','journalism-and-media',16),
  ('Education & Training','education-and-training',17),
  ('Food & Hospitality','food-and-hospitality',18)
on conflict do nothing;

insert into public.professional_roles (name,slug) values
  ('Video Editor','video-editor'),
  ('Film Editor','film-editor'),
  ('Video Producer','video-producer'),
  ('Videographer','videographer'),
  ('Cinematographer','cinematographer'),
  ('Director','director'),
  ('Assistant Director','assistant-director'),
  ('Camera Operator','camera-operator'),
  ('Drone Videographer','drone-videographer'),
  ('Colorist / Color Grading Artist','colorist-color-grading-artist'),
  ('Video Content Producer','video-content-producer'),
  ('Documentary Filmmaker','documentary-filmmaker'),
  ('Short-form Video Editor','short-form-video-editor'),
  ('Wedding Film Editor','wedding-film-editor'),
  ('Commercial Video Producer','commercial-video-producer'),
  ('Post-production Specialist','post-production-specialist'),
  ('Video Production Assistant','video-production-assistant'),
  ('Graphic Designer','graphic-designer'),
  ('Logo Designer','logo-designer'),
  ('Brand Identity Designer','brand-identity-designer'),
  ('Visual Designer','visual-designer'),
  ('Social Media Designer','social-media-designer'),
  ('Creative Designer','creative-designer'),
  ('Packaging Designer','packaging-designer'),
  ('Print Designer','print-designer'),
  ('Advertising Designer','advertising-designer'),
  ('Poster Designer','poster-designer'),
  ('Thumbnail Designer','thumbnail-designer'),
  ('Presentation Designer','presentation-designer'),
  ('Illustrator','illustrator'),
  ('Photoshop Artist','photoshop-artist'),
  ('Digital Artist','digital-artist'),
  ('Infographic Designer','infographic-designer'),
  ('Photographer','photographer'),
  ('Product Photographer','product-photographer'),
  ('Fashion Photographer','fashion-photographer'),
  ('Wedding Photographer','wedding-photographer'),
  ('Event Photographer','event-photographer'),
  ('Portrait Photographer','portrait-photographer'),
  ('Food Photographer','food-photographer'),
  ('Commercial Photographer','commercial-photographer'),
  ('Wildlife Photographer','wildlife-photographer'),
  ('Travel Photographer','travel-photographer'),
  ('Real Estate Photographer','real-estate-photographer'),
  ('Automotive Photographer','automotive-photographer'),
  ('Photo Editor','photo-editor'),
  ('Photo Retoucher','photo-retoucher'),
  ('Studio Photographer','studio-photographer'),
  ('Instagram Influencer','instagram-influencer'),
  ('YouTube Creator','youtube-creator'),
  ('Lifestyle Influencer','lifestyle-influencer'),
  ('Fashion Influencer','fashion-influencer'),
  ('Beauty Influencer','beauty-influencer'),
  ('Fitness Influencer','fitness-influencer'),
  ('Food Influencer','food-influencer'),
  ('Travel Influencer','travel-influencer'),
  ('Tech Influencer','tech-influencer'),
  ('Gaming Influencer','gaming-influencer'),
  ('Finance Influencer','finance-influencer'),
  ('Education Influencer','education-influencer'),
  ('Parenting Influencer','parenting-influencer'),
  ('Regional Language Influencer','regional-language-influencer'),
  ('Micro-influencer','micro-influencer'),
  ('UGC Creator','ugc-creator'),
  ('Social Media Influencer','social-media-influencer'),
  ('Brand Ambassador','brand-ambassador'),
  ('Influencer Campaign Manager','influencer-campaign-manager'),
  ('Content Creator','content-creator'),
  ('Content Writer','content-writer'),
  ('Copywriter','copywriter'),
  ('Scriptwriter','scriptwriter'),
  ('Blog Writer','blog-writer'),
  ('Technical Writer','technical-writer'),
  ('Creative Writer','creative-writer'),
  ('Storyteller','storyteller'),
  ('Travel Blogger','travel-blogger'),
  ('Food Blogger','food-blogger'),
  ('Fashion Blogger','fashion-blogger'),
  ('YouTube Scriptwriter','youtube-scriptwriter'),
  ('Social Media Content Creator','social-media-content-creator'),
  ('Podcast Host','podcast-host'),
  ('Newsletter Writer','newsletter-writer'),
  ('Content Strategist','content-strategist'),
  ('Ghostwriter','ghostwriter'),
  ('Digital Marketing Specialist','digital-marketing-specialist'),
  ('SEO Specialist','seo-specialist'),
  ('SEM Specialist','sem-specialist'),
  ('Performance Marketer','performance-marketer'),
  ('Google Ads Specialist','google-ads-specialist'),
  ('Meta Ads Specialist','meta-ads-specialist'),
  ('Social Media Marketer','social-media-marketer'),
  ('Email Marketing Specialist','email-marketing-specialist'),
  ('Affiliate Marketer','affiliate-marketer'),
  ('Growth Marketer','growth-marketer'),
  ('Marketing Analyst','marketing-analyst'),
  ('Conversion Rate Optimisation Specialist','conversion-rate-optimisation-specialist'),
  ('Marketing Automation Specialist','marketing-automation-specialist'),
  ('PPC Specialist','ppc-specialist'),
  ('Digital Campaign Manager','digital-campaign-manager'),
  ('2D Animator','2d-animator'),
  ('3D Animator','3d-animator'),
  ('Motion Graphics Designer','motion-graphics-designer'),
  ('VFX Artist','vfx-artist'),
  ('Visual Effects Supervisor','visual-effects-supervisor'),
  ('Character Animator','character-animator'),
  ('3D Modeler','3d-modeler'),
  ('3D Artist','3d-artist'),
  ('3D Rendering Artist','3d-rendering-artist'),
  ('Compositor','compositor'),
  ('Rigging Artist','rigging-artist'),
  ('Game Animator','game-animator'),
  ('Stop Motion Animator','stop-motion-animator'),
  ('Motion Designer','motion-designer'),
  ('UI Designer','ui-designer'),
  ('UX Designer','ux-designer'),
  ('UI/UX Designer','ui-ux-designer'),
  ('Web Designer','web-designer'),
  ('Frontend Developer','frontend-developer'),
  ('Backend Developer','backend-developer'),
  ('Full Stack Developer','full-stack-developer'),
  ('Mobile App Developer','mobile-app-developer'),
  ('WordPress Developer','wordpress-developer'),
  ('Webflow Developer','webflow-developer'),
  ('No-code Developer','no-code-developer'),
  ('Product Designer','product-designer'),
  ('UX Researcher','ux-researcher'),
  ('Software Developer','software-developer'),
  ('Webflow Specialist','webflow-specialist'),
  ('Music Producer','music-producer'),
  ('Music Composer','music-composer'),
  ('Sound Engineer','sound-engineer'),
  ('Audio Engineer','audio-engineer'),
  ('Sound Designer','sound-designer'),
  ('Voice-over Artist','voice-over-artist'),
  ('Dubbing Artist','dubbing-artist'),
  ('Podcast Editor','podcast-editor'),
  ('Audio Editor','audio-editor'),
  ('Mixing Engineer','mixing-engineer'),
  ('Mastering Engineer','mastering-engineer'),
  ('Singer','singer'),
  ('Musician','musician'),
  ('DJ','dj'),
  ('Background Score Composer','background-score-composer'),
  ('Event Manager','event-manager'),
  ('Event Planner','event-planner'),
  ('Wedding Planner','wedding-planner'),
  ('Event Coordinator','event-coordinator'),
  ('Stage Manager','stage-manager'),
  ('Event Videographer','event-videographer'),
  ('Exhibition Designer','exhibition-designer'),
  ('Set Designer','set-designer'),
  ('Production Manager','production-manager'),
  ('Live Event Producer','live-event-producer'),
  ('Lighting Designer','lighting-designer'),
  ('Event Host','event-host'),
  ('Emcee / Anchor','emcee-anchor'),
  ('Event Marketing Specialist','event-marketing-specialist'),
  ('Brand Strategist','brand-strategist'),
  ('Creative Director','creative-director'),
  ('Advertising Executive','advertising-executive'),
  ('Campaign Manager','campaign-manager'),
  ('Brand Manager','brand-manager'),
  ('Art Director','art-director'),
  ('Creative Producer','creative-producer'),
  ('Advertising Copywriter','advertising-copywriter'),
  ('Media Planner','media-planner'),
  ('Media Buyer','media-buyer'),
  ('Marketing Consultant','marketing-consultant'),
  ('Brand Consultant','brand-consultant'),
  ('Account Manager','account-manager'),
  ('Advertising Film Producer','advertising-film-producer'),
  ('AI Content Creator','ai-content-creator'),
  ('AI Video Creator','ai-video-creator'),
  ('AI Image Creator','ai-image-creator'),
  ('Generative AI Specialist','generative-ai-specialist'),
  ('AI Automation Specialist','ai-automation-specialist'),
  ('Prompt Engineer','prompt-engineer'),
  ('AI Video Editor','ai-video-editor'),
  ('AI Creative Designer','ai-creative-designer'),
  ('AI Artist','ai-artist'),
  ('AR/VR Developer','ar-vr-developer'),
  ('Virtual Production Specialist','virtual-production-specialist'),
  ('3D AI Artist','3d-ai-artist'),
  ('Fashion Designer','fashion-designer'),
  ('Fashion Stylist','fashion-stylist'),
  ('Personal Stylist','personal-stylist'),
  ('Fashion Model','fashion-model'),
  ('Makeup Artist','makeup-artist'),
  ('Hair Stylist','hair-stylist'),
  ('Beauty Artist','beauty-artist'),
  ('Fashion Consultant','fashion-consultant'),
  ('Costume Designer','costume-designer'),
  ('Fashion Content Creator','fashion-content-creator'),
  ('Jewellery Designer','jewellery-designer'),
  ('Lifestyle Consultant','lifestyle-consultant'),
  ('PR Specialist','pr-specialist'),
  ('Public Relations Manager','public-relations-manager'),
  ('Communications Specialist','communications-specialist'),
  ('Media Relations Specialist','media-relations-specialist'),
  ('Corporate Communications Manager','corporate-communications-manager'),
  ('Press Release Writer','press-release-writer'),
  ('Reputation Management Specialist','reputation-management-specialist'),
  ('Media Spokesperson','media-spokesperson'),
  ('PR Consultant','pr-consultant'),
  ('Influencer Relations Manager','influencer-relations-manager'),
  ('Business Consultant','business-consultant'),
  ('Creative Consultant','creative-consultant'),
  ('Startup Consultant','startup-consultant'),
  ('Business Development Specialist','business-development-specialist'),
  ('Partnership Manager','partnership-manager'),
  ('Sponsorship Manager','sponsorship-manager'),
  ('Talent Manager','talent-manager'),
  ('Creator Manager','creator-manager'),
  ('Project Manager','project-manager'),
  ('Community Manager','community-manager'),
  ('Business Strategist','business-strategist'),
  ('Journalist','journalist'),
  ('News Reporter','news-reporter'),
  ('News Anchor','news-anchor'),
  ('Video Journalist','video-journalist'),
  ('Photojournalist','photojournalist'),
  ('Documentary Journalist','documentary-journalist'),
  ('Media Producer','media-producer'),
  ('News Editor','news-editor'),
  ('Feature Writer','feature-writer'),
  ('Investigative Journalist','investigative-journalist'),
  ('Media Researcher','media-researcher'),
  ('Online Educator','online-educator'),
  ('Course Creator','course-creator'),
  ('Corporate Trainer','corporate-trainer'),
  ('Skill Development Trainer','skill-development-trainer'),
  ('Educational Content Creator','educational-content-creator'),
  ('Instructional Designer','instructional-designer'),
  ('E-learning Specialist','e-learning-specialist'),
  ('Public Speaker','public-speaker'),
  ('Workshop Facilitator','workshop-facilitator'),
  ('Career Coach','career-coach'),
  ('Chef','chef'),
  ('Food Stylist','food-stylist'),
  ('Food Consultant','food-consultant'),
  ('Restaurant Consultant','restaurant-consultant'),
  ('Food Content Creator','food-content-creator'),
  ('Culinary Photographer','culinary-photographer'),
  ('Recipe Developer','recipe-developer'),
  ('Hospitality Consultant','hospitality-consultant'),
  ('Restaurant Marketing Specialist','restaurant-marketing-specialist')
on conflict do nothing;

insert into public.professional_role_categories (role_id,category_id) select r.id,c.id from (values
  ('Video Editor','video-and-film-production'),
  ('Film Editor','video-and-film-production'),
  ('Video Producer','video-and-film-production'),
  ('Videographer','video-and-film-production'),
  ('Cinematographer','video-and-film-production'),
  ('Director','video-and-film-production'),
  ('Assistant Director','video-and-film-production'),
  ('Camera Operator','video-and-film-production'),
  ('Drone Videographer','video-and-film-production'),
  ('Colorist / Color Grading Artist','video-and-film-production'),
  ('Video Content Producer','video-and-film-production'),
  ('Documentary Filmmaker','video-and-film-production'),
  ('Short-form Video Editor','video-and-film-production'),
  ('Wedding Film Editor','video-and-film-production'),
  ('Commercial Video Producer','video-and-film-production'),
  ('Post-production Specialist','video-and-film-production'),
  ('Video Production Assistant','video-and-film-production'),
  ('Graphic Designer','graphic-and-visual-design'),
  ('Logo Designer','graphic-and-visual-design'),
  ('Brand Identity Designer','graphic-and-visual-design'),
  ('Visual Designer','graphic-and-visual-design'),
  ('Social Media Designer','graphic-and-visual-design'),
  ('Creative Designer','graphic-and-visual-design'),
  ('Packaging Designer','graphic-and-visual-design'),
  ('Print Designer','graphic-and-visual-design'),
  ('Advertising Designer','graphic-and-visual-design'),
  ('Poster Designer','graphic-and-visual-design'),
  ('Thumbnail Designer','graphic-and-visual-design'),
  ('Presentation Designer','graphic-and-visual-design'),
  ('Illustrator','graphic-and-visual-design'),
  ('Photoshop Artist','graphic-and-visual-design'),
  ('Digital Artist','graphic-and-visual-design'),
  ('Infographic Designer','graphic-and-visual-design'),
  ('Photographer','photography'),
  ('Product Photographer','photography'),
  ('Fashion Photographer','photography'),
  ('Wedding Photographer','photography'),
  ('Event Photographer','photography'),
  ('Portrait Photographer','photography'),
  ('Food Photographer','photography'),
  ('Commercial Photographer','photography'),
  ('Wildlife Photographer','photography'),
  ('Travel Photographer','photography'),
  ('Real Estate Photographer','photography'),
  ('Automotive Photographer','photography'),
  ('Photo Editor','photography'),
  ('Photo Retoucher','photography'),
  ('Studio Photographer','photography'),
  ('Instagram Influencer','influencers-and-social-media'),
  ('YouTube Creator','influencers-and-social-media'),
  ('Lifestyle Influencer','influencers-and-social-media'),
  ('Fashion Influencer','influencers-and-social-media'),
  ('Beauty Influencer','influencers-and-social-media'),
  ('Fitness Influencer','influencers-and-social-media'),
  ('Food Influencer','influencers-and-social-media'),
  ('Travel Influencer','influencers-and-social-media'),
  ('Tech Influencer','influencers-and-social-media'),
  ('Gaming Influencer','influencers-and-social-media'),
  ('Finance Influencer','influencers-and-social-media'),
  ('Education Influencer','influencers-and-social-media'),
  ('Parenting Influencer','influencers-and-social-media'),
  ('Regional Language Influencer','influencers-and-social-media'),
  ('Micro-influencer','influencers-and-social-media'),
  ('UGC Creator','influencers-and-social-media'),
  ('Social Media Influencer','influencers-and-social-media'),
  ('Brand Ambassador','influencers-and-social-media'),
  ('Influencer Campaign Manager','influencers-and-social-media'),
  ('Content Creator','content-creation-and-writing'),
  ('Content Writer','content-creation-and-writing'),
  ('Copywriter','content-creation-and-writing'),
  ('Scriptwriter','content-creation-and-writing'),
  ('Blog Writer','content-creation-and-writing'),
  ('Technical Writer','content-creation-and-writing'),
  ('Creative Writer','content-creation-and-writing'),
  ('Storyteller','content-creation-and-writing'),
  ('Travel Blogger','content-creation-and-writing'),
  ('Food Blogger','content-creation-and-writing'),
  ('Fashion Blogger','content-creation-and-writing'),
  ('YouTube Scriptwriter','content-creation-and-writing'),
  ('Social Media Content Creator','content-creation-and-writing'),
  ('Podcast Host','content-creation-and-writing'),
  ('Newsletter Writer','content-creation-and-writing'),
  ('Content Strategist','content-creation-and-writing'),
  ('Ghostwriter','content-creation-and-writing'),
  ('Digital Marketing Specialist','digital-marketing'),
  ('SEO Specialist','digital-marketing'),
  ('SEM Specialist','digital-marketing'),
  ('Performance Marketer','digital-marketing'),
  ('Google Ads Specialist','digital-marketing'),
  ('Meta Ads Specialist','digital-marketing'),
  ('Social Media Marketer','digital-marketing'),
  ('Email Marketing Specialist','digital-marketing'),
  ('Affiliate Marketer','digital-marketing'),
  ('Growth Marketer','digital-marketing'),
  ('Marketing Analyst','digital-marketing'),
  ('Conversion Rate Optimisation Specialist','digital-marketing'),
  ('Marketing Automation Specialist','digital-marketing'),
  ('PPC Specialist','digital-marketing'),
  ('Digital Campaign Manager','digital-marketing'),
  ('2D Animator','animation-and-motion-graphics'),
  ('3D Animator','animation-and-motion-graphics'),
  ('Motion Graphics Designer','animation-and-motion-graphics'),
  ('VFX Artist','animation-and-motion-graphics'),
  ('Visual Effects Supervisor','animation-and-motion-graphics'),
  ('Character Animator','animation-and-motion-graphics'),
  ('3D Modeler','animation-and-motion-graphics'),
  ('3D Artist','animation-and-motion-graphics'),
  ('3D Rendering Artist','animation-and-motion-graphics'),
  ('Compositor','animation-and-motion-graphics'),
  ('Rigging Artist','animation-and-motion-graphics'),
  ('Game Animator','animation-and-motion-graphics'),
  ('Stop Motion Animator','animation-and-motion-graphics'),
  ('Motion Designer','animation-and-motion-graphics'),
  ('UI Designer','web-technology-and-design'),
  ('UX Designer','web-technology-and-design'),
  ('UI/UX Designer','web-technology-and-design'),
  ('Web Designer','web-technology-and-design'),
  ('Frontend Developer','web-technology-and-design'),
  ('Backend Developer','web-technology-and-design'),
  ('Full Stack Developer','web-technology-and-design'),
  ('Mobile App Developer','web-technology-and-design'),
  ('WordPress Developer','web-technology-and-design'),
  ('Webflow Developer','web-technology-and-design'),
  ('No-code Developer','web-technology-and-design'),
  ('Product Designer','web-technology-and-design'),
  ('UX Researcher','web-technology-and-design'),
  ('Software Developer','web-technology-and-design'),
  ('Webflow Specialist','web-technology-and-design'),
  ('Music Producer','audio-and-music-production'),
  ('Music Composer','audio-and-music-production'),
  ('Sound Engineer','audio-and-music-production'),
  ('Audio Engineer','audio-and-music-production'),
  ('Sound Designer','audio-and-music-production'),
  ('Voice-over Artist','audio-and-music-production'),
  ('Dubbing Artist','audio-and-music-production'),
  ('Podcast Editor','audio-and-music-production'),
  ('Audio Editor','audio-and-music-production'),
  ('Mixing Engineer','audio-and-music-production'),
  ('Mastering Engineer','audio-and-music-production'),
  ('Singer','audio-and-music-production'),
  ('Musician','audio-and-music-production'),
  ('DJ','audio-and-music-production'),
  ('Background Score Composer','audio-and-music-production'),
  ('Event Manager','events-and-production'),
  ('Event Planner','events-and-production'),
  ('Wedding Planner','events-and-production'),
  ('Event Coordinator','events-and-production'),
  ('Stage Manager','events-and-production'),
  ('Event Photographer','events-and-production'),
  ('Event Videographer','events-and-production'),
  ('Exhibition Designer','events-and-production'),
  ('Set Designer','events-and-production'),
  ('Production Manager','events-and-production'),
  ('Live Event Producer','events-and-production'),
  ('Lighting Designer','events-and-production'),
  ('Event Host','events-and-production'),
  ('Emcee / Anchor','events-and-production'),
  ('Event Marketing Specialist','events-and-production'),
  ('Brand Strategist','advertising-and-branding'),
  ('Creative Director','advertising-and-branding'),
  ('Advertising Executive','advertising-and-branding'),
  ('Campaign Manager','advertising-and-branding'),
  ('Brand Manager','advertising-and-branding'),
  ('Art Director','advertising-and-branding'),
  ('Creative Producer','advertising-and-branding'),
  ('Advertising Copywriter','advertising-and-branding'),
  ('Media Planner','advertising-and-branding'),
  ('Media Buyer','advertising-and-branding'),
  ('Marketing Consultant','advertising-and-branding'),
  ('Brand Consultant','advertising-and-branding'),
  ('Account Manager','advertising-and-branding'),
  ('Advertising Film Producer','advertising-and-branding'),
  ('AI Content Creator','ai-and-emerging-technologies'),
  ('AI Video Creator','ai-and-emerging-technologies'),
  ('AI Image Creator','ai-and-emerging-technologies'),
  ('Generative AI Specialist','ai-and-emerging-technologies'),
  ('AI Automation Specialist','ai-and-emerging-technologies'),
  ('Prompt Engineer','ai-and-emerging-technologies'),
  ('AI Video Editor','ai-and-emerging-technologies'),
  ('AI Creative Designer','ai-and-emerging-technologies'),
  ('AI Artist','ai-and-emerging-technologies'),
  ('AR/VR Developer','ai-and-emerging-technologies'),
  ('Virtual Production Specialist','ai-and-emerging-technologies'),
  ('3D AI Artist','ai-and-emerging-technologies'),
  ('Fashion Designer','fashion-and-lifestyle'),
  ('Fashion Stylist','fashion-and-lifestyle'),
  ('Personal Stylist','fashion-and-lifestyle'),
  ('Fashion Model','fashion-and-lifestyle'),
  ('Makeup Artist','fashion-and-lifestyle'),
  ('Hair Stylist','fashion-and-lifestyle'),
  ('Beauty Artist','fashion-and-lifestyle'),
  ('Fashion Consultant','fashion-and-lifestyle'),
  ('Costume Designer','fashion-and-lifestyle'),
  ('Fashion Content Creator','fashion-and-lifestyle'),
  ('Jewellery Designer','fashion-and-lifestyle'),
  ('Lifestyle Consultant','fashion-and-lifestyle'),
  ('PR Specialist','public-relations-and-communications'),
  ('Public Relations Manager','public-relations-and-communications'),
  ('Communications Specialist','public-relations-and-communications'),
  ('Media Relations Specialist','public-relations-and-communications'),
  ('Corporate Communications Manager','public-relations-and-communications'),
  ('Press Release Writer','public-relations-and-communications'),
  ('Reputation Management Specialist','public-relations-and-communications'),
  ('Media Spokesperson','public-relations-and-communications'),
  ('PR Consultant','public-relations-and-communications'),
  ('Influencer Relations Manager','public-relations-and-communications'),
  ('Business Consultant','business-and-creative-consulting'),
  ('Creative Consultant','business-and-creative-consulting'),
  ('Marketing Consultant','business-and-creative-consulting'),
  ('Startup Consultant','business-and-creative-consulting'),
  ('Business Development Specialist','business-and-creative-consulting'),
  ('Partnership Manager','business-and-creative-consulting'),
  ('Sponsorship Manager','business-and-creative-consulting'),
  ('Talent Manager','business-and-creative-consulting'),
  ('Creator Manager','business-and-creative-consulting'),
  ('Project Manager','business-and-creative-consulting'),
  ('Community Manager','business-and-creative-consulting'),
  ('Business Strategist','business-and-creative-consulting'),
  ('Journalist','journalism-and-media'),
  ('News Reporter','journalism-and-media'),
  ('News Anchor','journalism-and-media'),
  ('Video Journalist','journalism-and-media'),
  ('Photojournalist','journalism-and-media'),
  ('Documentary Journalist','journalism-and-media'),
  ('Media Producer','journalism-and-media'),
  ('News Editor','journalism-and-media'),
  ('Feature Writer','journalism-and-media'),
  ('Investigative Journalist','journalism-and-media'),
  ('Media Researcher','journalism-and-media'),
  ('Online Educator','education-and-training'),
  ('Course Creator','education-and-training'),
  ('Corporate Trainer','education-and-training'),
  ('Skill Development Trainer','education-and-training'),
  ('Educational Content Creator','education-and-training'),
  ('Instructional Designer','education-and-training'),
  ('E-learning Specialist','education-and-training'),
  ('Public Speaker','education-and-training'),
  ('Workshop Facilitator','education-and-training'),
  ('Career Coach','education-and-training'),
  ('Chef','food-and-hospitality'),
  ('Food Stylist','food-and-hospitality'),
  ('Food Consultant','food-and-hospitality'),
  ('Restaurant Consultant','food-and-hospitality'),
  ('Food Content Creator','food-and-hospitality'),
  ('Culinary Photographer','food-and-hospitality'),
  ('Recipe Developer','food-and-hospitality'),
  ('Hospitality Consultant','food-and-hospitality'),
  ('Restaurant Marketing Specialist','food-and-hospitality')) v(role_name,category_slug) join public.professional_roles r on r.name=v.role_name join public.professional_categories c on c.slug=v.category_slug on conflict do nothing;

insert into public.skills (name,slug) values
  ('Video Editing','video-editing'),
  ('Color Grading','color-grading'),
  ('Motion Graphics','motion-graphics'),
  ('Cinematography','cinematography'),
  ('Video Storytelling','video-storytelling'),
  ('Short-form Editing','short-form-editing'),
  ('Post-production','post-production'),
  ('Graphic Design','graphic-design'),
  ('Brand Identity','brand-identity'),
  ('Typography','typography'),
  ('Illustration','illustration'),
  ('Layout Design','layout-design'),
  ('Packaging Design','packaging-design'),
  ('Photo Editing','photo-editing'),
  ('Photo Retouching','photo-retouching'),
  ('Product Photography','product-photography'),
  ('Portrait Lighting','portrait-lighting'),
  ('Studio Lighting','studio-lighting'),
  ('UGC Production','ugc-production'),
  ('Influencer Campaigns','influencer-campaigns'),
  ('Community Engagement','community-engagement'),
  ('Social Media Content Planning','social-media-content-planning'),
  ('Copywriting','copywriting'),
  ('Scriptwriting','scriptwriting'),
  ('SEO Writing','seo-writing'),
  ('Content Strategy','content-strategy'),
  ('Long-form Writing','long-form-writing'),
  ('Search Engine Optimization','search-engine-optimization'),
  ('Paid Search','paid-search'),
  ('Performance Marketing','performance-marketing'),
  ('Campaign Analytics','campaign-analytics'),
  ('Email Campaigns','email-campaigns'),
  ('2D Animation','2d-animation'),
  ('3D Modeling','3d-modeling'),
  ('Compositing','compositing'),
  ('Visual Effects','visual-effects'),
  ('Character Animation','character-animation'),
  ('UI Design','ui-design'),
  ('UX Research','ux-research'),
  ('Responsive Web Design','responsive-web-design'),
  ('Frontend Development','frontend-development'),
  ('No-code Development','no-code-development'),
  ('Audio Editing','audio-editing'),
  ('Audio Mixing','audio-mixing'),
  ('Audio Mastering','audio-mastering'),
  ('Sound Design','sound-design'),
  ('Voice-over Recording','voice-over-recording'),
  ('Event Planning','event-planning'),
  ('Stage Production','stage-production'),
  ('Lighting Design','lighting-design'),
  ('Live Event Production','live-event-production'),
  ('Brand Strategy','brand-strategy'),
  ('Media Planning','media-planning'),
  ('Campaign Management','campaign-management'),
  ('Creative Direction','creative-direction'),
  ('Generative AI','generative-ai'),
  ('Prompt Design','prompt-design'),
  ('AI Workflow Automation','ai-workflow-automation'),
  ('AI Video Production','ai-video-production'),
  ('Fashion Styling','fashion-styling'),
  ('Makeup Artistry','makeup-artistry'),
  ('Costume Design','costume-design'),
  ('Personal Styling','personal-styling'),
  ('Media Relations','media-relations'),
  ('Public Relations','public-relations'),
  ('Corporate Communications','corporate-communications'),
  ('Reputation Management','reputation-management'),
  ('Business Development','business-development'),
  ('Partnership Development','partnership-development'),
  ('Project Management','project-management'),
  ('Community Management','community-management'),
  ('News Reporting','news-reporting'),
  ('Video Journalism','video-journalism'),
  ('Photojournalism','photojournalism'),
  ('Investigative Research','investigative-research'),
  ('Instructional Design','instructional-design'),
  ('Workshop Facilitation','workshop-facilitation'),
  ('Online Course Production','online-course-production'),
  ('Public Speaking','public-speaking'),
  ('Recipe Development','recipe-development'),
  ('Food Styling','food-styling'),
  ('Culinary Photography','culinary-photography'),
  ('Hospitality Consulting','hospitality-consulting')
on conflict do nothing;

insert into public.skill_categories (skill_id,category_id) select s.id,c.id from (values
  ('Video Editing','video-and-film-production'),
  ('Color Grading','video-and-film-production'),
  ('Motion Graphics','video-and-film-production'),
  ('Cinematography','video-and-film-production'),
  ('Video Storytelling','video-and-film-production'),
  ('Short-form Editing','video-and-film-production'),
  ('Post-production','video-and-film-production'),
  ('Graphic Design','graphic-and-visual-design'),
  ('Brand Identity','graphic-and-visual-design'),
  ('Typography','graphic-and-visual-design'),
  ('Illustration','graphic-and-visual-design'),
  ('Layout Design','graphic-and-visual-design'),
  ('Packaging Design','graphic-and-visual-design'),
  ('Photo Editing','photography'),
  ('Photo Retouching','photography'),
  ('Product Photography','photography'),
  ('Portrait Lighting','photography'),
  ('Studio Lighting','photography'),
  ('UGC Production','influencers-and-social-media'),
  ('Influencer Campaigns','influencers-and-social-media'),
  ('Community Engagement','influencers-and-social-media'),
  ('Social Media Content Planning','influencers-and-social-media'),
  ('Copywriting','content-creation-and-writing'),
  ('Scriptwriting','content-creation-and-writing'),
  ('SEO Writing','content-creation-and-writing'),
  ('Content Strategy','content-creation-and-writing'),
  ('Long-form Writing','content-creation-and-writing'),
  ('Search Engine Optimization','digital-marketing'),
  ('Paid Search','digital-marketing'),
  ('Performance Marketing','digital-marketing'),
  ('Campaign Analytics','digital-marketing'),
  ('Email Campaigns','digital-marketing'),
  ('2D Animation','animation-and-motion-graphics'),
  ('3D Modeling','animation-and-motion-graphics'),
  ('Compositing','animation-and-motion-graphics'),
  ('Visual Effects','animation-and-motion-graphics'),
  ('Character Animation','animation-and-motion-graphics'),
  ('UI Design','web-technology-and-design'),
  ('UX Research','web-technology-and-design'),
  ('Responsive Web Design','web-technology-and-design'),
  ('Frontend Development','web-technology-and-design'),
  ('No-code Development','web-technology-and-design'),
  ('Audio Editing','audio-and-music-production'),
  ('Audio Mixing','audio-and-music-production'),
  ('Audio Mastering','audio-and-music-production'),
  ('Sound Design','audio-and-music-production'),
  ('Voice-over Recording','audio-and-music-production'),
  ('Event Planning','events-and-production'),
  ('Stage Production','events-and-production'),
  ('Lighting Design','events-and-production'),
  ('Live Event Production','events-and-production'),
  ('Brand Strategy','advertising-and-branding'),
  ('Media Planning','advertising-and-branding'),
  ('Campaign Management','advertising-and-branding'),
  ('Creative Direction','advertising-and-branding'),
  ('Generative AI','ai-and-emerging-technologies'),
  ('Prompt Design','ai-and-emerging-technologies'),
  ('AI Workflow Automation','ai-and-emerging-technologies'),
  ('AI Video Production','ai-and-emerging-technologies'),
  ('Fashion Styling','fashion-and-lifestyle'),
  ('Makeup Artistry','fashion-and-lifestyle'),
  ('Costume Design','fashion-and-lifestyle'),
  ('Personal Styling','fashion-and-lifestyle'),
  ('Media Relations','public-relations-and-communications'),
  ('Public Relations','public-relations-and-communications'),
  ('Corporate Communications','public-relations-and-communications'),
  ('Reputation Management','public-relations-and-communications'),
  ('Business Development','business-and-creative-consulting'),
  ('Partnership Development','business-and-creative-consulting'),
  ('Project Management','business-and-creative-consulting'),
  ('Community Management','business-and-creative-consulting'),
  ('News Reporting','journalism-and-media'),
  ('Video Journalism','journalism-and-media'),
  ('Photojournalism','journalism-and-media'),
  ('Investigative Research','journalism-and-media'),
  ('Instructional Design','education-and-training'),
  ('Workshop Facilitation','education-and-training'),
  ('Online Course Production','education-and-training'),
  ('Public Speaking','education-and-training'),
  ('Recipe Development','food-and-hospitality'),
  ('Food Styling','food-and-hospitality'),
  ('Culinary Photography','food-and-hospitality'),
  ('Hospitality Consulting','food-and-hospitality')) v(skill_name,category_slug) join public.skills s on s.name=v.skill_name join public.professional_categories c on c.slug=v.category_slug on conflict do nothing;

insert into public.professional_tools (name,slug) values
  ('Adobe Premiere Pro','adobe-premiere-pro'),
  ('DaVinci Resolve','davinci-resolve'),
  ('After Effects','after-effects'),
  ('Final Cut Pro','final-cut-pro'),
  ('Photoshop','photoshop'),
  ('Illustrator','illustrator'),
  ('Figma','figma'),
  ('Canva','canva'),
  ('InDesign','indesign'),
  ('Lightroom','lightroom'),
  ('Capture One','capture-one'),
  ('Blender','blender'),
  ('Maya','maya'),
  ('Cinema 4D','cinema-4d'),
  ('Google Ads','google-ads'),
  ('Meta Ads Manager','meta-ads-manager'),
  ('Google Analytics','google-analytics'),
  ('HubSpot','hubspot'),
  ('React','react'),
  ('Next.js','next-js'),
  ('WordPress','wordpress'),
  ('Webflow','webflow'),
  ('Pro Tools','pro-tools'),
  ('FL Studio','fl-studio'),
  ('Logic Pro','logic-pro'),
  ('Audacity','audacity'),
  ('ChatGPT','chatgpt'),
  ('Midjourney','midjourney'),
  ('Runway','runway'),
  ('Adobe Firefly','adobe-firefly'),
  ('Stable Diffusion','stable-diffusion')
on conflict do nothing;

insert into public.professional_tool_categories (tool_id,category_id) select t.id,c.id from (values
  ('Adobe Premiere Pro','video-and-film-production'),
  ('DaVinci Resolve','video-and-film-production'),
  ('After Effects','video-and-film-production'),
  ('Final Cut Pro','video-and-film-production'),
  ('Photoshop','graphic-and-visual-design'),
  ('Illustrator','graphic-and-visual-design'),
  ('Figma','graphic-and-visual-design'),
  ('Canva','graphic-and-visual-design'),
  ('InDesign','graphic-and-visual-design'),
  ('Lightroom','photography'),
  ('Capture One','photography'),
  ('Blender','animation-and-motion-graphics'),
  ('Maya','animation-and-motion-graphics'),
  ('Cinema 4D','animation-and-motion-graphics'),
  ('Google Ads','digital-marketing'),
  ('Meta Ads Manager','digital-marketing'),
  ('Google Analytics','digital-marketing'),
  ('HubSpot','digital-marketing'),
  ('React','web-technology-and-design'),
  ('Next.js','web-technology-and-design'),
  ('WordPress','web-technology-and-design'),
  ('Webflow','web-technology-and-design'),
  ('Pro Tools','audio-and-music-production'),
  ('FL Studio','audio-and-music-production'),
  ('Logic Pro','audio-and-music-production'),
  ('Audacity','audio-and-music-production'),
  ('ChatGPT','ai-and-emerging-technologies'),
  ('Midjourney','ai-and-emerging-technologies'),
  ('Runway','ai-and-emerging-technologies'),
  ('Adobe Firefly','ai-and-emerging-technologies'),
  ('Stable Diffusion','ai-and-emerging-technologies')) v(tool_name,category_slug) join public.professional_tools t on t.name=v.tool_name join public.professional_categories c on c.slug=v.category_slug on conflict do nothing;

insert into public.taxonomy_aliases (alias,skill_id) select 'Video Editing',id from public.skills where name='Video Editing' on conflict (alias) do nothing;
insert into public.taxonomy_aliases (alias,skill_id) select 'SEO',id from public.skills where name='Search Engine Optimization' on conflict (alias) do nothing;
insert into public.taxonomy_aliases (alias,tool_id) select 'Premiere Pro',id from public.professional_tools where name='Adobe Premiere Pro' on conflict (alias) do nothing;
insert into public.taxonomy_aliases (alias,tool_id) select 'Resolve',id from public.professional_tools where name='DaVinci Resolve' on conflict (alias) do nothing;
insert into public.taxonomy_aliases (alias,tool_id) select 'Facebook Ads Manager',id from public.professional_tools where name='Meta Ads Manager' on conflict (alias) do nothing;
insert into public.taxonomy_aliases (alias,skill_id) select 'User Generated Content',id from public.skills where name='UGC Production' on conflict (alias) do nothing;

commit;
