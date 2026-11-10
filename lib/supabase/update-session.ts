import { createServerClient } from '@supabase/ssr'
import { NextResponse, type NextRequest } from 'next/server'
import { getSupabaseConfig } from './shared'

export async function updateSession(request: NextRequest) {
  let response = NextResponse.next({ request })
  const config = getSupabaseConfig()
  if (!config) return response

  const supabase = createServerClient(config.url, config.key, {
    cookies: {
      getAll() {
        return request.cookies.getAll()
      },
      setAll(cookiesToSet) {
        cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value))
        response = NextResponse.next({ request })
        cookiesToSet.forEach(({ name, value, options }) => response.cookies.set(name, value, options))
      },
    },
  })

  // Refresh the cookie-backed session when needed. Route pages still verify the user
  // and account profile themselves before rendering protected workspace content.
  await supabase.auth.getUser()
  return response
}
