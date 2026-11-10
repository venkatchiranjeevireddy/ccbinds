import { NextRequest, NextResponse } from 'next/server'
import { getAdminSession, getAdminBackend } from '@/zadmin/lib/server'
import { getR2Config, presignR2Request } from '@/zadmin/lib/r2'

export const runtime = 'nodejs'

function validFileSignature(bytes: Uint8Array, mimeType: string) {
  const ascii = (start: number, length: number) => String.fromCharCode(...bytes.slice(start, start + length))
  if (mimeType === 'image/jpeg') return bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff
  if (mimeType === 'image/png') return [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a].every((value, index) => bytes[index] === value)
  if (mimeType === 'image/webp') return ascii(0, 4) === 'RIFF' && ascii(8, 4) === 'WEBP'
  if (mimeType === 'image/avif') return ascii(4, 4) === 'ftyp' && /^(avif|avis)$/.test(ascii(8, 4))
  if (mimeType === 'image/gif') return ['GIF87a', 'GIF89a'].includes(ascii(0, 6))
  if (mimeType === 'video/mp4') return ascii(4, 4) === 'ftyp' && !['qt  ', 'avif', 'avis'].includes(ascii(8, 4))
  if (mimeType === 'video/quicktime') return ascii(4, 4) === 'ftyp' && ascii(8, 4) === 'qt  '
  if (mimeType === 'video/webm') return bytes[0] === 0x1a && bytes[1] === 0x45 && bytes[2] === 0xdf && bytes[3] === 0xa3
  return false
}

export async function POST(request: NextRequest) {
  if (request.headers.get('origin') !== request.nextUrl.origin) return NextResponse.json({ error: 'Request origin is not allowed.' }, { status: 403 })
  if (!(await getAdminSession())) return NextResponse.json({ error: 'Admin session expired. Sign in again.' }, { status: 401 })
  const config = getR2Config()
  const backend = getAdminBackend()
  if (!config || !backend) return NextResponse.json({ error: 'R2 and Supabase server configuration are required.' }, { status: 503 })
  let body: { objectKey?: string; filename?: string; mimeType?: string; size?: number }
  try { body = await request.json() } catch { return NextResponse.json({ error: 'Invalid upload confirmation.' }, { status: 400 }) }
  const key = body.objectKey
  const filename = body.filename?.trim().slice(0, 180)
  const mimeType = body.mimeType
  const size = body.size
  const allowedTypes = new Set(['image/jpeg', 'image/png', 'image/webp', 'image/avif', 'image/gif', 'video/mp4', 'video/webm', 'video/quicktime'])
  const maxSize = mimeType?.startsWith('video/') ? 150 * 1024 * 1024 : 10 * 1024 * 1024
  if (!key || !key.startsWith('admin/') || !filename || !mimeType || !allowedTypes.has(mimeType) || typeof size !== 'number' || size < 1 || size > maxSize) {
    return NextResponse.json({ error: 'Upload details are invalid.' }, { status: 400 })
  }
  const headUrl = presignR2Request(config, 'HEAD', key)
  const head = await fetch(headUrl, { method: 'HEAD', cache: 'no-store' })
  if (!head.ok || Number(head.headers.get('content-length')) !== size || head.headers.get('content-type')?.split(';')[0] !== mimeType) {
    return NextResponse.json({ error: 'R2 could not verify the uploaded media.' }, { status: 400 })
  }
  const signature = await fetch(presignR2Request(config, 'GET', key, undefined, 60), { headers: { Range: 'bytes=0-511' }, cache: 'no-store' })
  if (signature.status !== 206 || !validFileSignature(new Uint8Array(await signature.arrayBuffer()), mimeType)) return NextResponse.json({ error: 'The file content does not match its declared image/video type.' }, { status: 400 })
  const { data, error } = await backend.from('media_assets').insert({
    bucket_name: config.bucket, object_key: key, original_filename: filename, mime_type: mimeType,
    file_size_bytes: size, visibility: 'private', alt_text: filename,
  }).select('id,owner_user_id,bucket_name,object_key,original_filename,mime_type,file_size_bytes,visibility,alt_text,created_at').single()
  if (error) return NextResponse.json({ error: 'Image uploaded, but Supabase could not save its media record. Check the platform schema.' }, { status: 503 })
  return NextResponse.json({ row: data }, { status: 201 })
}
