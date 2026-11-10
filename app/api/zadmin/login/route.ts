import { NextRequest, NextResponse } from 'next/server'
import { createAdminSession, getAdminBackend, verifyTurnstile } from '@/zadmin/lib/server'

export const runtime = 'nodejs'

export async function POST(request: NextRequest) {
  if (request.headers.get('origin') !== request.nextUrl.origin) {
    return NextResponse.json({ error: 'Request origin is not allowed.' }, { status: 403 })
  }

  let body: { adminId?: string; password?: string; turnstileToken?: string }
  try {
    body = await request.json()
  } catch {
    return NextResponse.json({ error: 'Enter your Admin ID and password.' }, { status: 400 })
  }

  const adminId = body.adminId?.trim()
  const password = body.password
  if (!adminId || !password || adminId.length > 120 || password.length > 256) {
    return NextResponse.json({ error: 'Enter a valid Admin ID and password.' }, { status: 400 })
  }
  if (!(await verifyTurnstile(body.turnstileToken ?? '', request.headers.get('x-forwarded-for')?.split(',')[0]?.trim()))) {
    return NextResponse.json({ error: 'Complete the security check and try again.' }, { status: 400 })
  }

  const backend = getAdminBackend()
  if (!backend || !process.env.ZADMIN_SESSION_SECRET || process.env.ZADMIN_SESSION_SECRET.length < 32) {
    return NextResponse.json({ error: 'Admin login is not configured yet. Check the server environment settings.' }, { status: 503 })
  }

  const { data: valid, error: verifyError } = await backend.rpc('verify_admin_credentials', {
    p_admin_id: adminId,
    p_password: password,
  })
  if (verifyError) {
    return NextResponse.json({ error: 'Admin database setup is incomplete. Run the static Admin credentials SQL migration.' }, { status: 503 })
  }
  if (!valid) {
    return NextResponse.json({ error: 'The Admin ID or password is incorrect.' }, { status: 401 })
  }

  const { data, error } = await backend
    .from('admin_accounts')
    .select('password_hash')
    .eq('admin_id', adminId)
    .maybeSingle()
  if (error || !data) return NextResponse.json({ error: 'Could not start the Admin session.' }, { status: 503 })

  try {
    await createAdminSession(adminId, data.password_hash)
  } catch {
    return NextResponse.json({ error: 'Admin session is not configured yet.' }, { status: 503 })
  }
  await backend.from('audit_logs').insert({ action: 'admin.login', entity_type: 'admin_session', details: { admin_id: adminId } })
  return NextResponse.json({ ok: true, redirectTo: '/zadmin' })
}
