'use client'

import { ChangeEvent, FormEvent, useCallback, useEffect, useRef, useState } from 'react'
import {
  Activity, ArrowDownRight, ArrowRight, ArrowUpRight, Award, Bell, BriefcaseBusiness,
  CalendarDays, Check, ChevronDown, ChevronLeft, ChevronRight, CircleHelp, ClipboardList,
  Clock3, FileImage, FileText, Grid2X2, Layers3, LogOut, Menu, Plus, Search, Settings2,
  ShieldCheck, Sparkles, Tags, Users, X,
} from 'lucide-react'
import { AdminField, navigationGroups, resources } from '@/zadmin/lib/catalog'

type Row = Record<string, unknown>
type Section = 'overview' | string
type TableResponse = { rows: Row[]; total: number; page: number; pageSize: number; columns: { key: string; label: string }[]; fields: AdminField[]; resource: { key: string; label: string; description: string; create: boolean; remove: boolean } }
type Overview = { counts: Record<string, number | null>; recentEvents: Row[]; unavailable: boolean }

const iconFor: Record<string, typeof Grid2X2> = {
  overview: Grid2X2, members: Users, clients: BriefcaseBusiness, membership_applications: ClipboardList,
  memberships: Award, client_service_requests: CircleHelp, events: CalendarDays, programs: Layers3,
  articles: FileText, professional_categories: Tags, skills: Sparkles,
  recognition_awards: Award, media_assets: FileImage, work_opportunities: BriefcaseBusiness,
  applications: ClipboardList, partnership_enquiries: ArrowUpRight,
  recognition_nominations: Award, program_enrollments: Layers3, reviews: ShieldCheck,
  subscription_plans: Settings2, subscriptions: Activity, payments: Activity, audit_logs: ClipboardList,
}

const displayLabels: Record<string, string> = Object.fromEntries(resources.map((item) => [item.key, item.label]))

function getValue(row: Row, path: string): unknown {
  return path.split('.').reduce<unknown>((value, key) => value && typeof value === 'object' ? (value as Row)[key] : undefined, row)
}

function formatValue(value: unknown, key: string) {
  if (value === null || value === undefined || value === '') return '-'
  if (typeof value === 'boolean') return value ? 'Yes' : 'No'
  if (typeof value === 'number') return value.toLocaleString('en-IN')
  if (typeof value === 'string' && (key.endsWith('_at') || key.endsWith('_on') || key === 'created_at' || key === 'submitted_at')) {
    const date = new Date(value)
    if (!Number.isNaN(date.valueOf())) return new Intl.DateTimeFormat('en-IN', { day: '2-digit', month: 'short', year: 'numeric', ...(key.endsWith('_at') ? { hour: '2-digit', minute: '2-digit' } : {}) }).format(date)
  }
  if (typeof value === 'string' && value.length > 48) return `${value.slice(0, 45)}...`
  return String(value)
}

function toFormValue(value: unknown, field: AdminField) {
  if (field.type === 'boolean') return value === true
  if (value === null || value === undefined) return ''
  if (field.type === 'json') return JSON.stringify(value, null, 2)
  if (field.type === 'datetime' && typeof value === 'string') {
    const date = new Date(value)
    return Number.isNaN(date.valueOf()) ? '' : new Date(date.getTime() - date.getTimezoneOffset() * 60000).toISOString().slice(0, 16)
  }
  return String(value)
}

function slugify(value: string) {
  return value.normalize('NFKD').toLowerCase().trim().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '')
}

function FieldControl({ field, value, onChange }: { field: AdminField; value: unknown; onChange: (value: unknown) => void }) {
  const common = { id: `admin-field-${field.key}`, name: field.key }
  if (field.type === 'textarea') return <textarea {...common} rows={4} defaultValue={String(value ?? '')} placeholder={field.placeholder ?? ''} required={field.required} />
  if (field.type === 'json') return <textarea {...common} rows={4} defaultValue={JSON.stringify(value ?? [], null, 2)} placeholder={field.placeholder ?? '[]'} required={field.required} />
  if (field.type === 'select') return <select {...common} defaultValue={String(value ?? '')} required={field.required}><option value="">Choose...</option>{field.options?.map((option) => <option key={option} value={option}>{option.replaceAll('_', ' ')}</option>)}</select>
  if (field.type === 'boolean') return <div className="za-switch"><input {...common} type="checkbox" defaultChecked={Boolean(value)} /><span /><em>{value ? 'Enabled' : 'Disabled'}</em></div>
  const type = field.type === 'number' ? 'number' : field.type === 'date' ? 'date' : field.type === 'datetime' ? 'datetime-local' : 'text'
  return <input {...common} type={type} defaultValue={String(value ?? '')} placeholder={field.placeholder ?? ''} required={field.required} />
}

