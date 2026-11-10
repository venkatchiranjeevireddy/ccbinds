import { notFound } from 'next/navigation'
import AuthForm from '@/components/auth/auth-form'
import { isAccountType } from '@/lib/supabase/shared'

export default async function SignUpPage({ params }: { params: Promise<{ role: string }> }) {
  const { role } = await params
  if (!isAccountType(role)) notFound()
  return <AuthForm mode="sign-up" role={role} siteKey={process.env.NEXT_PUBLIC_TURNSTILE_SITE_KEY ?? ''}/>
}
