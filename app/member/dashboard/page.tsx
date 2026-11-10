import { redirect } from 'next/navigation'
import Workspace from '@/components/dashboard/workspace'
import { createClient } from '@/lib/supabase/server'
import { getSupabaseConfig } from '@/lib/supabase/shared'

export default async function MemberDashboardPage() {
  if (!getSupabaseConfig()) redirect('/auth')
  const supabase = await createClient()
  const { data: { user } } = await supabase.auth.getUser()
  if (!user) redirect('/auth/member/sign-in')

  const { data: profile } = await supabase.from('user_profiles').select('account_type, display_name').eq('id', user.id).maybeSingle()
  if (profile?.account_type === 'client') redirect('/client/dashboard')
  if (profile?.account_type !== 'member') redirect('/auth')

  return <Workspace role="member" email={user.email ?? ''} name={profile.display_name}/>
}
