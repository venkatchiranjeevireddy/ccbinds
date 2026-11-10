-- Keep portfolio media and application attachments within the owning Member's
-- account. Admin access continues through the existing admin policies.

drop policy if exists portfolio_item_media_manage on public.portfolio_item_media;

create policy portfolio_item_media_insert_own on public.portfolio_item_media
for insert to authenticated with check (
  exists (
    select 1
    from public.portfolio_items p
    join public.media_assets m on m.id = media_asset_id
    where p.id = portfolio_item_id
      and p.member_id = (select auth.uid())
      and m.owner_user_id = (select auth.uid())
  )
);

create policy portfolio_item_media_delete_own on public.portfolio_item_media
for delete to authenticated using (
  exists (
    select 1 from public.portfolio_items p
    where p.id = portfolio_item_id and p.member_id = (select auth.uid())
  )
);

drop policy if exists application_portfolio_manage_member on public.application_portfolio_items;

create policy application_portfolio_insert_own on public.application_portfolio_items
for insert to authenticated with check (
  exists (
    select 1
    from public.applications a
    join public.portfolio_items p on p.id = portfolio_item_id
    where a.id = application_id
      and a.member_id = (select auth.uid())
      and p.member_id = a.member_id
  )
);

create policy application_portfolio_delete_own on public.application_portfolio_items
for delete to authenticated using (
  exists (
    select 1 from public.applications a
    where a.id = application_id and a.member_id = (select auth.uid())
  )
);
