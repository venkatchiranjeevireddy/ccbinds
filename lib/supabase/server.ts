import { createServerClient } from '@supabase/ssr'
import { cookies } from 'next/headers'
import { getSupabaseConfig } from './shared'

export async function createClient() {
  const config = getSupabaseConfig()
  if (!config) throw new Error('Supabase is not configured. Add the Supabase URL and anon key to .env.local.')

  const cookieStore = await cookies()
  return createServerClient(config.url, config.key, {
    cookies: {
      getAll() {
        return cookieStore.getAll()
      },
      setAll(cookiesToSet) {
        try {
          cookiesToSet.forEach(({ name, value, options }) => cookieStore.set(name, value, options))
        } catch {
          // Server Components cannot write cookies. The root proxy refreshes auth cookies.
        }
      },
    },
  })
}
