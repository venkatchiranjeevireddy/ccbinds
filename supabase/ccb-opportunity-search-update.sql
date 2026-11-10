begin;

-- Replace the unfiltered Member feed RPC with a server-side searchable,
-- paginated feed. The existing taxonomy GIN indexes and opportunity join-table
-- indexes provide the query paths for names and approved aliases.
alter table public.work_opportunities add column if not exists search_document tsvector
  generated always as (to_tsvector('simple', coalesce(title, '') || ' ' || coalesce(description, ''))) stored;
create index if not exists opportunities_search_document_idx
  on public.work_opportunities using gin(search_document) where status = 'published';

drop function if exists public.get_personalized_opportunities(integer, integer);

create or replace function public.get_personalized_opportunities(
  p_page integer,
  p_page_size integer,
  p_query text,
  p_location text,
  p_category_id uuid,
  p_skill_id uuid,
  p_role_id uuid,
  p_tool_id uuid,
  p_work_arrangement text,
  p_min_experience numeric,
  p_max_budget numeric
)
returns table(opportunity_id uuid, relevance_score numeric, total_count bigint)
language sql
stable
security definer
set search_path = ''
as $$
  with search_terms as (
    select plainto_tsquery('simple', left(coalesce(p_query, ''), 160)) as query
  ), member_data as (
    select m.user_id, m.location, m.years_experience, m.availability,
      m.expected_rate_min, m.expected_rate_max, m.expected_rate_period,
      coalesce(array_agg(distinct mc.category_id) filter (where mc.category_id is not null), '{}'::uuid[]) categories,
      coalesce((select array_agg(ms.skill_id) from public.member_skills ms where ms.member_id = m.user_id), '{}'::uuid[]) skills,
      coalesce((select array_agg(mr.role_id) from public.member_roles mr where mr.member_id = m.user_id), '{}'::uuid[]) roles,
      coalesce((select array_agg(mt.tool_id) from public.member_tools mt where mt.member_id = m.user_id), '{}'::uuid[]) tools,
      coalesce((select array_agg(mwp.work_arrangement) from public.member_work_preferences mwp where mwp.member_id = m.user_id), '{}'::text[]) arrangements
    from public.member_profiles m
    left join public.member_categories mc on mc.member_id = m.user_id
    where m.user_id = (select auth.uid())
      and public.current_account_type() = 'member'
      and public.has_entitlement('view_opportunities')
    group by m.user_id
  ), candidates as (
    select o.id, o.title, o.description, o.location, o.work_arrangement,
      o.budget_min, o.budget_max, o.currency_code, o.deadline, o.application_deadline,
      o.experience_min_years, o.experience_max_years, o.required_availability,
      (select count(*) from public.opportunity_skills os join public.member_skills ms on ms.skill_id = os.skill_id and ms.member_id = md.user_id where os.opportunity_id = o.id)::numeric skill_matches,
      (select count(*) from public.opportunity_skills os where os.opportunity_id = o.id)::numeric total_skills,
      (select count(*) from public.opportunity_categories oc where oc.opportunity_id = o.id and oc.category_id = any(md.categories))::numeric category_matches,
      (select count(*) from public.opportunity_roles orl where orl.opportunity_id = o.id and orl.role_id = any(md.roles))::numeric role_matches,
      (select count(*) from public.opportunity_tools ot where ot.opportunity_id = o.id and ot.tool_id = any(md.tools))::numeric tool_matches,
      case when md.location is not null and (lower(coalesce(o.location, '')) = lower(md.location) or o.work_arrangement = 'remote') then 1 else 0 end::numeric location_match,
      case when cardinality(md.arrangements) = 0 or o.work_arrangement is null or o.work_arrangement = any(md.arrangements) then 1 else 0 end::numeric preference_match,
      case when o.budget_min is null or md.expected_rate_max is null or o.budget_max is null then 1
        when md.expected_rate_period is not null and o.budget_type is not null and md.expected_rate_period <> case o.budget_type when 'fixed' then 'project' when 'monthly_salary' then 'monthly' else o.budget_type end then 0
        when md.expected_rate_max >= o.budget_min then 1 else 0 end::numeric budget_match,
      greatest(0, 30 - extract(epoch from (now() - coalesce(o.published_at, o.created_at))) / 86400 / 3)::numeric recency_score,
      exists(select 1 from public.opportunity_skills os where os.opportunity_id = o.id and os.is_mandatory and not exists(select 1 from public.member_skills ms where ms.member_id = md.user_id and ms.skill_id = os.skill_id)) missing_mandatory,
      exists(select 1 from public.opportunity_skills os where os.opportunity_id = o.id and not exists(select 1 from public.member_skills ms where ms.member_id = md.user_id and ms.skill_id = os.skill_id)) missing_any_skill,
      md.availability, md.years_experience, st.query
    from public.work_opportunities o
    cross join member_data md
    cross join search_terms st
    where o.status = 'published'
      and (o.application_deadline is null or o.application_deadline > now())
      and (o.deadline is null or o.deadline >= current_date)
      and (nullif(btrim(p_location), '') is null or lower(coalesce(o.location, '')) like lower(replace(replace(btrim(p_location), '%', ''), '_', '')) || '%')
      and (p_category_id is null or exists(select 1 from public.opportunity_categories oc where oc.opportunity_id = o.id and oc.category_id = p_category_id))
      and (p_skill_id is null or exists(select 1 from public.opportunity_skills os where os.opportunity_id = o.id and os.skill_id = p_skill_id))
      and (p_role_id is null or exists(select 1 from public.opportunity_roles r where r.opportunity_id = o.id and r.role_id = p_role_id))
      and (p_tool_id is null or exists(select 1 from public.opportunity_tools t where t.opportunity_id = o.id and t.tool_id = p_tool_id))
      and (p_work_arrangement is null or o.work_arrangement = p_work_arrangement)
      and (p_min_experience is null or coalesce(o.experience_min_years, 0) >= p_min_experience)
      and (p_max_budget is null or o.budget_min is null or o.budget_min <= p_max_budget)
      and (
        nullif(btrim(p_query), '') is null
        or o.search_document @@ st.query
        or exists (
          select 1 from public.opportunity_categories oc
          join public.professional_categories c on c.id = oc.category_id and c.is_active
          where oc.opportunity_id = o.id and c.search_document @@ st.query
        )
        or exists (
          select 1 from public.opportunity_skills os
          join public.skills s on s.id = os.skill_id and s.is_active
          where os.opportunity_id = o.id and (s.search_document @@ st.query or exists(select 1 from public.taxonomy_aliases a where a.skill_id = s.id and a.search_document @@ st.query))
        )
        or exists (
          select 1 from public.opportunity_roles opr
          join public.professional_roles r on r.id = opr.role_id and r.is_active
          where opr.opportunity_id = o.id and (r.search_document @@ st.query or exists(select 1 from public.taxonomy_aliases a where a.role_id = r.id and a.search_document @@ st.query))
        )
        or exists (
          select 1 from public.opportunity_tools opt
          join public.professional_tools t on t.id = opt.tool_id and t.is_active
          where opt.opportunity_id = o.id and (t.search_document @@ st.query or exists(select 1 from public.taxonomy_aliases a where a.tool_id = t.id and a.search_document @@ st.query))
        )
      )
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
  limit greatest(1, least(coalesce(p_page_size, 20), 100))
  offset greatest(0, coalesce(p_page, 0)) * greatest(1, least(coalesce(p_page_size, 20), 100));
$$;

revoke all on function public.get_personalized_opportunities(integer, integer, text, text, uuid, uuid, uuid, uuid, text, numeric, numeric) from public, anon;
grant execute on function public.get_personalized_opportunities(integer, integer, text, text, uuid, uuid, uuid, uuid, text, numeric, numeric) to authenticated;

create index if not exists opportunities_published_arrangement_idx
  on public.work_opportunities (work_arrangement, published_at desc, id)
  where status = 'published';
create index if not exists opportunities_published_experience_budget_idx
  on public.work_opportunities (experience_min_years, budget_min)
  where status = 'published';
create index if not exists opportunities_published_location_prefix_idx
  on public.work_opportunities (lower(coalesce(location, '')) text_pattern_ops)
  where status = 'published';

commit;
