'use client'

import Link from 'next/link'
import { useEffect, useState } from 'react'
import { CalendarDays, MapPin, ArrowRight, FileText } from 'lucide-react'
import { createClient } from '@/lib/supabase/client'

type PublicKind = 'events' | 'programs' | 'knowledge-hub' | 'news' | 'recognition'
type Row = Record<string, unknown>
const asRows = (value: unknown): Row[] => Array.isArray(value) ? value as Row[] : []

export function PublicListing({ kind }: { kind: PublicKind }) {
  const [rows, setRows] = useState<Row[]>([])
  const [error, setError] = useState('')
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    const supabase = createClient()
    const load = async () => {
      const table = kind === 'events' ? 'events' : kind === 'programs' ? 'programs' : kind === 'recognition' ? 'recognition_awards' : 'articles'
      const select = kind === 'events'
        ? 'id,title,slug,summary,starts_at,ends_at,timezone,venue_name,is_online,registration_closes_at,featured_media_id,event_category,target_audience,event_visibility,external_rsvp_url,rsvp_closed,event_media(sort_order,media_asset_id,media_assets(id,original_filename,mime_type))'
        : kind === 'programs'
          ? 'id,title,slug,summary,starts_on,ends_on,featured_media_id'
          : kind === 'recognition'
            ? 'id,title,slug,description,award_year,status,nomination_opens_at,nomination_closes_at'
            : 'id,title,slug,excerpt,content_type,published_at,featured_media_id'
      let request = supabase.from(table).select(select).eq('status', kind === 'recognition' ? 'open' : 'published').limit(60)
      if (kind === 'events') request = request.eq('event_visibility', 'public').order('starts_at', { ascending: true })
      else if (kind === 'programs') request = request.order('starts_on', { ascending: false })
      else if (kind === 'recognition') request = request.order('award_year', { ascending: false })
      else request = request.order('published_at', { ascending: false })
      if (kind === 'news') request = request.eq('content_type', 'news')
      if (kind === 'knowledge-hub') request = request.in('content_type', ['insight', 'research', 'report', 'announcement'])
      const { data, error: queryError } = await request
      if (queryError) setError('Published content is temporarily unavailable. Please try again later.')
      else setRows((data ?? []) as unknown as Row[])
      setLoading(false)
    }
    void load()
  }, [kind])

  return <section className="section public-database-section"><div className="container"><div className="section-head"><div><div className="eyebrow">CCB India</div><h2>{listingTitle(kind)}</h2></div><p>Showing published records from the CCB platform. Draft content is not visible here.</p></div>{kind === 'programs' ? <p className="public-data-message">Full online training courses and learning materials are coming soon. You can browse and enroll in published CCB programs here.</p> : null}{loading ? <p className="public-data-message">Loading published updates…</p> : error ? <p className="public-data-message" role="alert">{error}</p> : rows.length ? <div className="public-record-grid">{rows.map((row) => <PublicCard key={String(row.id)} kind={kind} row={row}/>)}</div> : <p className="public-data-message">Nothing has been published here yet. Please check back later.</p>}</div></section>
}

export function PublicDetail({ kind, slug }: { kind: 'events' | 'programs' | 'articles'; slug: string }) {
  const [row, setRow] = useState<Row | null>(null)
  const [missing, setMissing] = useState(false)
  useEffect(() => {
    const supabase = createClient()
    const table = kind === 'events' ? 'events' : kind === 'programs' ? 'programs' : 'articles'
    const record = kind === 'events'
      ? supabase.from(table).select('*,event_media(sort_order,media_asset_id,media_assets(id,original_filename,mime_type))').eq('slug', slug).eq('status', 'published').maybeSingle()
      : supabase.from(table).select('*').eq('slug', slug).eq('status', 'published').maybeSingle()
    void record.then(({ data }) => {
      if (data) setRow(data as Row); else setMissing(true)
    })
  }, [kind, slug])
  if (missing) return <main className="public-detail"><div className="container"><h1>This page is unavailable.</h1><Link href="/">Return to CCB India</Link></div></main>
  if (!row) return <main className="public-detail"><div className="container"><p>Loading published content…</p></div></main>
  const date = kind === 'events' ? row.starts_at : row.starts_on
  return <main className="public-detail"><div className="container"><Link className="auth-back-link" href={kind === 'events' ? '/events' : kind === 'programs' ? '/programs' : '/knowledge-hub'}>← Back</Link><span className="eyebrow">{kind === 'events' ? 'CCB EVENT' : kind === 'programs' ? 'CCB PROGRAM' : String(row.content_type ?? 'CCB ARTICLE').replaceAll('_', ' ').toUpperCase()}</span><h1>{String(row.title)}</h1>{row.featured_media_id ? <img className="public-detail-image" src={`/api/media?id=${encodeURIComponent(String(row.featured_media_id))}`} alt={String(row.title)} /> : null}{kind === 'events' ? <EventMediaGallery items={row.event_media}/> : null}{row.summary || row.excerpt ? <p className="public-detail-lede">{String(row.summary ?? row.excerpt)}</p> : null}{date ? <p className="public-detail-meta"><CalendarDays size={15}/>{new Date(String(date)).toLocaleString()}</p> : null}{row.venue_name ? <p className="public-detail-meta"><MapPin size={15}/>{String(row.venue_name)}{row.venue_address ? ` · ${String(row.venue_address)}` : ''}</p> : null}{row.event_category ? <p className="public-detail-meta">{String(row.event_category)}</p> : null}{row.description || row.body ? <div className="public-detail-body">{String(row.description ?? row.body).split('\n').map((paragraph, index) => <p key={index}>{paragraph}</p>)}</div> : null}{kind === 'events' ? <EventRegistrationAction event={row}/> : null}</div></main>
}

