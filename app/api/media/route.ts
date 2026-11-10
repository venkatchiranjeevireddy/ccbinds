import { NextRequest, NextResponse } from 'next/server'
import { createClient as createUserClient } from '@/lib/supabase/server'
import { getR2Config, presignR2Request } from '@/zadmin/lib/r2'

export const runtime = 'nodejs'
export const dynamic = 'force-dynamic'

const PROFILE_IMAGE_TYPES = new Set(['image/jpeg', 'image/png', 'image/webp', 'image/avif'])
const PORTFOLIO_IMAGE_TYPES = new Set([...PROFILE_IMAGE_TYPES, 'image/gif'])
const PORTFOLIO_VIDEO_TYPES = new Set(['video/mp4', 'video/webm', 'video/quicktime'])
const PORTFOLIO_DOCUMENT_TYPES = new Set(['application/pdf'])
const IMAGE_LIMIT = 10 * 1024 * 1024
const VIDEO_LIMIT = 100 * 1024 * 1024
const DOCUMENT_LIMIT = 20 * 1024 * 1024

function uploadLimit(role: string, purpose: string, mimeType: string) {
  if (purpose === 'profile' && PROFILE_IMAGE_TYPES.has(mimeType)) return IMAGE_LIMIT
  if (role === 'member' && purpose === 'portfolio') {
    if (PORTFOLIO_IMAGE_TYPES.has(mimeType)) return IMAGE_LIMIT
    if (PORTFOLIO_VIDEO_TYPES.has(mimeType)) return VIDEO_LIMIT
    if (PORTFOLIO_DOCUMENT_TYPES.has(mimeType)) return DOCUMENT_LIMIT
  }
  return 0
}

function fileSignatureMatches(bytes: Uint8Array, mimeType: string) {
  const ascii = (start: number, length: number) => String.fromCharCode(...bytes.slice(start, start + length))
  if (mimeType === 'image/jpeg') return bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff
  if (mimeType === 'image/png') return [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a].every((value, index) => bytes[index] === value)
  if (mimeType === 'image/webp') return ascii(0, 4) === 'RIFF' && ascii(8, 4) === 'WEBP'
  if (mimeType === 'image/avif') return ascii(4, 4) === 'ftyp' && /^(avif|avis)$/.test(ascii(8, 4))
  if (mimeType === 'image/gif') return ['GIF87a', 'GIF89a'].includes(ascii(0, 6))
  if (mimeType === 'application/pdf') return ascii(0, 5) === '%PDF-'
  if (mimeType === 'video/mp4') return ascii(4, 4) === 'ftyp' && !['qt  ', 'avif', 'avis'].includes(ascii(8, 4))
  if (mimeType === 'video/quicktime') return ascii(4, 4) === 'ftyp' && ascii(8, 4) === 'qt  '
  if (mimeType === 'video/webm') return bytes[0] === 0x1a && bytes[1] === 0x45 && bytes[2] === 0xdf && bytes[3] === 0xa3
  return false
}

function error(message: string, status = 400) {
  return NextResponse.json({ error: message }, { status, headers: { 'Cache-Control': 'no-store' } })
}

async function currentUser() {
  const supabase = await createUserClient()
  const { data: { user }, error: authError } = await supabase.auth.getUser()
  if (authError || !user) return null
  const { data: profile } = await supabase.from('user_profiles').select('account_type').eq('id', user.id).maybeSingle()
  if (profile?.account_type !== 'member' && profile?.account_type !== 'client') return null
  return { supabase, user, role: profile.account_type }
}

export async function POST(request: NextRequest) {
  if (request.headers.get('origin') !== request.nextUrl.origin) return error('Request origin is not allowed.', 403)
  const identity = await currentUser()
  if (!identity) return error('Sign in to upload profile media.', 401)
  const config = getR2Config()
  if (!config) return error('Private file storage is not configured.', 503)

  let body: { filename?: string; mimeType?: string; size?: number; purpose?: string }
  try { body = await request.json() } catch { return error('Invalid upload request.') }
  const filename = typeof body.filename === 'string' ? body.filename.replace(/[\\/\u0000-\u001f]/g, '_').slice(0, 180) : ''
  const mimeType = typeof body.mimeType === 'string' ? body.mimeType.toLowerCase() : ''
  const purpose = body.purpose === 'portfolio' ? 'portfolio' : 'profile'
  const maxBytes = uploadLimit(identity.role, purpose, mimeType)
  if (!filename || !maxBytes || !Number.isInteger(body.size) || !body.size || body.size > maxBytes) {
    return error(purpose === 'portfolio' ? 'Choose a supported portfolio image (10 MB), video (100 MB) or PDF (20 MB).' : 'Choose a JPG, PNG, WebP or AVIF image up to 10 MB.')
  }

  const objectKey = `${identity.role}s/${identity.user.id}/${purpose}/${crypto.randomUUID()}`
  const uploadUrl = presignR2Request(config, 'PUT', objectKey, mimeType, 300)
  return NextResponse.json({ uploadUrl, objectKey, bucket: config.bucket, expiresIn: 300 }, { headers: { 'Cache-Control': 'no-store' } })
}

