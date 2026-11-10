import type { Metadata } from 'next'
import { redirect } from 'next/navigation'
import { AdminLogin } from '@/zadmin/components/admin-login'
import { getAdminSession } from '@/zadmin/lib/server'

export const metadata: Metadata = { title: 'Admin sign in | CCB India' }
export const dynamic = 'force-dynamic'

export default async function AdminLoginPage() {
  if (await getAdminSession()) redirect('/zadmin')
  return <AdminLogin siteKey={process.env.NEXT_PUBLIC_TURNSTILE_SITE_KEY ?? ''} />
}
