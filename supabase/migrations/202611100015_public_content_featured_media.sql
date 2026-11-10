-- Public content references media metadata; the image bytes remain in private R2.
alter table public.events
  add column if not exists featured_media_id uuid references public.media_assets (id) on delete set null;

alter table public.programs
  add column if not exists featured_media_id uuid references public.media_assets (id) on delete set null;
