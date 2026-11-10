-- Require Admin scanners to select an event and bind ticket validation to it.
drop function if exists public.check_in_event_ticket(text, uuid);

create function public.check_in_event_ticket(
  p_ticket_token text,
  p_event_id uuid,
  p_checked_in_by uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  ticket_row public.event_tickets;
  result jsonb;
begin
  if p_event_id is null then raise exception 'Select an event before check-in.' using errcode = '22023'; end if;
  if length(coalesce(p_ticket_token, '')) <> 32 then
    raise exception 'Invalid ticket.' using errcode = '22023';
  end if;

  select t.* into ticket_row
  from public.event_tickets t
  where t.token_hash = encode(extensions.digest(p_ticket_token, 'sha256'), 'hex')
    and t.revoked_at is null
  for update;
  if not found then raise exception 'Ticket is invalid or revoked.' using errcode = 'P0002'; end if;

  if not exists (
    select 1 from public.event_registrations r
    where r.id = ticket_row.registration_id and r.event_id = p_event_id
  ) then raise exception 'Ticket belongs to another event.' using errcode = '22023'; end if;

  if exists (select 1 from public.attendance_records a where a.registration_id = ticket_row.registration_id) then
    raise exception 'This ticket has already been checked in.' using errcode = '23505';
  end if;
  if not exists (
    select 1 from public.event_registrations r join public.events e on e.id = r.event_id
    where r.id = ticket_row.registration_id and r.status = 'registered'
      and e.id = p_event_id and e.qr_check_in_enabled
  ) then raise exception 'Registration is not eligible for check-in.' using errcode = '42501'; end if;

  insert into public.attendance_records (registration_id, checked_in_by, check_in_method)
  values (ticket_row.registration_id, p_checked_in_by, 'qr');
  select jsonb_build_object('attendee_name', r.attendee_name, 'attendee_email', r.attendee_email,
      'event_title', e.title, 'checked_in_at', a.checked_in_at)
  into result from public.attendance_records a
  join public.event_registrations r on r.id = a.registration_id
  join public.events e on e.id = r.event_id
  where a.registration_id = ticket_row.registration_id;
  return result;
end;
$$;

revoke all on function public.check_in_event_ticket(text, uuid, uuid) from public, anon, authenticated;
grant execute on function public.check_in_event_ticket(text, uuid, uuid) to service_role;
