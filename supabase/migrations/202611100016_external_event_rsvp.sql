-- CCB publishes events and links to external RSVP providers. Existing native
-- registration records are preserved for history, while the native write/RPC
-- paths are retired for the current version.
alter table public.events
  add column if not exists event_category text,
  add column if not exists target_audience text[] not null default '{}',
  add column if not exists event_visibility text not null default 'public',
  add column if not exists external_rsvp_url text,
  add column if not exists rsvp_closed boolean not null default false,
  add column if not exists announcement_audience text[] not null default '{}';

alter table public.events drop constraint if exists events_event_visibility_check;
alter table public.events add constraint events_event_visibility_check
  check (event_visibility in ('public', 'unlisted', 'private'));
alter table public.events drop constraint if exists events_external_rsvp_url_check;
alter table public.events add constraint events_external_rsvp_url_check
  check (external_rsvp_url is null or external_rsvp_url ~* '^https://[^[:space:]]+$');
alter table public.events drop constraint if exists events_target_audience_check;
alter table public.events add constraint events_target_audience_check
  check (target_audience <@ array['members','clients','both']::text[]);
alter table public.events drop constraint if exists events_announcement_audience_check;
alter table public.events add constraint events_announcement_audience_check
  check (announcement_audience <@ array['members','clients']::text[]);

drop policy if exists read_published_events on public.events;
create policy read_published_events on public.events
for select to anon, authenticated using (
  (status = 'published' and event_visibility in ('public', 'unlisted'))
  or (select public.is_admin())
);

-- Keep historical event_registrations, event_tickets, attendance_records and
-- event_form_fields rows intact. Prevent future native ticket workflows.
revoke all on function public.register_for_event(uuid, text, text, text, jsonb) from public, anon, authenticated;
revoke all on function public.refresh_event_ticket(uuid) from public, anon, authenticated;
revoke all on function public.check_in_event_ticket(text, uuid, uuid) from public, anon, authenticated;
