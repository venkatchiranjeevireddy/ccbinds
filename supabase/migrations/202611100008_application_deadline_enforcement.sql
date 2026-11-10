begin;

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

commit;
