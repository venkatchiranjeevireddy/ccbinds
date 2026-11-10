import { redirect } from 'next/navigation'
import Workspace from '@/components/dashboard/workspace'
import { createClient } from '@/lib/supabase/server'
import { getSupabaseConfig } from '@/lib/supabase/shared'

export default async function ClientDashboardPage() {
  if (!getSupabaseConfig()) redirect('/auth')
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/auth/client/sign-in')

  const { data: profile } = await supabase.from('user_profiles').select('account_type, display_name').eq('id', user.id).maybeSingle()
  if (profile?.account_type === 'member') redirect('/member/dashboard')
  if (profile?.account_type !== 'client') redirect('/auth')

  return <Workspace role="client" email={user.email ?? ''} name={profile.display_name}/>
}
