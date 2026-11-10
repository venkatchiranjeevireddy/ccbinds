-- Account type is assigned once at signup and cannot be changed by the user.
-- Admin accounts are provisioned separately through trusted administrative tooling.
create table if not exists public.user_profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  account_type text check (account_type in ('member', 'client', 'admin')),
  display_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.user_profiles enable row level security;

create policy "Users can read their own profile"
  on public.user_profiles for select
  to authenticated
  using ((select auth.uid()) = id);

-- The only client-side update allowed is choosing a non-admin account type for
-- an OAuth account whose profile was created before its role was selected.
create policy "Users can set an unset account type once"
  on public.user_profiles for update
  to authenticated
  using ((select auth.uid()) = id and account_type is null)
  with check (
    (select auth.uid()) = id
    and account_type in ('member', 'client')
  );

create or replace function public.create_user_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  requested_type text;
begin
  requested_type := new.raw_user_meta_data ->> 'account_type';
  insert into public.user_profiles (id, account_type, display_name)
  values (
    new.id,
    case when requested_type in ('member', 'client') then requested_type else null end,
    nullif(new.raw_user_meta_data ->> 'display_name', '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_profile on auth.users;
create trigger on_auth_user_created_profile
  after insert on auth.users
  for each row execute procedure public.create_user_profile();

-- Existing accounts receive a profile, but no privileged role is inferred.
insert into public.user_profiles (id, account_type, display_name)
select
  users.id,
  case when users.raw_user_meta_data ->> 'account_type' in ('member', 'client')
    then users.raw_user_meta_data ->> 'account_type'
    else null
  end,
  nullif(users.raw_user_meta_data ->> 'display_name', '')
from auth.users as users
on conflict (id) do nothing;

grant select, update on public.user_profiles to authenticated;
