import { NextRequest, NextResponse } from 'next/server'
import { getAdminSession, getAdminBackend } from '@/zadmin/lib/server'
import { getResource } from '@/zadmin/lib/catalog'
import { getR2Config, presignR2Request } from '@/zadmin/lib/r2'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

function apiError(message: string, status = 400) {
  return NextResponse.json({ error: message }, { status })
}

async function getAuthorizedBackend() {
  const session = await getAdminSession()
  const backend = getAdminBackend()
  return session && backend ? { session, backend } : null
}

async function recordAdminAction(backend: NonNullable<ReturnType<typeof getAdminBackend>>, adminId: string, action: string, entityType: string, entityId?: string, details: Record<string, unknown> = {}) {
  const uuid = entityId && /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(entityId) ? entityId : null
  await backend.from('audit_logs').insert({
    action: `admin.${action}`,
    entity_type: entityType,
    entity_id: uuid,
    details: { admin_id: adminId, ...(entityId && !uuid ? { target_id: entityId } : {}), ...details },
  })
}

async function notifyPublishedEvent(backend: NonNullable<ReturnType<typeof getAdminBackend>>, event: Record<string, unknown>) {
  const audience = Array.isArray(event.announcement_audience) ? event.announcement_audience.filter((value): value is string => value === 'members' || value === 'clients') : []
  if (audience.length === 0) return
  const accountTypes = audience.includes('members') && audience.includes('clients') ? ['member', 'client'] : audience
  const recipients: { id: string }[] = []
  for (let start = 0; ; start += 1000) {
    const { data, error } = await backend.from('user_profiles').select('id').in('account_type', accountTypes).range(start, start + 999)
    if (error) return
    recipients.push(...(data ?? []))
    if (!data || data.length < 1000) break
  }
  if (!recipients.length) return
  const slug = typeof event.slug === 'string' ? event.slug : ''
  const eventUrl = slug ? `/events/${slug}` : '/events'
  const when = event.starts_at ? new Date(String(event.starts_at)).toLocaleString('en-IN', { timeZone: typeof event.timezone === 'string' ? event.timezone : 'Asia/Kolkata' }) : 'Date to be announced'
  const venue = event.is_online ? 'Online' : String(event.venue_name ?? event.venue_address ?? 'Details on the event page')
  const message = [String(event.summary ?? event.description ?? ''), when, venue, eventUrl, String(event.external_rsvp_url ?? '')].filter(Boolean).join(' · ').slice(0, 4000)
  for (let start = 0; start < recipients.length; start += 500) {
    await backend.from('notifications').insert(recipients.slice(start, start + 500).map(({ id }) => ({ user_id: id, notification_type: 'event_announcement', title: String(event.title ?? 'CCB event'), message, target_url: eventUrl, delivery_channel: 'in_app', delivery_status: 'sent', delivered_at: new Date().toISOString() })))
  }
}

