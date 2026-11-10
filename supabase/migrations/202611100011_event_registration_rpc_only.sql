begin;

-- Registration must pass capacity, date-window, policy, duplicate and custom
-- form validation in register_for_event; direct row inserts bypass those checks.
drop policy if exists event_registrations_create on public.event_registrations;
revoke insert (event_id, user_id, attendee_name, attendee_email, attendee_phone, form_responses)
  on public.event_registrations from anon, authenticated;
revoke insert (event_id, attendee_name, attendee_email, attendee_phone, form_responses)
  on public.event_registrations from anon;

commit;
