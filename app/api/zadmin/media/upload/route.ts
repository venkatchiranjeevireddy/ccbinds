import { randomUUID } from 'node:crypto'
import { NextRequest, NextResponse } from 'next/server'
import { getAdminSession } from '@/zadmin/lib/server'
import { getR2Config, presignR2Request } from '@/zadmin/lib/r2'

export const runtime = 'nodejs'

const allowedTypes = new Set(['image/jpeg', 'image/png', 'image/webp', 'image/avif', 'image/gif', 'video/mp4', 'video/webm', 'video/quicktime'])

export async function POST(request: NextRequest) {
  if (request.headers.get('origin') !== request.nextUrl.origin) return NextResponse.json({ error: 'Request origin is not allowed.' }, { status: 403 })
  if (!(await getAdminSession())) return NextResponse.json({ error: 'Admin session expired. Sign in again.' }, { status: 401 })
  const config = getR2Config()
  if (!config) return NextResponse.json({ error: 'R2 is not configured yet. Add the server-side R2 values to .env.local.' }, { status: 503 })
  let body: { filename?: string; mimeType?: string; size?: number }
  try { body = await request.json() } catch { return NextResponse.json({ error: 'Invalid upload request.' }, { status: 400 }) }
  const filename = body.filename?.trim().slice(0, 180)
  const mimeType = body.mimeType
  const size = body.size
  const maxSize = mimeType?.startsWith('video/') ? 150 * 1024 * 1024 : 10 * 1024 * 1024
  if (!filename || !mimeType || !allowedTypes.has(mimeType) || typeof size !== 'number' || size < 1 || size > maxSize) {
    return NextResponse.json({ error: 'Choose a supported image up to 10 MB or MP4, WebM, or QuickTime video up to 150 MB.' }, { status: 400 })
  }
  const safeName = filename.normalize('NFKD').replace(/[^a-zA-Z0-9._-]+/g, '-').replace(/^-|-$/g, '').slice(-100) || 'image'
  const objectKey = `admin/${new Date().toISOString().slice(0, 7)}/${randomUUID()}-${safeName}`
  return NextResponse.json({
    uploadUrl: presignR2Request(config, 'PUT', objectKey, mimeType),
    verifyUrl: presignR2Request(config, 'HEAD', objectKey),
    objectKey, bucket: config.bucket,
  })
}
