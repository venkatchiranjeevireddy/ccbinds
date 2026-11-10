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