function StatusPill({ value }: { value: unknown }) {
  const text = String(value ?? 'unknown')
  const tone = ['published', 'active', 'verified', 'approved', 'registered', 'completed', 'resolved'].includes(text) ? 'good'
    : ['draft', 'pending', 'submitted', 'under_review', 'limited', 'in_progress'].includes(text) ? 'warm'
      : ['rejected', 'cancelled', 'suspended', 'archived', 'unavailable'].includes(text) ? 'muted' : 'neutral'
  return <span className={`za-status za-status-${tone}`}><i />{text.replaceAll('_', ' ')}</span>
}

export function AdminConsole({ adminId }: { adminId: string }) {
  const [section, setSection] = useState<Section>('overview')
  const [mobileNav, setMobileNav] = useState(false)
  const [query, setQuery] = useState('')
  const [page, setPage] = useState(1)
  const [rows, setRows] = useState<Row[]>([])
  const [tableInfo, setTableInfo] = useState<TableResponse | null>(null)
  const [overview, setOverview] = useState<Overview | null>(null)
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const [editor, setEditor] = useState<{ mode: 'create' | 'edit'; row: Row | null } | null>(null)
  const [saving, setSaving] = useState(false)
  const [uploading, setUploading] = useState(false)
  const uploadInput = useRef<HTMLInputElement>(null)
  const [notice, setNotice] = useState('')

  const refresh = useCallback(async (target = section, targetPage = page, targetQuery = query) => {
    setLoading(true)
    setError('')
    try {
      const params = new URLSearchParams({ resource: target, page: String(targetPage), pageSize: '50', q: targetQuery })
      const response = await fetch(`/api/zadmin/data?${params.toString()}`, { cache: 'no-store' })
      const body = await response.json()
      if (!response.ok) throw new Error(body.error ?? 'Could not load this section.')
      if (target === 'overview') setOverview(body as Overview)
      else {
        setTableInfo(body as TableResponse)
        setRows(body.rows as Row[])
      }
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Could not load this section.')
    } finally {
      setLoading(false)
    }
  }, [page, query, section])

  useEffect(() => { void refresh(section) }, [section, refresh])

  const currentResource = resources.find((item) => item.key === section)
  const visibleRows = rows

  function chooseSection(key: string) {
    setSection(key)
    setQuery('')
    setPage(1)
    setMobileNav(false)
    setEditor(null)
  }

  async function signOut() {
    await fetch('/api/zadmin/logout', { method: 'POST' })
    window.location.assign('/zadmin/login')
  }

  function editRecord(row: Row) {
    setEditor({ mode: 'edit', row })
  }

  async function saveRecord(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    if (!editor || !tableInfo) return
    const form = new FormData(event.currentTarget)
    const values: Record<string, unknown> = {}
    for (const field of tableInfo.fields) {
      const value = form.get(field.key)
      if (field.type === 'boolean') values[field.key] = form.get(field.key) === 'on'
      else if (value === '' || value === null) {
        if (editor.mode === 'edit') values[field.key] = null
      } else if (field.type === 'number') values[field.key] = Number(value)
      else if (field.type === 'datetime') values[field.key] = new Date(String(value)).toISOString()
      else values[field.key] = value
    }
    setSaving(true)
    setError('')
    try {
      const resource = tableInfo.resource.key
      const response = await fetch('/api/zadmin/data', {
        method: editor.mode === 'create' ? 'POST' : 'PATCH',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ resource, id: editor.row?.[resources.find((item) => item.key === resource)?.idKey ?? 'id'], values }),
      })
      const body = await response.json()
      if (!response.ok) throw new Error(body.error ?? 'Could not save changes.')
      setEditor(null)
      setNotice(editor.mode === 'create' ? 'Item created successfully.' : 'Changes saved successfully.')
      await refresh(resource)
      window.setTimeout(() => setNotice(''), 3400)
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Could not save changes.')
    } finally {
      setSaving(false)
    }
  }

  async function removeRecord(row: Row) {
    if (!tableInfo || !window.confirm('Remove this item? This action cannot be undone.')) return
    const resource = resources.find((item) => item.key === tableInfo.resource.key)
    if (!resource) return
    setError('')
    const response = await fetch('/api/zadmin/data', {
      method: 'DELETE', headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ resource: resource.key, id: row[resource.idKey] }),
    })
    const body = await response.json()
    if (!response.ok) setError(body.error ?? 'Could not remove this item.')
    else { setNotice('Item removed.'); await refresh(resource.key); window.setTimeout(() => setNotice(''), 3400) }
  }

  async function uploadMedia(event: ChangeEvent<HTMLInputElement>) {
    const file = event.target.files?.[0]
    event.target.value = ''
    if (!file) return
    setUploading(true)
    setError('')
    try {
      const request = await fetch('/api/zadmin/media/upload', {
        method: 'POST', headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ filename: file.name, mimeType: file.type, size: file.size }),
      })
      const signed = await request.json()
      if (!request.ok) throw new Error(signed.error ?? 'Could not start this upload.')
      const uploaded = await fetch(signed.uploadUrl as string, { method: 'PUT', headers: { 'content-type': file.type }, body: file })
      if (!uploaded.ok) throw new Error('Cloudflare R2 rejected the upload. Check the bucket CORS settings and credentials.')
      const completed = await fetch('/api/zadmin/media/complete', {
        method: 'POST', headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ objectKey: signed.objectKey, filename: file.name, mimeType: file.type, size: file.size }),
      })
      const result = await completed.json()
      if (!completed.ok) throw new Error(result.error ?? 'Could not save the media record.')
      setNotice('Media uploaded to private R2 and added to the media library.')
      await refresh('media_assets')
      window.setTimeout(() => setNotice(''), 4000)
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Upload failed.')
    } finally {
      setUploading(false)
    }
  }

  function startCreate() {
    if (!tableInfo) return
    setError('')
    setEditor({ mode: 'create', row: null })
  }

  return (
    <div className="za-app">
      {mobileNav ? <button className="za-mobile-scrim" aria-label="Close navigation" onClick={() => setMobileNav(false)} /> : null}
      <aside className={`za-sidebar ${mobileNav ? 'za-sidebar-open' : ''}`}>
        <a className="za-side-brand" href="/zadmin"><span className="za-brand-monogram">CCB</span><span><b>CCB INDIA</b><small>ADMIN WORKSPACE</small></span></a>
        <div className="za-side-rule" />
        <div className="za-side-nav">
          {navigationGroups.map((group) => <div className="za-nav-group" key={group.label}>
            <span className="za-nav-caption">{group.label}</span>
            {group.items.map((key) => {
              const Icon = key === 'overview' ? Grid2X2 : iconFor[key] ?? Grid2X2
              const label = key === 'overview' ? 'Overview' : displayLabels[key] ?? key
              return <button key={key} className={`za-nav-item ${section === key ? 'active' : ''}`} onClick={() => chooseSection(key)}><Icon size={17} strokeWidth={1.8} /><span>{label}</span>{key === 'membership_applications' && overview?.counts.applications ? <small>{overview.counts.applications}</small> : null}</button>
            })}
          </div>)}
        </div>
        <div className="za-sidebar-bottom">
          <div className="za-support-card"><span className="za-support-icon"><CircleHelp size={16} /></span><div><b>Need a hand?</b><small>Workspace support</small></div><ArrowUpRight size={15} /></div>
          <div className="za-admin-profile"><span className="za-admin-avatar">{adminId.slice(0, 1).toUpperCase()}</span><div className="za-admin-meta"><b>{adminId}</b><small>Administrator</small></div><button onClick={() => void signOut()} aria-label="Sign out"><LogOut size={17} /></button></div>
        </div>
      </aside>

      <div className="za-main-column">
        <header className="za-topbar">
          <button className="za-mobile-menu" aria-label="Open navigation" onClick={() => setMobileNav(true)}><Menu size={21} /></button>
          <div className="za-breadcrumb"><span>CCB India</span><ChevronRight size={14} /><b>{section === 'overview' ? 'Overview' : displayLabels[section]}</b></div>
          <div className="za-top-actions"><span className="za-live-state"><i /> Platform workspace</span><button className="za-icon-button" title="Settings"><Settings2 size={18} /></button><button className="za-icon-button za-notification" title="Notifications"><Bell size={18} /><i /></button><span className="za-top-avatar">{adminId.slice(0, 1).toUpperCase()}</span></div>
        </header>
        <main className="za-content">
          {section === 'overview' ? <OverviewPage overview={overview} loading={loading} error={error} onNavigate={chooseSection} /> : <>
            <div className="za-page-head">
              <div><div className="za-overline"><span>ADMINISTRATION</span><span className="za-overline-dot" /> PLATFORM DATA</div><h1>{currentResource?.label ?? 'Workspace'}</h1><p>{currentResource?.description ?? 'Manage the CCB India platform.'}</p></div>
              {tableInfo?.resource.create ? <button className="za-primary-button" onClick={startCreate}><Plus size={17} /> Add {tableInfo.resource.label.replace(/s$/, '')}</button> : null}
            </div>
            <div className="za-table-card">
              <div className="za-table-toolbar"><div className="za-table-summary"><b>{loading ? 'Loading...' : `${tableInfo?.total ?? 0} records`}</b><span>Showing {tableInfo?.total ? `${(page - 1) * (tableInfo.pageSize || 50) + 1}-${Math.min(page * (tableInfo.pageSize || 50), tableInfo.total)} of ${tableInfo.total}` : '0'}  |  50 per page</span></div><div className="za-toolbar-actions">{section === 'media_assets' ? <><input ref={uploadInput} className="za-hidden-file" type="file" accept="image/jpeg,image/png,image/webp,image/avif,image/gif,video/mp4,video/webm,video/quicktime" onChange={(event) => void uploadMedia(event)} /><button className="za-primary-button" onClick={() => uploadInput.current?.click()} disabled={uploading}>{uploading ? <span className="za-spinner za-spinner-light" /> : <Plus size={16} />}{uploading ? 'Uploading...' : 'Upload media'}</button></> : null}<label className="za-search"><Search size={16} /><input value={query} onChange={(event) => { setQuery(event.target.value); setPage(1) }} placeholder={`Search ${currentResource?.label.toLowerCase() ?? 'records'}...`} /><kbd>Ctrl K</kbd></label></div></div>
              {error ? <div className="za-inline-error"><CircleHelp size={17} /><span>{error}</span><button onClick={() => void refresh()}>Retry</button></div> : null}
              <div className="za-table-scroll"><table className="za-table"><thead><tr><th className="za-check-cell"><input type="checkbox" aria-label="Select all rows" /></th>{(tableInfo?.columns ?? []).map((column) => <th key={column.key}>{column.label}<ChevronDown size={12} /></th>)}<th className="za-actions-cell">Action</th></tr></thead><tbody>
                {loading && !tableInfo ? <tr><td colSpan={7}><div className="za-table-loading"><span className="za-spinner" />Loading records</div></td></tr> : null}
                {!loading && !error && visibleRows.length === 0 ? <tr><td colSpan={(tableInfo?.columns.length ?? 5) + 2}><div className="za-empty"><span><Search size={19} /></span><b>{rows.length ? 'No matching records' : 'Nothing here yet'}</b><small>{rows.length ? 'Try another search.' : 'Records will appear here when they are added to the platform.'}</small></div></td></tr> : null}
                {visibleRows.map((row, index) => <tr key={`${String(row[resources.find((item) => item.key === section)?.idKey ?? 'id'] ?? 'row')}-${index}`}>
                  <td className="za-check-cell"><input type="checkbox" aria-label="Select row" /></td>
                  {(tableInfo?.columns ?? []).map((column) => {
                    const value = getValue(row, column.key)
                    const isStatus = column.key === 'status' || column.key === 'verification_status' || column.key === 'availability'
                    if (column.key === 'preview_url') return <td key={column.key}>{typeof value === 'string' ? <a className="za-media-preview" href={value} target="_blank" rel="noreferrer">{String(row.mime_type ?? '').startsWith('video/') ? <video src={value} controls preload="metadata" aria-label={String(row.original_filename ?? 'Video preview')} /> : <img src={value} alt={String(row.original_filename ?? 'Media preview')} />}</a> : <span className="za-media-preview-empty"><FileImage size={14} /></span>}</td>
                    return <td key={column.key}>{isStatus ? <StatusPill value={value} /> : column.key === 'is_public' || column.key === 'is_online' || column.key === 'is_active' ? <span className={`za-boolean ${value ? 'on' : ''}`}><i />{value ? 'Yes' : 'No'}</span> : <span className={column.key === 'title' || column.key === 'company_name' || column.key === 'full_name' ? 'za-cell-primary' : ''}>{formatValue(value, column.key)}</span>}</td>
                  })}
                  <td className="za-row-actions">{(tableInfo?.fields.length ?? 0) > 0 ? <button onClick={() => editRecord(row)} aria-label="Edit record" title="Edit record"><ArrowUpRight size={16} /></button> : null}{tableInfo?.resource.remove ? <button className="za-row-delete" onClick={() => void removeRecord(row)} aria-label="Remove record" title="Remove record"><X size={16} /></button> : null}</td>
                </tr>)}
              </tbody></table></div>
              <div className="za-table-foot"><span>Page {page} of {Math.max(1, Math.ceil((tableInfo?.total ?? 0) / (tableInfo?.pageSize || 50)))}</span><div><button onClick={() => setPage((current) => Math.max(1, current - 1))} disabled={page <= 1 || loading}><ChevronLeft size={16} />Previous</button><button onClick={() => setPage((current) => current + 1)} disabled={loading || page >= Math.ceil((tableInfo?.total ?? 0) / (tableInfo?.pageSize || 50))}>Next<ChevronRight size={16} /></button></div></div>
            </div>
          </>}
        </main>
      </div>

      {editor && tableInfo ? <RecordEditor editor={editor} tableInfo={tableInfo} saving={saving} error={error} onClose={() => setEditor(null)} onSubmit={saveRecord} /> : null}
      {notice ? <div className="za-toast"><span><Check size={15} /></span>{notice}</div> : null}
    </div>
  )
}

