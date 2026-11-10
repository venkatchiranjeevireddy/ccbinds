begin;

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

commit;
