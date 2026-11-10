export type AccountType = 'member' | 'client'

export function isAccountType(value: unknown): value is AccountType {
  return value === 'member' || value === 'client'
}

export function getSupabaseConfig() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL
  const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY

  if (!url || !key) return null
  return { url, key }
}
