-- Make the identity fields embedded in public Member profiles readable to
-- entitled Clients without exposing other account identities.
create policy user_profiles_read_discoverable_member_identity
on public.user_profiles for select to authenticated using (
  account_type = 'member'
  and (select public.current_account_type()) = 'client'
  and (select public.has_entitlement('discover_members'))
  and exists (
    select 1 from public.member_profiles m
    where m.user_id = public.user_profiles.id and m.is_public
  )
);

-- Participants in an opportunity engagement can see the other party's basic
-- display identity even if the Member is not listed publicly.
create policy user_profiles_read_application_participants
on public.user_profiles for select to authenticated using (
  exists (
    select 1
    from public.applications a
    join public.work_opportunities o on o.id = a.opportunity_id
    where (a.member_id = public.user_profiles.id and o.client_id = (select auth.uid()))
       or (o.client_id = public.user_profiles.id and a.member_id = (select auth.uid()))
  )
);
