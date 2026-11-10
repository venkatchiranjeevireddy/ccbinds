-- Apply after 202611100002_ccb_platform_schema.sql.
-- Adds links from Member/Client profiles to R2 media metadata records.
begin;

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

commit;
