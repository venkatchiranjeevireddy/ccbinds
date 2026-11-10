-- Admins use private Admin IDs and passwords, separate from Supabase Auth.
-- Run once after 202611100004_admin_accounts.sql. Legacy Auth-user roster rows
-- are discarded during conversion; existing static admin_id/password_hash rows
-- are preserved. Add any missing Admins with the INSERT example below.
begin;

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

commit;

-- Provision each Admin manually in the SQL Editor. Repeat with a unique Admin ID:
-- insert into public.admin_accounts (admin_id, password_hash)
-- values ('your-admin-id', extensions.crypt('your-password', extensions.gen_salt('bf')));
