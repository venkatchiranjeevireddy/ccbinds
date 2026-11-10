begin;

-- A guessed Member UUID must not bypass discovery entitlement checks.
drop policy if exists member_enquiries_create_client on public.member_enquiries;
create policy member_enquiries_create_client on public.member_enquiries
for insert to authenticated
with check (
  client_id = (select auth.uid())
  and (select public.current_account_type()) = 'client'
  and (select public.has_entitlement('discover_members'))
  and exists (
    select 1 from public.member_profiles m
    where m.user_id = member_id and m.is_public
  )
);

-- Keep a Client's saved/search history readable/removable if access expires,
-- while preventing discovery writes without the matching entitlement.
drop policy if exists saved_members_manage_client on public.saved_members;
create policy saved_members_read_own on public.saved_members
for select to authenticated using (client_id = (select auth.uid()) or (select public.is_admin()));
create policy saved_members_create_entitled on public.saved_members
for insert to authenticated with check (
  client_id = (select auth.uid())
  and (select public.current_account_type()) = 'client'
  and (select public.has_entitlement('discover_members'))
  and exists (select 1 from public.member_profiles m where m.user_id = member_id and m.is_public)
);
create policy saved_members_remove_own on public.saved_members
for delete to authenticated using (client_id = (select auth.uid()) or (select public.is_admin()));

drop policy if exists search_history_manage_client on public.client_search_history;
create policy search_history_read_own on public.client_search_history
for select to authenticated using (client_id = (select auth.uid()) or (select public.is_admin()));
create policy search_history_create_entitled on public.client_search_history
for insert to authenticated with check (
  client_id = (select auth.uid())
  and (select public.current_account_type()) = 'client'
  and (select public.has_entitlement('discover_members'))
);
create policy search_history_remove_own on public.client_search_history
for delete to authenticated using (client_id = (select auth.uid()) or (select public.is_admin()));

commit;
