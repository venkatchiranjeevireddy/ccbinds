import { NextResponse, type NextRequest } from 'next/server'
import { createClient } from '@/lib/supabase/server'
import { isAccountType } from '@/lib/supabase/shared'

export async function GET(request: NextRequest) {
  const code = request.nextUrl.searchParams.get('code')
  const requestedRole = request.nextUrl.searchParams.get('role')
  const fallback = new URL('/auth', request.url)

  if (!code) {
    fallback.searchParams.set('error', 'oauth')
    return NextResponse.redirect(fallback)
  }

  try {
    const supabase = await createClient()
    const { error: exchangeError } = await supabase.auth.exchangeCodeForSession(code)
    if (exchangeError) throw exchangeError

    const { data: userData, error: userError } = await supabase.auth.getUser()
    if (userError || !userData.user) throw userError ?? new Error('User session was not created.')

    const { data: profile, error: profileError } = await supabase
      .from('user_profiles')
      .select('account_type')
      .eq('id', userData.user.id)
      .maybeSingle()
    if (profileError) throw profileError

    let accountType = profile?.account_type
    if (accountType === null && isAccountType(requestedRole)) {
      const { data: updatedProfile, error: updateError } = await supabase
        .from('user_profiles')
        .update({ account_type: requestedRole })
        .eq('id', userData.user.id)
        .is('account_type', null)
        .select('account_type')
        .maybeSingle()
      if (updateError) throw updateError
      accountType = updatedProfile?.account_type
    }

    const destination = accountType === 'client'
      ? '/client/dashboard'
      : accountType === 'member'
        ? '/member/dashboard'
        : '/auth'
    return NextResponse.redirect(new URL(destination, request.url))
  } catch {
    fallback.searchParams.set('error', 'oauth')
    return NextResponse.redirect(fallback)
  }
}
