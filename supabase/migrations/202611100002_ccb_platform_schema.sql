-- CCB India shared platform schema
-- Run this entire script once in Supabase Dashboard > SQL Editor.
-- It creates the initial shared database for Member, Client and Admin modules.
-- Pricing, plans, membership rules and event policies are data/configuration decisions;
-- this schema intentionally does not invent those business values.

begin;

create extension if not exists pgcrypto with schema extensions;

-- -----------------------------------------------------------------------------
-- Identity and account roles
-- -----------------------------------------------------------------------------

create table if not exists public.user_profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  account_type text check (account_type in ('member', 'client', 'admin')),
  display_name text,
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.user_profiles add column if not exists avatar_url text;

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
  insert into public.user_profiles (id, account_type, display_name, avatar_url)
  values (
    new.id,
    case when requested_type in ('member', 'client') then requested_type else null end,
    nullif(new.raw_user_meta_data ->> 'display_name', ''),
    nullif(new.raw_user_meta_data ->> 'avatar_url', '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_profile on auth.users;
create trigger on_auth_user_created_profile
  after insert on auth.users
  for each row execute procedure public.create_user_profile();

insert into public.user_profiles (id, account_type, display_name, avatar_url)
select
  u.id,
  case when u.raw_user_meta_data ->> 'account_type' in ('member', 'client')
    then u.raw_user_meta_data ->> 'account_type' else null end,
  nullif(u.raw_user_meta_data ->> 'display_name', ''),
  nullif(u.raw_user_meta_data ->> 'avatar_url', '')
from auth.users u
on conflict (id) do nothing;

create or replace function public.current_account_type()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select p.account_type from public.user_profiles p where p.id = (select auth.uid())
$$;

create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.user_profiles p
    where p.id = (select auth.uid()) and p.account_type = 'admin'
  )
$$;

-- Set account type once for OAuth-created profiles; only Member or Client can
-- be selected by a signed-in user. Admin is assigned through trusted tooling.
alter table public.user_profiles enable row level security;
drop policy if exists user_profiles_read_self_or_admin on public.user_profiles;
create policy user_profiles_read_self_or_admin on public.user_profiles
  for select to authenticated using (id = (select auth.uid()) or (select public.is_admin()));
drop policy if exists user_profiles_choose_role_once on public.user_profiles;
create policy user_profiles_choose_role_once on public.user_profiles
  for update to authenticated
  using (id = (select auth.uid()) and account_type is null)
  with check (id = (select auth.uid()) and account_type in ('member', 'client'));
grant select on public.user_profiles to authenticated;
grant update (account_type) on public.user_profiles to authenticated;

-- -----------------------------------------------------------------------------
-- Reusable professional taxonomy
-- -----------------------------------------------------------------------------

create table if not exists public.professional_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  slug text not null unique,
  description text,
  is_active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.skills (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  slug text not null unique,
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- Member and Client profile data (kept separate)
-- -----------------------------------------------------------------------------

create table if not exists public.member_profiles (
  user_id uuid primary key references public.user_profiles (id) on delete cascade,
  headline text,
  bio text,
  location text,
  country_code text,
  years_experience numeric(4,1) check (years_experience is null or years_experience >= 0),
  availability text check (availability is null or availability in ('available', 'limited', 'unavailable')),
  professional_interests text[] not null default '{}',
  contact_preference text check (contact_preference is null or contact_preference in ('platform', 'email', 'none')),
  portfolio_website text,
  is_public boolean not null default false,
  insights_sharing_enabled boolean not null default false,
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.client_profiles (
  user_id uuid primary key references public.user_profiles (id) on delete cascade,
  company_name text not null,
  organization_type text,
  industry text,
  description text,
  website_url text,
  location text,
  country_code text,
  business_email text,
  business_phone text,
  verification_status text not null default 'unverified'
    check (verification_status in ('unverified', 'pending', 'verified', 'rejected')),
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.member_categories (
  member_id uuid not null references public.member_profiles (user_id) on delete cascade,
  category_id uuid not null references public.professional_categories (id) on delete restrict,
  is_primary boolean not null default false,
  created_at timestamptz not null default now(),
  primary key (member_id, category_id)
);

create unique index if not exists member_one_primary_category
  on public.member_categories (member_id) where is_primary;

create table if not exists public.member_skills (
  member_id uuid not null references public.member_profiles (user_id) on delete cascade,
  skill_id uuid not null references public.skills (id) on delete restrict,
  proficiency text check (proficiency is null or proficiency in ('beginner', 'intermediate', 'advanced', 'expert')),
  created_at timestamptz not null default now(),
  primary key (member_id, skill_id)
);

create table if not exists public.portfolio_items (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.member_profiles (user_id) on delete cascade,
  title text not null,
  description text,
  project_url text,
  visibility text not null default 'public' check (visibility in ('public', 'private')),
  sort_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- Media metadata. Binary files belong in Cloudflare R2, never in PostgreSQL.
-- -----------------------------------------------------------------------------

create table if not exists public.media_assets (
  id uuid primary key default gen_random_uuid(),
  owner_user_id uuid references public.user_profiles (id) on delete set null,
  bucket_name text not null default 'ccb-media',
  object_key text not null unique,
  original_filename text,
  mime_type text not null,
  file_size_bytes bigint not null check (file_size_bytes >= 0),
  visibility text not null default 'private' check (visibility in ('public', 'private')),
  alt_text text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Profile and company images are R2 objects. These columns reference the
-- corresponding media metadata row rather than storing image bytes in Postgres.
alter table public.member_profiles
  add column if not exists profile_media_id uuid references public.media_assets (id) on delete set null;
alter table public.client_profiles
  add column if not exists logo_media_id uuid references public.media_assets (id) on delete set null;

create table if not exists public.portfolio_item_media (
  portfolio_item_id uuid not null references public.portfolio_items (id) on delete cascade,
  media_asset_id uuid not null references public.media_assets (id) on delete cascade,
  sort_order integer not null default 0,
  primary key (portfolio_item_id, media_asset_id)
);

-- -----------------------------------------------------------------------------
-- Client discovery, work opportunities and applications
-- -----------------------------------------------------------------------------

create table if not exists public.work_opportunities (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.client_profiles (user_id) on delete cascade,
  title text not null,
  description text not null,
  budget_min numeric(12,2) check (budget_min is null or budget_min >= 0),
  budget_max numeric(12,2) check (budget_max is null or budget_max >= budget_min),
  currency_code char(3),
  professionals_required integer check (professionals_required is null or professionals_required > 0),
  experience_min_years numeric(4,1) check (experience_min_years is null or experience_min_years >= 0),
  location text,
  work_arrangement text check (work_arrangement is null or work_arrangement in ('remote', 'on_site', 'hybrid')),
  start_date date,
  deadline date,
  application_deadline timestamptz,
  additional_requirements text,
  status text not null default 'draft'
    check (status in ('draft', 'published', 'applications_closed', 'in_progress', 'completed', 'cancelled')),
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.opportunity_categories (
  opportunity_id uuid not null references public.work_opportunities (id) on delete cascade,
  category_id uuid not null references public.professional_categories (id) on delete restrict,
  primary key (opportunity_id, category_id)
);

create table if not exists public.opportunity_skills (
  opportunity_id uuid not null references public.work_opportunities (id) on delete cascade,
  skill_id uuid not null references public.skills (id) on delete restrict,
  primary key (opportunity_id, skill_id)
);

create table if not exists public.applications (
  id uuid primary key default gen_random_uuid(),
  opportunity_id uuid not null references public.work_opportunities (id) on delete cascade,
  member_id uuid not null references public.member_profiles (user_id) on delete cascade,
  cover_message text,
  status text not null default 'submitted'
    check (status in ('submitted', 'under_review', 'shortlisted', 'selected', 'rejected', 'withdrawn')),
  client_message text,
  submitted_at timestamptz not null default now(),
  status_updated_at timestamptz not null default now(),
  unique (opportunity_id, member_id)
);

create table if not exists public.application_portfolio_items (
  application_id uuid not null references public.applications (id) on delete cascade,
  portfolio_item_id uuid not null references public.portfolio_items (id) on delete cascade,
  primary key (application_id, portfolio_item_id)
);

create table if not exists public.saved_members (
  client_id uuid not null references public.client_profiles (user_id) on delete cascade,
  member_id uuid not null references public.member_profiles (user_id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (client_id, member_id)
);

create table if not exists public.client_search_history (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.client_profiles (user_id) on delete cascade,
  search_filters jsonb not null default '{}'::jsonb,
  searched_at timestamptz not null default now()
);

create table if not exists public.member_enquiries (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.client_profiles (user_id) on delete cascade,
  member_id uuid not null references public.member_profiles (user_id) on delete cascade,
  subject text not null,
  message text not null,
  status text not null default 'submitted' check (status in ('submitted', 'read', 'replied', 'closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- Programmes, events, registrations, tickets and attendance
-- -----------------------------------------------------------------------------

create table if not exists public.programs (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  slug text not null unique,
  summary text,
  description text,
  status text not null default 'draft' check (status in ('draft', 'published', 'archived')),
  starts_on date,
  ends_on date,
  created_by uuid references public.user_profiles (id) on delete set null,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_on is null or starts_on is null or ends_on >= starts_on)
);

create table if not exists public.events (
  id uuid primary key default gen_random_uuid(),
  program_id uuid references public.programs (id) on delete set null,
  title text not null,
  slug text not null unique,
  summary text,
  description text,
  status text not null default 'draft' check (status in ('draft', 'published', 'cancelled', 'completed')),
  starts_at timestamptz,
  ends_at timestamptz,
  timezone text not null default 'Asia/Kolkata',
  venue_name text,
  venue_address text,
  is_online boolean not null default false,
  registration_opens_at timestamptz,
  registration_closes_at timestamptz,
  capacity integer check (capacity is null or capacity > 0),
  registration_policy text not null default 'open' check (registration_policy in ('open', 'approval_required', 'invite_only')),
  qr_check_in_enabled boolean not null default false,
  created_by uuid references public.user_profiles (id) on delete set null,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at is null or starts_at is null or ends_at >= starts_at),
  check (registration_closes_at is null or registration_opens_at is null or registration_closes_at >= registration_opens_at)
);

create table if not exists public.program_enrollments (
  id uuid primary key default gen_random_uuid(),
  program_id uuid not null references public.programs (id) on delete cascade,
  user_id uuid not null references public.user_profiles (id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'active', 'completed', 'cancelled', 'rejected')),
  enrolled_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (program_id, user_id)
);

create table if not exists public.event_form_fields (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events (id) on delete cascade,
  field_key text not null,
  label text not null,
  field_type text not null check (field_type in ('text', 'textarea', 'email', 'phone', 'number', 'select', 'checkbox', 'date')),
  is_required boolean not null default false,
  options jsonb not null default '[]'::jsonb,
  sort_order integer not null default 0,
  unique (event_id, field_key)
);

create table if not exists public.event_registrations (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events (id) on delete cascade,
  user_id uuid references public.user_profiles (id) on delete set null,
  attendee_name text not null,
  attendee_email text not null,
  attendee_phone text,
  form_responses jsonb not null default '{}'::jsonb,
  status text not null default 'pending' check (status in ('pending', 'registered', 'waitlisted', 'cancelled', 'rejected')),
  registered_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (event_id, user_id)
);

create table if not exists public.event_tickets (
  id uuid primary key default gen_random_uuid(),
  registration_id uuid not null unique references public.event_registrations (id) on delete cascade,
  token_hash text not null unique,
  issued_at timestamptz not null default now(),
  revoked_at timestamptz
);

create table if not exists public.attendance_records (
  id uuid primary key default gen_random_uuid(),
  registration_id uuid not null unique references public.event_registrations (id) on delete cascade,
  checked_in_at timestamptz not null default now(),
  checked_in_by uuid references public.user_profiles (id) on delete set null,
  check_in_method text not null default 'qr' check (check_in_method in ('qr', 'manual')),
  notes text
);

-- -----------------------------------------------------------------------------
-- Membership applications and separate Client-to-CCB service requests
-- -----------------------------------------------------------------------------

create table if not exists public.membership_applications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.user_profiles (id) on delete set null,
  full_name text not null,
  email text not null,
  phone text,
  organization text,
  requested_category text,
  message text,
  status text not null default 'submitted'
    check (status in ('draft', 'submitted', 'under_review', 'approved', 'rejected', 'withdrawn')),
  admin_notes text,
  reviewed_by uuid references public.user_profiles (id) on delete set null,
  reviewed_at timestamptz,
  submitted_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.memberships (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_profiles (id) on delete cascade,
  application_id uuid unique references public.membership_applications (id) on delete set null,
  membership_category text not null,
  membership_number text unique,
  status text not null default 'pending' check (status in ('pending', 'active', 'expired', 'suspended', 'cancelled')),
  starts_at date,
  ends_at date,
  fee_amount numeric(12,2) check (fee_amount is null or fee_amount >= 0),
  currency_code char(3),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at is null or starts_at is null or ends_at >= starts_at)
);

create table if not exists public.client_service_requests (
  id uuid primary key default gen_random_uuid(),
  client_id uuid not null references public.client_profiles (user_id) on delete cascade,
  request_type text not null,
  subject text not null,
  description text not null,
  status text not null default 'submitted'
    check (status in ('submitted', 'under_review', 'assigned', 'in_progress', 'resolved', 'closed')),
  assigned_to uuid references public.user_profiles (id) on delete set null,
  admin_notes text,
  submitted_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- Content and media references
-- -----------------------------------------------------------------------------

create table if not exists public.content_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  slug text not null unique,
  created_at timestamptz not null default now()
);

create table if not exists public.articles (
  id uuid primary key default gen_random_uuid(),
  category_id uuid references public.content_categories (id) on delete set null,
  author_id uuid references public.user_profiles (id) on delete set null,
  title text not null,
  slug text not null unique,
  excerpt text,
  body text not null,
  content_type text not null default 'news' check (content_type in ('news', 'insight', 'research', 'report', 'announcement')),
  status text not null default 'draft' check (status in ('draft', 'published', 'archived')),
  featured_media_id uuid references public.media_assets (id) on delete set null,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.recognition_awards (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  slug text not null unique,
  description text,
  award_year integer,
  status text not null default 'draft' check (status in ('draft', 'open', 'closed', 'published', 'archived')),
  nomination_opens_at timestamptz,
  nomination_closes_at timestamptz,
  created_by uuid references public.user_profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.recognition_nominations (
  id uuid primary key default gen_random_uuid(),
  award_id uuid not null references public.recognition_awards (id) on delete cascade,
  nominee_user_id uuid references public.user_profiles (id) on delete set null,
  nominee_name text not null,
  nominee_organization text,
  nominator_user_id uuid references public.user_profiles (id) on delete set null,
  nominator_name text not null,
  nominator_email text not null,
  rationale text not null,
  status text not null default 'submitted' check (status in ('submitted', 'under_review', 'shortlisted', 'selected', 'rejected', 'withdrawn')),
  admin_notes text,
  reviewed_by uuid references public.user_profiles (id) on delete set null,
  submitted_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.partnership_enquiries (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.user_profiles (id) on delete set null,
  organization_name text,
  contact_name text not null,
  contact_email text not null,
  contact_phone text,
  partnership_type text not null,
  message text not null,
  status text not null default 'submitted' check (status in ('submitted', 'under_review', 'assigned', 'in_progress', 'resolved', 'closed')),
  assigned_to uuid references public.user_profiles (id) on delete set null,
  admin_notes text,
  submitted_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.event_media (
  event_id uuid not null references public.events (id) on delete cascade,
  media_asset_id uuid not null references public.media_assets (id) on delete cascade,
  sort_order integer not null default 0,
  primary key (event_id, media_asset_id)
);

create table if not exists public.program_media (
  program_id uuid not null references public.programs (id) on delete cascade,
  media_asset_id uuid not null references public.media_assets (id) on delete cascade,
  sort_order integer not null default 0,
  primary key (program_id, media_asset_id)
);

-- -----------------------------------------------------------------------------
-- Trials, plans, subscriptions, entitlements and payment records
-- Prices are nullable until approved. Store provider references, never card data.
-- -----------------------------------------------------------------------------

create table if not exists public.subscription_plans (
  id uuid primary key default gen_random_uuid(),
  audience text not null check (audience in ('member', 'client')),
  name text not null,
  description text,
  billing_period text not null check (billing_period in ('monthly', 'quarterly', 'yearly', 'one_time')),
  price_amount numeric(12,2) check (price_amount is null or price_amount >= 0),
  currency_code char(3),
  trial_days integer not null default 7 check (trial_days >= 0),
  is_active boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (audience, name, billing_period)
);

create table if not exists public.subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_profiles (id) on delete cascade,
  plan_id uuid references public.subscription_plans (id) on delete set null,
  status text not null default 'trial' check (status in ('trial', 'active', 'past_due', 'expired', 'cancelled', 'suspended')),
  trial_starts_at timestamptz,
  trial_ends_at timestamptz,
  starts_at timestamptz,
  current_period_ends_at timestamptz,
  renews_at timestamptz,
  cancelled_at timestamptz,
  cancellation_reason text,
  gateway_name text,
  gateway_customer_reference text,
  gateway_subscription_reference text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.subscription_entitlements (
  subscription_id uuid not null references public.subscriptions (id) on delete cascade,
  feature_key text not null,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (subscription_id, feature_key)
);

create or replace function public.has_entitlement(requested_feature text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.subscriptions s
    join public.subscription_entitlements e on e.subscription_id = s.id
    where s.user_id = (select auth.uid())
      and s.status in ('trial', 'active')
      and e.feature_key = requested_feature
      and e.enabled
      and (s.status <> 'trial' or s.trial_ends_at is null or s.trial_ends_at > now())
      and (s.current_period_ends_at is null or s.current_period_ends_at > now())
  )
$$;

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  subscription_id uuid references public.subscriptions (id) on delete set null,
  user_id uuid not null references public.user_profiles (id) on delete cascade,
  gateway_name text not null,
  gateway_order_reference text,
  gateway_payment_reference text,
  amount numeric(12,2) not null check (amount >= 0),
  currency_code char(3) not null,
  status text not null default 'created' check (status in ('created', 'pending', 'succeeded', 'failed', 'refunded', 'partially_refunded')),
  paid_at timestamptz,
  failure_code text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (gateway_name, gateway_payment_reference)
);

-- -----------------------------------------------------------------------------
-- Engagement-based reviews, optional social metadata, notifications and audit
-- -----------------------------------------------------------------------------

create table if not exists public.reviews (
  id uuid primary key default gen_random_uuid(),
  opportunity_id uuid not null references public.work_opportunities (id) on delete cascade,
  reviewer_user_id uuid not null references public.user_profiles (id) on delete cascade,
  reviewed_user_id uuid not null references public.user_profiles (id) on delete cascade,
  rating smallint not null check (rating between 1 and 5),
  review_text text,
  status text not null default 'pending' check (status in ('pending', 'published', 'hidden', 'rejected')),
  moderated_by uuid references public.user_profiles (id) on delete set null,
  moderated_at timestamptz,
  created_at timestamptz not null default now(),
  unique (opportunity_id, reviewer_user_id),
  check (reviewer_user_id <> reviewed_user_id)
);

create table if not exists public.social_accounts (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.member_profiles (user_id) on delete cascade,
  provider text not null,
  provider_account_id text,
  profile_url text not null,
  account_type text,
  authorization_status text not null default 'link_only'
    check (authorization_status in ('link_only', 'pending', 'authorized', 'revoked', 'expired')),
  token_secret_reference text,
  sharing_enabled boolean not null default false,
  authorized_at timestamptz,
  last_synced_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (member_id, provider, provider_account_id)
);

create table if not exists public.social_insights (
  id uuid primary key default gen_random_uuid(),
  social_account_id uuid not null references public.social_accounts (id) on delete cascade,
  metric_key text not null,
  metric_value numeric(20,4),
  metric_data jsonb not null default '{}'::jsonb,
  measured_at timestamptz not null,
  created_at timestamptz not null default now(),
  unique (social_account_id, metric_key, measured_at)
);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_profiles (id) on delete cascade,
  notification_type text not null,
  title text not null,
  message text not null,
  target_url text,
  read_at timestamptz,
  delivery_channel text not null default 'in_app' check (delivery_channel in ('in_app', 'email', 'sms', 'push')),
  delivery_status text not null default 'queued' check (delivery_status in ('queued', 'sent', 'failed', 'skipped')),
  delivered_at timestamptz,
  created_at timestamptz not null default now()
);

create table if not exists public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid references public.user_profiles (id) on delete set null,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  details jsonb not null default '{}'::jsonb,
  ip_address inet,
  user_agent text,
  created_at timestamptz not null default now()
);

-- -----------------------------------------------------------------------------
-- Helpful indexes for ownership, status, deadlines and common filters
-- -----------------------------------------------------------------------------

create index if not exists member_profiles_location_idx on public.member_profiles (location);
create index if not exists member_profiles_public_idx on public.member_profiles (is_public) where is_public;
create index if not exists member_profiles_media_idx on public.member_profiles (profile_media_id);
create index if not exists client_profiles_logo_idx on public.client_profiles (logo_media_id);
create index if not exists member_categories_category_idx on public.member_categories (category_id, member_id);
create index if not exists member_skills_skill_idx on public.member_skills (skill_id, member_id);
create index if not exists portfolio_items_member_idx on public.portfolio_items (member_id, sort_order);
create index if not exists media_assets_owner_idx on public.media_assets (owner_user_id);
create index if not exists opportunities_client_status_idx on public.work_opportunities (client_id, status, created_at desc);
create index if not exists opportunities_search_idx on public.work_opportunities using gin (to_tsvector('simple', coalesce(title, '') || ' ' || coalesce(description, '')));
create index if not exists opportunities_deadline_idx on public.work_opportunities (application_deadline) where status = 'published';
create index if not exists opportunity_categories_category_idx on public.opportunity_categories (category_id, opportunity_id);
create index if not exists opportunity_skills_skill_idx on public.opportunity_skills (skill_id, opportunity_id);
create index if not exists applications_member_status_idx on public.applications (member_id, status, submitted_at desc);
create index if not exists applications_opportunity_status_idx on public.applications (opportunity_id, status, submitted_at desc);
create index if not exists saved_members_member_idx on public.saved_members (member_id);
create index if not exists programs_status_dates_idx on public.programs (status, starts_on);
create index if not exists program_enrollments_user_status_idx on public.program_enrollments (user_id, status, enrolled_at desc);
create index if not exists events_status_start_idx on public.events (status, starts_at);
create index if not exists registrations_event_status_idx on public.event_registrations (event_id, status, registered_at);
create index if not exists registrations_user_idx on public.event_registrations (user_id, registered_at desc);
create index if not exists membership_applications_status_idx on public.membership_applications (status, submitted_at desc);
create index if not exists memberships_user_status_idx on public.memberships (user_id, status, ends_at);
create index if not exists service_requests_client_idx on public.client_service_requests (client_id, status, submitted_at desc);
create index if not exists articles_publication_idx on public.articles (status, published_at desc);
create index if not exists awards_status_idx on public.recognition_awards (status, award_year);
create index if not exists nominations_award_status_idx on public.recognition_nominations (award_id, status, submitted_at desc);
create index if not exists partnership_enquiries_status_idx on public.partnership_enquiries (status, submitted_at desc);
create index if not exists subscriptions_user_status_idx on public.subscriptions (user_id, status, current_period_ends_at);
create index if not exists payments_user_created_idx on public.payments (user_id, created_at desc);
create index if not exists reviews_reviewed_status_idx on public.reviews (reviewed_user_id, status, created_at desc);
create index if not exists social_insights_account_time_idx on public.social_insights (social_account_id, measured_at desc);
create index if not exists notifications_user_created_idx on public.notifications (user_id, created_at desc);
create index if not exists audit_logs_entity_idx on public.audit_logs (entity_type, entity_id, created_at desc);

-- -----------------------------------------------------------------------------
-- Row Level Security
-- Public content is readable; private records are scoped to their owner/client
-- and Admin. Sensitive status transitions and privileged writes belong on the
-- trusted backend. RLS remains enabled as a second line of defense.
-- -----------------------------------------------------------------------------

alter table public.professional_categories enable row level security;
alter table public.skills enable row level security;
alter table public.member_profiles enable row level security;
alter table public.client_profiles enable row level security;
alter table public.member_categories enable row level security;
alter table public.member_skills enable row level security;
alter table public.portfolio_items enable row level security;
alter table public.media_assets enable row level security;
alter table public.portfolio_item_media enable row level security;
alter table public.work_opportunities enable row level security;
alter table public.opportunity_categories enable row level security;
alter table public.opportunity_skills enable row level security;
alter table public.applications enable row level security;
alter table public.application_portfolio_items enable row level security;
alter table public.saved_members enable row level security;
alter table public.client_search_history enable row level security;
alter table public.member_enquiries enable row level security;
alter table public.programs enable row level security;
alter table public.program_enrollments enable row level security;
alter table public.events enable row level security;
alter table public.event_form_fields enable row level security;
alter table public.event_registrations enable row level security;
alter table public.event_tickets enable row level security;
alter table public.attendance_records enable row level security;
alter table public.membership_applications enable row level security;
alter table public.memberships enable row level security;
alter table public.client_service_requests enable row level security;
alter table public.content_categories enable row level security;
alter table public.articles enable row level security;
alter table public.recognition_awards enable row level security;
alter table public.recognition_nominations enable row level security;
alter table public.partnership_enquiries enable row level security;
alter table public.event_media enable row level security;
alter table public.program_media enable row level security;
alter table public.subscription_plans enable row level security;
alter table public.subscriptions enable row level security;
alter table public.subscription_entitlements enable row level security;
alter table public.payments enable row level security;
alter table public.reviews enable row level security;
alter table public.social_accounts enable row level security;
alter table public.social_insights enable row level security;
alter table public.notifications enable row level security;
alter table public.audit_logs enable row level security;

-- Admin management policies (write/manage operations are also expected to use a trusted server).
create policy admin_manage_categories on public.professional_categories for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy admin_manage_skills on public.skills for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy admin_manage_content_categories on public.content_categories for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy admin_manage_programs on public.programs for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy admin_manage_program_enrollments on public.program_enrollments for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy admin_manage_events on public.events for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy admin_manage_event_fields on public.event_form_fields for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy admin_manage_event_registrations on public.event_registrations for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy admin_manage_event_tickets on public.event_tickets for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy admin_manage_attendance on public.attendance_records for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy admin_manage_membership_applications on public.membership_applications for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy admin_manage_memberships on public.memberships for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy admin_manage_service_requests on public.client_service_requests for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy admin_manage_articles on public.articles for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy admin_manage_awards on public.recognition_awards for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy admin_manage_nominations on public.recognition_nominations for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy admin_manage_partnership_enquiries on public.partnership_enquiries for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy admin_manage_subscription_plans on public.subscription_plans for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy admin_manage_subscriptions on public.subscriptions for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy admin_manage_payments on public.payments for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy admin_manage_reviews on public.reviews for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy admin_manage_social_insights on public.social_insights for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy admin_read_audit_logs on public.audit_logs for select to authenticated using ((select public.is_admin()));

-- Taxonomy, public content and published listings.
create policy read_active_categories on public.professional_categories for select to anon, authenticated using (is_active or (select public.is_admin()));
create policy read_active_skills on public.skills for select to anon, authenticated using (is_active or (select public.is_admin()));
create policy read_published_programs on public.programs for select to anon, authenticated using (status = 'published' or (select public.is_admin()));
create policy program_enrollments_read_self_admin on public.program_enrollments for select to authenticated using (user_id = (select auth.uid()) or (select public.is_admin()));
create policy program_enrollments_insert_self on public.program_enrollments for insert to authenticated with check (
  user_id = (select auth.uid()) and exists (select 1 from public.programs p where p.id = program_id and p.status = 'published')
);
create policy program_enrollments_cancel_self on public.program_enrollments for update to authenticated using (user_id = (select auth.uid()) and status in ('pending', 'active')) with check (user_id = (select auth.uid()) and status = 'cancelled');
create policy read_published_events on public.events for select to anon, authenticated using (status = 'published' or (select public.is_admin()));
create policy read_fields_for_published_events on public.event_form_fields for select to anon, authenticated using (exists (select 1 from public.events e where e.id = event_id and e.status = 'published') or (select public.is_admin()));
create policy read_active_content_categories on public.content_categories for select to anon, authenticated using (true);
create policy read_published_articles on public.articles for select to anon, authenticated using (status = 'published' or author_id = (select auth.uid()) or (select public.is_admin()));
create policy read_public_media on public.media_assets for select to anon, authenticated using (visibility = 'public' or owner_user_id = (select auth.uid()) or (select public.is_admin()));

-- Member data and portfolio ownership/discovery.
create policy member_profile_read on public.member_profiles for select to authenticated using (
  user_id = (select auth.uid()) or (select public.is_admin()) or
  (is_public and (select public.current_account_type()) = 'client' and (select public.has_entitlement('discover_members')))
);
create policy member_profile_insert_own on public.member_profiles for insert to authenticated with check (
  user_id = (select auth.uid()) and (select public.current_account_type()) = 'member'
  and (profile_media_id is null or exists (select 1 from public.media_assets a where a.id = profile_media_id and a.owner_user_id = (select auth.uid())))
);
create policy member_profile_update_own on public.member_profiles for update to authenticated using (
  user_id = (select auth.uid()) and (select public.current_account_type()) = 'member'
) with check (
  user_id = (select auth.uid()) and (select public.current_account_type()) = 'member'
  and (profile_media_id is null or exists (select 1 from public.media_assets a where a.id = profile_media_id and a.owner_user_id = (select auth.uid())))
);
create policy member_profile_admin_manage on public.member_profiles for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

create policy client_profile_read_own_admin on public.client_profiles for select to authenticated using (user_id = (select auth.uid()) or (select public.is_admin()));
create policy client_profile_insert_own on public.client_profiles for insert to authenticated with check (
  user_id = (select auth.uid()) and (select public.current_account_type()) = 'client'
  and (logo_media_id is null or exists (select 1 from public.media_assets a where a.id = logo_media_id and a.owner_user_id = (select auth.uid())))
);
create policy client_profile_update_own on public.client_profiles for update to authenticated using (
  user_id = (select auth.uid()) and (select public.current_account_type()) = 'client'
) with check (
  user_id = (select auth.uid()) and (select public.current_account_type()) = 'client'
  and (logo_media_id is null or exists (select 1 from public.media_assets a where a.id = logo_media_id and a.owner_user_id = (select auth.uid())))
);
create policy client_profile_admin_manage on public.client_profiles for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

create policy member_categories_manage_own on public.member_categories for all to authenticated using (member_id = (select auth.uid()) or (select public.is_admin())) with check (member_id = (select auth.uid()) or (select public.is_admin()));
create policy member_skills_manage_own on public.member_skills for all to authenticated using (member_id = (select auth.uid()) or (select public.is_admin())) with check (member_id = (select auth.uid()) or (select public.is_admin()));
create policy member_categories_read_discovery on public.member_categories for select to authenticated using (
  member_id = (select auth.uid()) or (select public.is_admin()) or
  ((select public.current_account_type()) = 'client' and (select public.has_entitlement('discover_members'))
    and exists (select 1 from public.member_profiles m where m.user_id = member_id and m.is_public))
);
create policy member_skills_read_discovery on public.member_skills for select to authenticated using (
  member_id = (select auth.uid()) or (select public.is_admin()) or
  ((select public.current_account_type()) = 'client' and (select public.has_entitlement('discover_members'))
    and exists (select 1 from public.member_profiles m where m.user_id = member_id and m.is_public))
);
create policy portfolio_items_read on public.portfolio_items for select to authenticated using (
  member_id = (select auth.uid()) or (select public.is_admin()) or
  (visibility = 'public' and exists (select 1 from public.member_profiles m where m.user_id = member_id and m.is_public)
    and (select public.current_account_type()) = 'client' and (select public.has_entitlement('discover_members')))
);
create policy portfolio_items_manage_own on public.portfolio_items for all to authenticated using (member_id = (select auth.uid()) or (select public.is_admin())) with check (member_id = (select auth.uid()) or (select public.is_admin()));
create policy media_assets_manage_owner on public.media_assets for all to authenticated using (owner_user_id = (select auth.uid()) or (select public.is_admin())) with check (owner_user_id = (select auth.uid()) or (select public.is_admin()));
create policy portfolio_item_media_manage on public.portfolio_item_media for all to authenticated using (
  exists (select 1 from public.portfolio_items p where p.id = portfolio_item_id and (p.member_id = (select auth.uid()) or (select public.is_admin())))
) with check (
  exists (select 1 from public.portfolio_items p where p.id = portfolio_item_id and (p.member_id = (select auth.uid()) or (select public.is_admin())))
);
create policy portfolio_item_media_read on public.portfolio_item_media for select to authenticated using (
  exists (select 1 from public.portfolio_items p where p.id = portfolio_item_id and
    (p.member_id = (select auth.uid()) or (select public.is_admin()) or
      (p.visibility = 'public' and exists (select 1 from public.member_profiles m where m.user_id = p.member_id and m.is_public)
        and (select public.current_account_type()) = 'client' and (select public.has_entitlement('discover_members')))))
);

-- Client opportunities and member applications.
create policy opportunities_read on public.work_opportunities for select to authenticated using (
  client_id = (select auth.uid()) or (select public.is_admin()) or
  (status = 'published' and (select public.current_account_type()) = 'member' and (select public.has_entitlement('view_opportunities')))
);
create policy opportunities_create_client on public.work_opportunities for insert to authenticated with check (
  client_id = (select auth.uid()) and (select public.current_account_type()) = 'client' and (select public.has_entitlement('publish_opportunities'))
);
create policy opportunities_update_client on public.work_opportunities for update to authenticated using (
  client_id = (select auth.uid()) and (select public.current_account_type()) = 'client' and (select public.has_entitlement('publish_opportunities'))
) with check (client_id = (select auth.uid()) and (select public.current_account_type()) = 'client');
create policy opportunities_admin_manage on public.work_opportunities for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy opportunity_categories_manage_owner on public.opportunity_categories for all to authenticated using (
  exists (select 1 from public.work_opportunities o where o.id = opportunity_id and (o.client_id = (select auth.uid()) or (select public.is_admin())))
) with check (
  exists (select 1 from public.work_opportunities o where o.id = opportunity_id and (o.client_id = (select auth.uid()) or (select public.is_admin())))
);
create policy opportunity_categories_read on public.opportunity_categories for select to authenticated using (
  exists (select 1 from public.work_opportunities o where o.id = opportunity_id and
    (o.client_id = (select auth.uid()) or (select public.is_admin()) or
      (o.status = 'published' and (select public.current_account_type()) = 'member' and (select public.has_entitlement('view_opportunities')))))
);
create policy opportunity_skills_manage_owner on public.opportunity_skills for all to authenticated using (
  exists (select 1 from public.work_opportunities o where o.id = opportunity_id and (o.client_id = (select auth.uid()) or (select public.is_admin())))
) with check (
  exists (select 1 from public.work_opportunities o where o.id = opportunity_id and (o.client_id = (select auth.uid()) or (select public.is_admin())))
);
create policy opportunity_skills_read on public.opportunity_skills for select to authenticated using (
  exists (select 1 from public.work_opportunities o where o.id = opportunity_id and
    (o.client_id = (select auth.uid()) or (select public.is_admin()) or
      (o.status = 'published' and (select public.current_account_type()) = 'member' and (select public.has_entitlement('view_opportunities')))))
);
create policy applications_read_participants on public.applications for select to authenticated using (
  member_id = (select auth.uid()) or (select public.is_admin()) or
  exists (select 1 from public.work_opportunities o where o.id = opportunity_id and o.client_id = (select auth.uid()))
);
create policy applications_submit_member on public.applications for insert to authenticated with check (
  member_id = (select auth.uid()) and (select public.current_account_type()) = 'member' and (select public.has_entitlement('apply_opportunities'))
  and exists (select 1 from public.work_opportunities o where o.id = opportunity_id and o.status = 'published')
);
create policy applications_withdraw_member on public.applications for update to authenticated using (
  member_id = (select auth.uid()) and status = 'submitted'
) with check (member_id = (select auth.uid()) and status = 'withdrawn');
create policy applications_manage_client on public.applications for update to authenticated using (
  exists (select 1 from public.work_opportunities o where o.id = opportunity_id and o.client_id = (select auth.uid()))
) with check (
  exists (select 1 from public.work_opportunities o where o.id = opportunity_id and o.client_id = (select auth.uid()))
);
create policy applications_admin_manage on public.applications for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy application_portfolio_read_participants on public.application_portfolio_items for select to authenticated using (
  exists (select 1 from public.applications a where a.id = application_id and (a.member_id = (select auth.uid()) or (select public.is_admin()) or exists (select 1 from public.work_opportunities o where o.id = a.opportunity_id and o.client_id = (select auth.uid()))))
);
create policy application_portfolio_manage_member on public.application_portfolio_items for insert to authenticated with check (
  exists (select 1 from public.applications a where a.id = application_id and a.member_id = (select auth.uid()))
);
create policy application_portfolio_admin_manage on public.application_portfolio_items for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy saved_members_manage_client on public.saved_members for all to authenticated using (client_id = (select auth.uid()) or (select public.is_admin())) with check (client_id = (select auth.uid()) or (select public.is_admin()));
create policy search_history_manage_client on public.client_search_history for all to authenticated using (client_id = (select auth.uid()) or (select public.is_admin())) with check (client_id = (select auth.uid()) or (select public.is_admin()));
create policy member_enquiries_read_participants on public.member_enquiries for select to authenticated using (client_id = (select auth.uid()) or member_id = (select auth.uid()) or (select public.is_admin()));
create policy member_enquiries_create_client on public.member_enquiries for insert to authenticated with check (client_id = (select auth.uid()) and (select public.current_account_type()) = 'client');
create policy member_enquiries_admin_manage on public.member_enquiries for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

-- Events: anonymous users may read published details and register. Ticket tokens
-- are stored as hashes; only the attendee and Admin can read ticket records.
create policy event_registrations_read_owner_admin on public.event_registrations for select to authenticated using (user_id = (select auth.uid()) or (select public.is_admin()));
create policy event_registrations_create on public.event_registrations for insert to anon, authenticated with check (
  status = 'pending'
  and (user_id is null or user_id = (select auth.uid()))
  and exists (select 1 from public.events e where e.id = event_id and e.status = 'published')
);
create policy event_registrations_update_owner on public.event_registrations for update to authenticated using (user_id = (select auth.uid()) and status in ('pending', 'registered', 'waitlisted')) with check (user_id = (select auth.uid()) and status = 'cancelled');
create policy event_tickets_read_attendee_admin on public.event_tickets for select to authenticated using (
  (select public.is_admin()) or exists (select 1 from public.event_registrations r where r.id = registration_id and r.user_id = (select auth.uid()))
);
create policy attendance_read_attendee_admin on public.attendance_records for select to authenticated using (
  (select public.is_admin()) or exists (select 1 from public.event_registrations r where r.id = registration_id and r.user_id = (select auth.uid()))
);
create policy event_media_read_published on public.event_media for select to anon, authenticated using (
  exists (select 1 from public.events e where e.id = event_id and e.status = 'published') or (select public.is_admin())
);
create policy event_media_admin_manage on public.event_media for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy program_media_read_published on public.program_media for select to anon, authenticated using (
  exists (select 1 from public.programs p where p.id = program_id and p.status = 'published') or (select public.is_admin())
);
create policy program_media_admin_manage on public.program_media for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

-- Intake forms: public membership applications have no access to internal notes.
create policy membership_application_submit on public.membership_applications for insert to anon, authenticated with check (status = 'submitted' and (user_id is null or user_id = (select auth.uid())));
create policy membership_application_read on public.membership_applications for select to authenticated using (
  (select public.is_admin()) or user_id = (select auth.uid())
);
create policy membership_application_admin_update on public.membership_applications for update to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));
create policy memberships_read_self_admin on public.memberships for select to authenticated using (user_id = (select auth.uid()) or (select public.is_admin()));
create policy recognition_awards_read_open on public.recognition_awards for select to anon, authenticated using (status in ('open', 'published') or (select public.is_admin()));
create policy recognition_nominations_submit on public.recognition_nominations for insert to anon, authenticated with check (
  status = 'submitted' and (nominator_user_id is null or nominator_user_id = (select auth.uid()))
  and exists (select 1 from public.recognition_awards a where a.id = award_id and a.status = 'open')
);
create policy recognition_nominations_read_owner_admin on public.recognition_nominations for select to authenticated using (
  nominator_user_id = (select auth.uid()) or (select public.is_admin())
);
create policy partnership_enquiries_submit on public.partnership_enquiries for insert to anon, authenticated with check (
  status = 'submitted' and (user_id is null or user_id = (select auth.uid()))
);
create policy partnership_enquiries_read_owner_admin on public.partnership_enquiries for select to authenticated using (
  user_id = (select auth.uid()) or (select public.is_admin())
);
create policy service_requests_read on public.client_service_requests for select to authenticated using (client_id = (select auth.uid()) or (select public.is_admin()));
create policy service_requests_create_client on public.client_service_requests for insert to authenticated with check (
  client_id = (select auth.uid()) and (select public.current_account_type()) = 'client'
);
create policy service_requests_update_admin on public.client_service_requests for update to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

-- Plans are displayable when active; users can read only their own billing rows.
create policy plans_read_active on public.subscription_plans for select to anon, authenticated using (is_active or (select public.is_admin()));
create policy subscriptions_read_self_admin on public.subscriptions for select to authenticated using (user_id = (select auth.uid()) or (select public.is_admin()));
create policy entitlements_read_self_admin on public.subscription_entitlements for select to authenticated using (
  (select public.is_admin()) or exists (select 1 from public.subscriptions s where s.id = subscription_id and s.user_id = (select auth.uid()))
);
create policy payments_read_self_admin on public.payments for select to authenticated using (user_id = (select auth.uid()) or (select public.is_admin()));

-- Reviews require application-level verification of completed engagement before
-- insertion; the unique constraint prevents duplicate reviewer/opportunity rows.
create policy reviews_read_published_or_participant on public.reviews for select to anon, authenticated using (
  status = 'published' or reviewer_user_id = (select auth.uid()) or reviewed_user_id = (select auth.uid()) or (select public.is_admin())
);
create policy reviews_submit_participant on public.reviews for insert to authenticated with check (
  reviewer_user_id = (select auth.uid())
  and exists (
    select 1 from public.work_opportunities o
    where o.id = opportunity_id and o.status = 'completed'
      and (
        (o.client_id = (select auth.uid()) and exists (select 1 from public.applications a where a.opportunity_id = o.id and a.member_id = reviewed_user_id and a.status = 'selected'))
        or
        (reviewed_user_id = o.client_id and exists (select 1 from public.applications a where a.opportunity_id = o.id and a.member_id = (select auth.uid()) and a.status = 'selected'))
      )
  )
);

-- Social connections and insights are private to the creator unless explicitly
-- shared with an entitled Client. OAuth tokens themselves are never stored here.
create policy social_accounts_owner_admin on public.social_accounts for all to authenticated using (member_id = (select auth.uid()) or (select public.is_admin())) with check (member_id = (select auth.uid()) or (select public.is_admin()));
create policy social_insights_owner_shared_admin on public.social_insights for select to authenticated using (
  (select public.is_admin()) or exists (
    select 1 from public.social_accounts s
    where s.id = social_account_id and (
      s.member_id = (select auth.uid()) or
      (s.sharing_enabled and (select public.current_account_type()) = 'client' and (select public.has_entitlement('view_social_insights')))
    )
  )
);

create policy notifications_read_own on public.notifications for select to authenticated using (user_id = (select auth.uid()) or (select public.is_admin()));
create policy notifications_mark_own_read on public.notifications for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy audit_logs_admin_only on public.audit_logs for all to authenticated using ((select public.is_admin())) with check ((select public.is_admin()));

-- Revoke defaults only on these CCB tables, then grant the operations needed
-- by initial browser flows. This avoids changing grants on unrelated project tables.
revoke all on public.user_profiles, public.professional_categories, public.skills,
  public.member_profiles, public.client_profiles, public.member_categories, public.member_skills,
  public.portfolio_items, public.media_assets, public.portfolio_item_media,
  public.work_opportunities, public.opportunity_categories, public.opportunity_skills,
  public.applications, public.application_portfolio_items, public.saved_members,
  public.client_search_history, public.member_enquiries, public.programs, public.program_enrollments, public.events,
  public.event_form_fields, public.event_registrations, public.event_tickets,
  public.attendance_records, public.membership_applications, public.memberships, public.client_service_requests,
  public.content_categories, public.articles, public.recognition_awards, public.recognition_nominations, public.partnership_enquiries, public.event_media, public.program_media,
  public.subscription_plans, public.subscriptions, public.subscription_entitlements,
  public.payments, public.reviews, public.social_accounts, public.social_insights,
  public.notifications, public.audit_logs from anon, authenticated;
grant select on public.user_profiles, public.professional_categories, public.skills,
  public.member_profiles, public.client_profiles, public.member_categories, public.member_skills,
  public.portfolio_items, public.media_assets, public.portfolio_item_media,
  public.work_opportunities, public.opportunity_categories, public.opportunity_skills,
  public.applications, public.application_portfolio_items, public.saved_members,
  public.client_search_history, public.member_enquiries, public.programs, public.program_enrollments,
  public.events, public.event_form_fields, public.event_registrations, public.attendance_records,
  public.memberships, public.content_categories, public.articles, public.recognition_awards,
  public.event_media, public.program_media, public.subscription_plans, public.subscriptions,
  public.subscription_entitlements, public.payments, public.reviews, public.social_insights,
  public.notifications, public.audit_logs to authenticated;
grant select (id, registration_id, issued_at, revoked_at) on public.event_tickets to authenticated;
grant select (id, user_id, full_name, email, phone, organization, requested_category,
  message, status, submitted_at, updated_at) on public.membership_applications to authenticated;
grant select (id, client_id, request_type, subject, description, status, submitted_at, updated_at)
  on public.client_service_requests to authenticated;
grant select (id, award_id, nominee_user_id, nominee_name, nominee_organization,
  nominator_user_id, nominator_name, nominator_email, rationale, status, submitted_at, updated_at)
  on public.recognition_nominations to authenticated;
grant select (id, user_id, organization_name, contact_name, contact_email, contact_phone,
  partnership_type, message, status, submitted_at, updated_at)
  on public.partnership_enquiries to authenticated;
grant select (id, member_id, provider, provider_account_id, profile_url, account_type,
  authorization_status, sharing_enabled, authorized_at, last_synced_at, created_at, updated_at)
  on public.social_accounts to authenticated;

-- Anonymous users can read only public directory/content material. RLS then
-- limits each of these tables to active/published/public rows.
grant select on public.professional_categories, public.skills, public.programs, public.events,
  public.event_form_fields, public.media_assets, public.content_categories, public.articles,
  public.recognition_awards, public.event_media, public.program_media to anon;

-- Profile onboarding. Verification fields and account type are not client-writable.
grant insert (user_id, headline, bio, location, country_code, years_experience,
  availability, professional_interests, contact_preference, portfolio_website,
  is_public, insights_sharing_enabled, profile_media_id) on public.member_profiles to authenticated;
grant update (headline, bio, location, country_code, years_experience, availability,
  professional_interests, contact_preference, portfolio_website, is_public,
  insights_sharing_enabled, profile_media_id) on public.member_profiles to authenticated;
grant insert (user_id, company_name, organization_type, industry, description,
  website_url, location, country_code, business_email, business_phone, logo_media_id)
  on public.client_profiles to authenticated;
grant update (company_name, organization_type, industry, description, website_url,
  location, country_code, business_email, business_phone, logo_media_id) on public.client_profiles to authenticated;

-- Owner-managed classification, portfolio, media and saved-profile data.
grant insert, update, delete on public.member_categories, public.member_skills,
  public.portfolio_items, public.portfolio_item_media, public.saved_members,
  public.client_search_history to authenticated;
grant insert on public.program_enrollments to authenticated;
grant update (status) on public.program_enrollments to authenticated;
grant insert (owner_user_id, bucket_name, object_key, original_filename, mime_type,
  file_size_bytes, visibility, alt_text) on public.media_assets to authenticated;
grant update (original_filename, visibility, alt_text) on public.media_assets to authenticated;
-- R2 object ownership, keys, MIME type and size are immutable after upload;
-- the trusted upload endpoint controls them.

-- Client-created opportunity drafts; publishing/status transitions stay server-side.
grant insert (client_id, title, description, budget_min, budget_max, currency_code,
  professionals_required, experience_min_years, location, work_arrangement,
  start_date, deadline, application_deadline, additional_requirements)
  on public.work_opportunities to authenticated;
grant update (title, description, budget_min, budget_max, currency_code,
  professionals_required, experience_min_years, location, work_arrangement,
  start_date, deadline, application_deadline, additional_requirements)
  on public.work_opportunities to authenticated;
grant insert, delete on public.opportunity_categories, public.opportunity_skills to authenticated;
grant insert (opportunity_id, member_id, cover_message) on public.applications to authenticated;
grant update (status, client_message) on public.applications to authenticated;
grant insert, delete on public.application_portfolio_items to authenticated;
grant insert (client_id, member_id, subject, message) on public.member_enquiries to authenticated;
grant insert (member_id, provider, provider_account_id, profile_url, account_type,
  sharing_enabled) on public.social_accounts to authenticated;
grant update (profile_url, account_type, sharing_enabled) on public.social_accounts to authenticated;
grant delete on public.social_accounts to authenticated;

-- Public submissions cannot set review/admin state; approval and ticketing are backend-only.
grant insert (event_id, user_id, attendee_name, attendee_email, attendee_phone, form_responses)
  on public.event_registrations to authenticated;
grant insert (event_id, attendee_name, attendee_email, attendee_phone, form_responses)
  on public.event_registrations to anon;
grant update (status) on public.event_registrations to authenticated;
grant insert (user_id, full_name, email, phone, organization, requested_category, message)
  on public.membership_applications to authenticated;
grant insert (full_name, email, phone, organization, requested_category, message)
  on public.membership_applications to anon;
grant insert (user_id, contact_name, contact_email, contact_phone, organization_name, partnership_type, message)
  on public.partnership_enquiries to authenticated;
grant insert (contact_name, contact_email, contact_phone, organization_name, partnership_type, message)
  on public.partnership_enquiries to anon;
grant insert (award_id, nominee_user_id, nominee_name, nominee_organization, nominator_user_id,
  nominator_name, nominator_email, rationale) on public.recognition_nominations to authenticated;
grant insert (award_id, nominee_name, nominee_organization, nominator_name, nominator_email, rationale)
  on public.recognition_nominations to anon;
grant insert (client_id, request_type, subject, description) on public.client_service_requests to authenticated;

-- Users can only mark their own in-app notices as read. Billing, review
-- moderation, social metrics, event ticket/check-in, CMS and audit writes are
-- reserved for trusted server-side code.
grant update (read_at) on public.notifications to authenticated;

-- The profile grants were intentionally kept column-scoped above this point.
grant select on public.user_profiles to authenticated;
grant update (account_type) on public.user_profiles to authenticated;

commit;
