begin;

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

commit;
