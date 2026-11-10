-- Separate Admin authorization roster. Passwords remain exclusively in
-- Supabase Auth; this table stores only who is authorized for the Admin panel.
begin;

create table if not exists public.admin_accounts (
  user_id uuid primary key references auth.users (id) on delete cascade,
  status text not null default 'active' check (status in ('active', 'suspended'))
);
alter table public.admin_accounts
  drop column if exists invited_by,
  drop column if exists created_at,
  drop column if exists updated_at;

alter table public.admin_accounts enable row level security;

-- Preserve any Admins assigned before this dedicated table was introduced.
insert into public.admin_accounts (user_id)
select id from public.user_profiles where account_type = 'admin'
on conflict (user_id) do nothing;

-- User profiles remain the shared identity record for foreign-key references,
-- while Admin authorization is held in admin_accounts.
update public.user_profiles set account_type = null where account_type = 'admin';

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.admin_accounts a
    where a.user_id = (select auth.uid()) and a.status = 'active'
  )
$$;

drop policy if exists admin_accounts_read_active_admins on public.admin_accounts;
drop policy if exists admin_accounts_read_admin_roster on public.admin_accounts;
create policy admin_accounts_read_admin_roster on public.admin_accounts
  for select to authenticated using ((select public.is_admin()));

revoke all on public.admin_accounts from anon, authenticated;
grant select on public.admin_accounts to authenticated;

commit;