function OverviewPage({ overview, loading, error, onNavigate }: { overview: Overview | null; loading: boolean; error: string; onNavigate: (section: string) => void }) {
  const stats = [
    { key: 'members', title: 'Members', Icon: Users, note: 'Community profiles', color: 'blue' },
    { key: 'clients', title: 'Clients', Icon: BriefcaseBusiness, note: 'Organisation accounts', color: 'violet' },
    { key: 'events', title: 'Events', Icon: CalendarDays, note: 'All platform events', color: 'gold' },
    { key: 'programs', title: 'Programs', Icon: Layers3, note: 'Active initiatives', color: 'green' },
  ] as const
  const applications = overview?.counts.applications
  const today = new Intl.DateTimeFormat('en-IN', { weekday: 'long', day: '2-digit', month: 'long' }).format(new Date()).toUpperCase()
  return <>
    <div className="za-welcome-row"><div><div className="za-overline"><span>{today}</span><span className="za-overline-dot" /><span>ADMIN OVERVIEW</span></div><h1>Good to see you <span>at CCB.</span></h1><p>Your platform at a glance. Here's what's happening across your community.</p></div><button className="za-date-button"><CalendarDays size={16} />This month<ChevronDown size={14} /></button></div>
    {error ? <div className="za-inline-error"><CircleHelp size={17} /><span>{error}</span></div> : null}
    {overview?.unavailable ? <div className="za-setup-notice"><ShieldCheck size={18} /><div><b>Connect your Supabase schema to load live numbers.</b><span>The dashboard is ready. Apply the platform migrations and add the server keys from the setup guide.</span></div><ArrowRight size={17} /></div> : null}
    <div className="za-stats-grid">{stats.map(({ key, title, Icon, note, color }, index) => <article className="za-stat-card" key={key}><div className="za-stat-head"><span className={`za-stat-icon ${color}`}><Icon size={19} strokeWidth={1.7} /></span><button className="za-stat-menu" aria-label={`${title} menu`}><span /><span /><span /></button></div><div className="za-stat-number">{loading && !overview ? <i className="za-stat-skeleton" /> : overview?.counts[key] == null ? '-' : overview.counts[key]?.toLocaleString('en-IN')}</div><div className="za-stat-bottom"><b>{title}</b><small>{note}</small></div><span className="za-stat-index">0{index + 1}</span></article>)}</div>
    <div className="za-overview-grid">
      <section className="za-panel za-activity-panel"><div className="za-panel-head"><div><span className="za-panel-kicker">YOUR PLATFORM</span><h2>Recent events</h2></div><button className="za-text-button" onClick={() => onNavigate('events')}>View all<ArrowRight size={15} /></button></div>
        {overview?.recentEvents?.length ? <div className="za-event-list">{overview.recentEvents.map((event) => <button className="za-event-row" key={String(event.id)} onClick={() => onNavigate('events')}><span className="za-event-calendar"><small>{event.starts_at ? new Date(String(event.starts_at)).toLocaleString('en-IN', { month: 'short' }).toUpperCase() : 'NEW'}</small><b>{event.starts_at ? new Date(String(event.starts_at)).getDate() : '-'}</b></span><span className="za-event-title"><b>{String(event.title)}</b><small>{event.starts_at ? new Date(String(event.starts_at)).toLocaleString('en-IN', { weekday: 'short', hour: '2-digit', minute: '2-digit' }) : 'Date to be confirmed'}</small></span><StatusPill value={event.status} /><ArrowUpRight size={15} /></button>)}</div> : <div className="za-empty za-empty-short"><span><CalendarDays size={18} /></span><b>{loading ? 'Loading events...' : 'Your event calendar is ready'}</b><small>Create an event to see it here.</small><button className="za-primary-button za-small-button" onClick={() => onNavigate('events')}><Plus size={15} />Manage events</button></div>}
      </section>
      <section className="za-panel za-applications-panel"><div className="za-panel-head"><div><span className="za-panel-kicker">REQUIRES ATTENTION</span><h2>Membership applications</h2></div><span className="za-attention-icon"><ClipboardList size={18} /></span></div><div className="za-application-total"><strong>{applications == null ? '-' : applications.toLocaleString('en-IN')}</strong><span>applications<br />received</span></div><div className="za-application-meter"><span style={{ width: `${applications && applications > 0 ? Math.min(100, 27 + applications * 6) : 9}%` }} /></div><p>Review applications and update their status from your inbox.</p><button className="za-dark-button" onClick={() => onNavigate('membership_applications')}>Open applications<ArrowUpRight size={16} /></button></section>
    </div>
    <section className="za-quick-section"><div className="za-quick-heading"><div><span className="za-panel-kicker">SHORTCUTS</span><h2>Make something happen</h2></div><span>YOUR MOST USED TOOLS</span></div><div className="za-quick-grid"><button onClick={() => onNavigate('events')}><span className="za-quick-icon quick-gold"><CalendarDays size={18} /></span><span><b>Plan an event</b><small>Set dates, venue and registration</small></span><ArrowUpRight size={16} /></button><button onClick={() => onNavigate('articles')}><span className="za-quick-icon quick-blue"><FileText size={18} /></span><span><b>Publish a story</b><small>Share news with your community</small></span><ArrowUpRight size={16} /></button><button onClick={() => onNavigate('members')}><span className="za-quick-icon quick-violet"><Users size={18} /></span><span><b>Explore members</b><small>Review profiles and visibility</small></span><ArrowUpRight size={16} /></button></div></section>
    <div className="za-footer-note"><ShieldCheck size={15} /> Changes made here are saved to your CCB India platform database.</div>
  </>
}

