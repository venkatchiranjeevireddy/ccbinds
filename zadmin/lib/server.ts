import 'server-only'

import { createClient, type SupabaseClient } from '@supabase/supabase-js'
import { createHmac, randomBytes, timingSafeEqual, createHash } from 'node:crypto'
import { cookies } from 'next/headers'

const COOKIE_NAME = 'ccb_admin_session'
const SESSION_SECONDS = 60 * 60 * 24 * 7
const COOKIE_PATH = '/'

type SessionPayload = { adminId: string; expiresAt: number; credentialVersion: string; nonce: string }

export type AdminSession = { adminId: string; expiresAt: number }

export function getAdminBackend(): SupabaseClient | null {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL
  const key = process.env.SUPABASE_SECRET_KEY ?? process.env.SUPABASE_SERVICE_ROLE_KEY
  if (!url || !key) return null
  return createClient(url, key, {
    auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
  })
}

function getSessionSecret() {
  const secret = process.env.ZADMIN_SESSION_SECRET
  if (!secret || secret.length < 32) return null
  return secret
}

function sign(value: string, secret: string) {
  return createHmac('sha256', secret).update(value).digest('base64url')
}

function hashCredential(passwordHash: string) {
  return createHash('sha256').update(passwordHash).digest('base64url')
}

function parseToken(token: string, secret: string): SessionPayload | null {
  const [payloadPart, signature, extra] = token.split('.')
  if (!payloadPart || !signature || extra) return null
  const expected = Buffer.from(sign(payloadPart, secret))
  const received = Buffer.from(signature)
  if (expected.length !== received.length || !timingSafeEqual(expected, received)) return null
  try {
    const value = JSON.parse(Buffer.from(payloadPart, 'base64url').toString('utf8')) as SessionPayload
    if (!value.adminId || !value.credentialVersion || !value.nonce || !Number.isInteger(value.expiresAt)) return null
    if (value.expiresAt <= Math.floor(Date.now() / 1000)) return null
    return value
  } catch {
    return null
  }
}

export async function createAdminSession(adminId: string, passwordHash: string) {
  const secret = getSessionSecret()
  if (!secret) throw new Error('ZADMIN_SESSION_SECRET must be set to a random value of at least 32 characters.')
  const expiresAt = Math.floor(Date.now() / 1000) + SESSION_SECONDS
  const payload: SessionPayload = {
    adminId,
    expiresAt,
    credentialVersion: hashCredential(passwordHash),
    nonce: randomBytes(18).toString('base64url'),
  }
  const payloadPart = Buffer.from(JSON.stringify(payload)).toString('base64url')
  const token = `${payloadPart}.${sign(payloadPart, secret)}`
  const store = await cookies()
  store.set(COOKIE_NAME, token, {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'strict',
    path: COOKIE_PATH,
    maxAge: SESSION_SECONDS,
    expires: new Date(expiresAt * 1000),
  })
}

export async function clearAdminSession() {
  const store = await cookies()
  store.set(COOKIE_NAME, '', {
    httpOnly: true,
    secure: process.env.NODE_ENV === 'production',
    sameSite: 'strict',
    path: COOKIE_PATH,
    maxAge: 0,
    expires: new Date(0),
  })
}

export async function getAdminSession(): Promise<AdminSession | null> {
  const secret = getSessionSecret()
  const backend = getAdminBackend()
  if (!secret || !backend) return null
  const store = await cookies()
  const token = store.get(COOKIE_NAME)?.value
  if (!token) return null
  const payload = parseToken(token, secret)
  if (!payload) return null

  // Deleting an Admin or changing their password invalidates their sessions promptly.
  const { data, error } = await backend
    .from('admin_accounts')
    .select('password_hash')
    .eq('admin_id', payload.adminId)
    .maybeSingle()
  if (error || !data || hashCredential(data.password_hash) !== payload.credentialVersion) return null
  return { adminId: payload.adminId, expiresAt: payload.expiresAt }
}

export function hasAdminConfiguration() {
  return Boolean(
    process.env.NEXT_PUBLIC_SUPABASE_URL &&
    (process.env.SUPABASE_SECRET_KEY || process.env.SUPABASE_SERVICE_ROLE_KEY) &&
    process.env.ZADMIN_SESSION_SECRET &&
    process.env.ZADMIN_SESSION_SECRET.length >= 32,
  )
}

export async function verifyTurnstile(token: string, ip?: string | null) {
  const secret = process.env.TURNSTILE_SECRET_KEY
  if (!secret) return process.env.NODE_ENV !== 'production'
  if (!token) return false
  try {
    const body = new URLSearchParams({ secret, response: token })
    if (ip) body.set('remoteip', ip)
    const response = await fetch('https://challenges.cloudflare.com/turnstile/v0/siteverify', {
      method: 'POST',
      body,
      cache: 'no-store',
    })
    const result = (await response.json()) as { success?: boolean }
    return Boolean(result.success)
  } catch {
    return false
  }
}