function cleanValues(resourceKey: string, input: Record<string, unknown>, creating = false) {
  const resource = getResource(resourceKey)
  if (!resource) return null
  const fields = creating ? resource.fields : resource.fields
  const result: Record<string, unknown> = {}
  for (const field of fields) {
    if (!(field.key in input)) continue
    const value = input[field.key]
    if (field.type === 'boolean') {
      result[field.key] = value === true || value === 'true'
    } else if (field.type === 'number') {
      if (value === '' || value === null) result[field.key] = null
      else if (typeof value === 'number' && Number.isFinite(value)) result[field.key] = value
      else return null
    } else if (field.type === 'select' && field.options && value !== '' && value !== null) {
      if (typeof value !== 'string' || !field.options.includes(value)) return null
      result[field.key] = value
    } else if (field.type === 'json') {
      if (typeof value !== 'string' || value.length > 10000) return null
      try {
        const parsed = JSON.parse(value) as unknown
        if (field.key === 'options' && (!Array.isArray(parsed) || parsed.length > 100 || parsed.some((item) => typeof item !== 'string' || item.length > 500))) return null
        result[field.key] = parsed
      } catch { return null }
    } else if (field.type === 'date' || field.type === 'datetime') {
      if (value === '' || value === null) result[field.key] = null
      else if (typeof value === 'string' && !Number.isNaN(Date.parse(value))) result[field.key] = value
      else return null
    } else if (value === '' || value === null) {
      result[field.key] = null
    } else if (typeof value === 'string' && value.length <= (field.type === 'textarea' ? 50000 : 2000)) {
      result[field.key] = value.trim()
    } else return null
  }
  if (creating) {
    for (const field of fields) {
      if (field.required && (result[field.key] === undefined || result[field.key] === null || result[field.key] === '')) return null
    }
  }
  if (resource.table === 'articles' && result.status === 'published' && !result.published_at) {
    result.published_at = new Date().toISOString()
  }
  if (resource.table === 'events' && result.status === 'published') {
    const rsvpUrl = typeof result.external_rsvp_url === 'string' ? result.external_rsvp_url.trim() : ''
    if (!/^https:\/\//i.test(rsvpUrl)) return null
    try { if (new URL(rsvpUrl).protocol !== 'https:' || new URL(rsvpUrl).username || new URL(rsvpUrl).password) return null } catch { return null }
    if (!result.published_at) result.published_at = new Date().toISOString()
  }
  if (resource.table === 'events' && result.external_rsvp_url) {
    try {
      const url = new URL(String(result.external_rsvp_url))
      if (url.protocol !== 'https:' || url.username || url.password) return null
      result.external_rsvp_url = url.toString()
    } catch { return null }
  }
  return result
}

export async function GET(request: NextRequest) {
  const auth = await getAuthorizedBackend()
  if (!auth) return apiError('Admin session expired. Sign in again.', 401)
  const resourceKey = request.nextUrl.searchParams.get('resource') ?? ''
  if (resourceKey === 'overview') {
    const tables = [
      ['members', 'member_profiles'], ['clients', 'client_profiles'], ['events', 'events'],
      ['programs', 'programs'], ['applications', 'membership_applications'], ['content', 'articles'],
    ] as const
    const results = await Promise.all(tables.map(async ([key, table]) => {
      const { count, error } = await auth.backend.from(table).select('*', { count: 'exact', head: true })
      return [key, error ? null : count] as const
    }))
    const { data: recentEvents } = await auth.backend
      .from('events').select('id,title,status,starts_at').order('created_at', { ascending: false }).limit(5)
    const counts = Object.fromEntries(results)
    const unavailable = Object.values(counts).every((count) => count === null)
    return NextResponse.json({ counts, recentEvents: recentEvents ?? [], unavailable })
  }

  const resource = getResource(resourceKey)
  if (!resource) return apiError('Unknown Admin section.', 404)
  const requestedPage = Number(request.nextUrl.searchParams.get('page') ?? '1')
  const requestedPageSize = Number(request.nextUrl.searchParams.get('pageSize') ?? '50')
  const page = Number.isSafeInteger(requestedPage) ? Math.max(1, Math.min(requestedPage, 100000)) : 1
  const pageSize = Number.isSafeInteger(requestedPageSize) ? Math.max(10, Math.min(requestedPageSize, 100)) : 50
  const search = (request.nextUrl.searchParams.get('q') ?? '').trim().slice(0, 120).replace(/[%_]/g, '')
  let query = auth.backend.from(resource.table).select(resource.select, { count: 'exact' })
    .order(resource.orderBy ?? 'created_at', { ascending: false })
  query = resource.table === 'program_enrollments'
    ? query.order('program_id', { ascending: true }).order('user_id', { ascending: true })
    : query.order(resource.idKey, { ascending: true })
  if (search && resource.search) query = query.ilike(resource.search, `%${search}%`)
  const start = (page - 1) * pageSize
  query = query.range(start, start + pageSize - 1)
  const { data, error, count } = await query
  if (error) return apiError('Could not load this section. Check that the platform schema is applied.', 503)
  const records = (data ?? []) as unknown as Record<string, unknown>[]
  const r2 = resource.key === 'media_assets' ? getR2Config() : null
  const rows = resource.key === 'media_assets' ? records.map((row) => ({
    ...row,
    // Only an authenticated Admin receives a short-lived read URL for this exact
    // database record. The bucket itself remains private.
    preview_url: r2 ? presignR2Request(r2, 'GET', String(row.object_key), undefined, 300) : null,
  })) : records
  return NextResponse.json({ rows, total: count ?? 0, page, pageSize, columns: resource.columns, fields: resource.fields, resource: { key: resource.key, label: resource.label, description: resource.description, create: resource.create, remove: resource.remove } })
}

export async function POST(request: NextRequest) {
  if (request.headers.get('origin') !== request.nextUrl.origin) return apiError('Request origin is not allowed.', 403)
  const auth = await getAuthorizedBackend()
  if (!auth) return apiError('Admin session expired. Sign in again.', 401)
  let body: { resource?: string; values?: Record<string, unknown> }
  try { body = await request.json() } catch { return apiError('Invalid request body.') }
  const resource = getResource(body.resource ?? '')
  if (!resource?.create || !body.values || typeof body.values !== 'object' || Array.isArray(body.values)) return apiError('This item cannot be created here.', 403)
  const values = cleanValues(resource.key, body.values, true)
  if (!values) return apiError('Check the required fields and values.')
  const { data, error } = await auth.backend.from(resource.table).insert(values).select(resource.select).single()
  if (error) return apiError(error.code === '23505' ? 'That slug or name is already in use.' : 'Could not save this item. Check required fields and related records.', 400)
  await recordAdminAction(auth.backend, auth.session.adminId, 'create', resource.table, String((data as unknown as Record<string, unknown>)[resource.idKey] ?? ''), { fields: Object.keys(values) })
  if (resource.table === 'events' && values.status === 'published') await notifyPublishedEvent(auth.backend, data as unknown as Record<string, unknown>)
  return NextResponse.json({ row: data }, { status: 201 })
}

export async function PATCH(request: NextRequest) {
  if (request.headers.get('origin') !== request.nextUrl.origin) return apiError('Request origin is not allowed.', 403)
  const auth = await getAuthorizedBackend()
  if (!auth) return apiError('Admin session expired. Sign in again.', 401)
  let body: { resource?: string; id?: string; values?: Record<string, unknown> }
  try { body = await request.json() } catch { return apiError('Invalid request body.') }
  const resource = getResource(body.resource ?? '')
  if (!resource || !body.id || !body.values || typeof body.values !== 'object' || Array.isArray(body.values)) return apiError('Invalid update request.')
  const values = cleanValues(resource.key, body.values)
  if (!values || !Object.keys(values).length) return apiError('No valid fields were provided.')
  if (['member_profiles', 'client_profiles', 'events', 'programs', 'articles', 'professional_categories', 'skills', 'professional_roles', 'professional_tools', 'recognition_awards', 'memberships', 'media_assets', 'client_service_requests', 'recognition_nominations', 'subscriptions', 'reviews', 'subscription_plans', 'program_enrollments'].includes(resource.table)) {
    values.updated_at = new Date().toISOString()
  }
  if (resource.table === 'membership_applications') values.reviewed_at = new Date().toISOString()
  if (resource.table === 'applications') values.status_updated_at = new Date().toISOString()
  if (resource.table === 'reviews') values.moderated_at = new Date().toISOString()
  if (resource.table === 'taxonomy_suggestions') values.reviewed_at = new Date().toISOString()
  const shouldAnnounce = resource.table === 'events' && values.status === 'published'
  let wasPublished = false
  if (shouldAnnounce) {
    const { data: previous } = await auth.backend.from('events').select('status').eq('id', body.id).maybeSingle()
    wasPublished = previous?.status === 'published'
  }
  const { data, error } = await auth.backend.from(resource.table).update(values).eq(resource.idKey, body.id).select(resource.select).maybeSingle()
  if (error) return apiError('Could not update this item. Check that the selected values are valid.', 400)
  if (!data) return apiError('Item not found.', 404)
  await recordAdminAction(auth.backend, auth.session.adminId, 'update', resource.table, body.id, { fields: Object.keys(values) })
  if (shouldAnnounce && !wasPublished) await notifyPublishedEvent(auth.backend, data as unknown as Record<string, unknown>)
  return NextResponse.json({ row: data })
}

export async function DELETE(request: NextRequest) {
  if (request.headers.get('origin') !== request.nextUrl.origin) return apiError('Request origin is not allowed.', 403)
  const auth = await getAuthorizedBackend()
  if (!auth) return apiError('Admin session expired. Sign in again.', 401)
  let body: { resource?: string; id?: string }
  try { body = await request.json() } catch { return apiError('Invalid request body.') }
  const resource = getResource(body.resource ?? '')
  if (!resource?.remove || !body.id) return apiError('This item cannot be removed here.', 403)
  const { error, count } = await auth.backend.from(resource.table).delete({ count: 'exact' }).eq(resource.idKey, body.id)
  if (error) return apiError('Could not remove this item. It may still be in use.', 400)
  if (count === 0) return apiError('Item not found.', 404)
  await recordAdminAction(auth.backend, auth.session.adminId, 'delete', resource.table, body.id)
  return NextResponse.json({ ok: true })
}