function RecordEditor({ editor, tableInfo, saving, error, onClose, onSubmit }: { editor: { mode: 'create' | 'edit'; row: Row | null }; tableInfo: TableResponse; saving: boolean; error: string; onClose: () => void; onSubmit: (event: FormEvent<HTMLFormElement>) => void }) {
  const initial: Record<string, unknown> = {}
  for (const field of tableInfo.fields) {
    initial[field.key] = toFormValue(editor.row?.[field.key], field)
    if (editor.mode === 'create' && field.key === 'is_active' && ['professional_categories', 'skills'].includes(tableInfo.resource.key)) initial[field.key] = true
  }
  const title = editor.mode === 'create' ? `Add ${tableInfo.resource.label.replace(/s$/, '')}` : 'Edit record'
  return <div className="za-modal-backdrop" role="presentation" onMouseDown={(event) => { if (event.target === event.currentTarget) onClose() }}><section className="za-editor-modal" role="dialog" aria-modal="true" aria-labelledby="za-editor-title"><header className="za-editor-head"><div><span className="za-panel-kicker">{tableInfo.resource.label.toUpperCase()}</span><h2 id="za-editor-title">{title}</h2></div><button onClick={onClose} aria-label="Close"><X size={19} /></button></header><form onSubmit={onSubmit}><div className="za-editor-fields">{tableInfo.fields.map((field) => <label key={field.key} className={`za-editor-field ${field.type === 'textarea' ? 'wide' : ''}`}><span>{field.label}{field.required ? <i> *</i> : null}</span><FieldControl field={field} value={initial[field.key]} onChange={() => undefined} /></label>)}</div>
    {/* Form controls use native form state so boolean values and browser validation stay accessible. */}
    {error ? <div className="za-inline-error"><CircleHelp size={16} />{error}</div> : null}<div className="za-editor-actions"><button type="button" className="za-cancel-button" onClick={onClose}>Cancel</button><button type="submit" className="za-primary-button" disabled={saving}>{saving ? 'Saving...' : editor.mode === 'create' ? 'Create record' : 'Save changes'}<ArrowUpRight size={16} /></button></div></form></section></div>
}