export async function PUT(request: NextRequest) {
  if (request.headers.get('origin') !== request.nextUrl.origin) return error('Request origin is not allowed.', 403)
  const identity = await currentUser()
  if (!identity) return error('Sign in to finish this upload.', 401)
  const config = getR2Config()
  if (!config) return error('Private file storage is not configured.', 503)

  let body: { objectKey?: string; filename?: string; mimeType?: string; size?: number; altText?: string; purpose?: string }
  try { body = await request.json() } catch { return error('Invalid upload completion request.') }
  const prefix = `${identity.role}s/${identity.user.id}/`
  if (typeof body.objectKey !== 'string' || !body.objectKey.startsWith(prefix) || body.objectKey.includes('..')) return error('Upload does not belong to this account.', 403)
  const mimeType = typeof body.mimeType === 'string' ? body.mimeType.toLowerCase() : ''
  const purpose = body.purpose === 'portfolio' ? 'portfolio' : 'profile'
  const expectedPrefix = `${identity.role}s/${identity.user.id}/${purpose}/`
  const maxBytes = uploadLimit(identity.role, purpose, mimeType)
  if (!body.objectKey.startsWith(expectedPrefix) || !maxBytes || !Number.isInteger(body.size) || !body.size || body.size > maxBytes) return error('Invalid file metadata.')

  const check = await fetch(presignR2Request(config, 'HEAD', body.objectKey, undefined, 60), { method: 'HEAD', cache: 'no-store' })
  if (!check.ok) return error('Uploaded file was not found in private storage.', 400)
  const actualSize = Number(check.headers.get('content-length'))
  const actualType = check.headers.get('content-type')?.split(';')[0]?.toLowerCase()
  if (actualSize !== body.size || actualType !== mimeType) return error('Uploaded file does not match its declared type or size.', 400)
  const signatureResponse = await fetch(presignR2Request(config, 'GET', body.objectKey, undefined, 60), { headers: { Range: 'bytes=0-511' }, cache: 'no-store' })
  if (signatureResponse.status !== 206 || !fileSignatureMatches(new Uint8Array(await signatureResponse.arrayBuffer()), mimeType)) {
    return error('The uploaded file content does not match its declared type.', 400)
  }

  const { data, error: insertError } = await identity.supabase.from('media_assets').insert({
    owner_user_id: identity.user.id,
    bucket_name: config.bucket,
    object_key: body.objectKey,
    original_filename: typeof body.filename === 'string' ? body.filename.slice(0, 180) : null,
    mime_type: mimeType,
    file_size_bytes: actualSize,
    visibility: 'private',
    alt_text: typeof body.altText === 'string' ? body.altText.slice(0, 500) : null,
  }).select('id,original_filename,mime_type,file_size_bytes,visibility').single()
  if (insertError || !data) return error('Could not save private file metadata. Check that the latest Supabase migration is applied.', 503)
  return NextResponse.json({ media: data }, { status: 201, headers: { 'Cache-Control': 'no-store' } })
}

export async function GET(request: NextRequest) {
  const supabase = await createUserClient()
  const mediaId = request.nextUrl.searchParams.get('id')
  if (!mediaId || !/^[0-9a-f-]{36}$/i.test(mediaId)) return error('A valid file ID is required.')
  const { data, error: mediaError } = await supabase.from('media_assets')
    .select('bucket_name,object_key,visibility').eq('id', mediaId).maybeSingle()
  if (mediaError || !data) return error('File not found or access is not allowed.', 404)
  const config = getR2Config()
  if (!config || data.bucket_name !== config.bucket) return error('Private file storage is not configured.', 503)
  const url = presignR2Request(config, 'GET', data.object_key, undefined, 300)
  return NextResponse.redirect(url, { status: 307, headers: { 'Cache-Control': 'private, no-store', 'Referrer-Policy': 'no-referrer' } })
}