function EventMediaGallery({ items }: { items: unknown }) {
  const mediaRows = asRows(items).sort((a, b) => Number(a.sort_order ?? 0) - Number(b.sort_order ?? 0))
  if (!mediaRows.length) return null
  return <div className="public-event-gallery">{mediaRows.map((item) => {
    const media = item.media_assets as Row | undefined
    if (!media?.id) return null
    const src = `/api/media?id=${encodeURIComponent(String(media.id))}`
    return String(media.mime_type ?? '').startsWith('video/')
      ? <video key={String(media.id)} className="public-event-gallery-video" src={src} controls preload="metadata" aria-label={String(media.original_filename ?? 'Event video')} />
      : <img key={String(media.id)} className="public-event-gallery-image" src={src} alt={String(media.original_filename ?? 'Event image')} loading="lazy" />
  })}</div>
}

function EventRegistrationAction({ event }: { event: Row }) {
  const deadlinePassed = Boolean(event.registration_closes_at && new Date(String(event.registration_closes_at)).getTime() <= Date.now())
  const closed = Boolean(event.rsvp_closed) || deadlinePassed || ['completed', 'cancelled'].includes(String(event.status))
  const status = event.status === 'completed' ? 'Completed' : event.status === 'cancelled' ? 'Cancelled' : closed ? 'Registration closed' : 'Registration open'
  return <section className="public-registration-card"><span className="eyebrow">{status.toUpperCase()}</span><h2>{closed ? status : 'Register for this event'}</h2><p>{closed ? 'Registration for this event is no longer available.' : 'RSVP securely through the event registration form.'}</p>{!closed && typeof event.external_rsvp_url === 'string' && event.external_rsvp_url.startsWith('https://') ? <a className="btn btn-primary" href={event.external_rsvp_url} target="_blank" rel="noopener noreferrer">Register Now <ArrowRight size={15}/></a> : null}{!closed && !event.external_rsvp_url ? <p>Registration details will be announced by CCB.</p> : null}{event.registration_closes_at ? <small>Registration closes {new Date(String(event.registration_closes_at)).toLocaleString()}.</small> : null}</section>
}

function PublicCard({ kind, row }: { kind: PublicKind; row: Row }) {
  const href = kind === 'events' ? `/events/${String(row.slug)}` : kind === 'programs' ? `/programs/${String(row.slug)}` : kind === 'recognition' ? '/recognition' : `/${kind === 'news' ? 'news' : 'knowledge-hub'}/${String(row.slug)}`
  const date = row.starts_at ?? row.starts_on ?? row.published_at
  const eventClosed = kind === 'events' && (Boolean(row.rsvp_closed) || Boolean(row.registration_closes_at && new Date(String(row.registration_closes_at)).getTime() <= Date.now()))
  return <article className="public-record-card">{row.featured_media_id ? <img className="public-record-image" src={`/api/media?id=${encodeURIComponent(String(row.featured_media_id))}`} alt={String(row.title)} loading="lazy"/> : <div className="public-record-icon">{kind === 'events' ? <CalendarDays size={19}/> : <FileText size={19}/>}</div>}{kind === 'events' ? <EventMediaGallery items={row.event_media}/> : null}<span className="eyebrow">{kind === 'events' ? eventClosed ? 'REGISTRATION CLOSED' : 'EVENT' : kind === 'programs' ? 'PROGRAM' : kind === 'recognition' ? 'RECOGNITION' : String(row.content_type ?? 'ARTICLE').replaceAll('_', ' ').toUpperCase()}</span><h3><Link href={href}>{String(row.title)}</Link></h3>{row.summary || row.excerpt || row.description ? <p>{String(row.summary ?? row.excerpt ?? row.description)}</p> : null}<div className="public-record-meta">{date ? <span>{new Date(String(date)).toLocaleDateString()}</span> : null}{row.event_category ? <span>{String(row.event_category)}</span> : null}{row.venue_name ? <span>{String(row.venue_name)}</span> : null}{row.is_online ? <span>Online</span> : null}</div><Link className="link-arrow" href={href}>Explore <ArrowRight size={14}/></Link></article>
}

function listingTitle(kind: PublicKind) {
  return kind === 'events' ? 'Published events' : kind === 'programs' ? 'Published programs' : kind === 'recognition' ? 'Open recognition programs' : kind === 'news' ? 'Latest news' : 'Knowledge and insights'
}
