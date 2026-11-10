'use client'

import { createBrowserClient } from '@supabase/ssr'
import { getSupabaseConfig } from './shared'

export function createClient() {
  const config = getSupabaseConfig()
  if (!config) throw new Error('Supabase is not configured. Add the Supabase URL and anon key to .env.local.')
  return createBrowserClient(config.url, config.key)
}
