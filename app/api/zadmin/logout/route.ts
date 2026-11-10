import { NextRequest, NextResponse } from 'next/server'
import { clearAdminSession, getAdminBackend, getAdminSession } from '@/zadmin/lib/server'

export async function POST(request: NextRequest) {
  if (request.headers.get('origin') !== request.nextUrl.origin) {
    return NextResponse.json({ error: 'Request origin is not allowed.' }, { status: 403 })
  }
  const session = await getAdminSession()
  const backend = getAdminBackend()
  if (session && backend) {
    await backend.from('audit_logs').insert({ action: 'admin.logout', entity_type: 'admin_session', details: { admin_id: session.adminId } })
  }
  await clearAdminSession()
  return NextResponse.json({ ok: true, redirectTo: '/zadmin/login' })
}
