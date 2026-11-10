'use client'

import Link from 'next/link'
import Script from 'next/script'
import { useRouter } from 'next/navigation'
import { FormEvent, useEffect, useRef, useState } from 'react'
import { ArrowLeft, ArrowRight, LoaderCircle } from 'lucide-react'
import { createClient } from '@/lib/supabase/client'
import { isAccountType, type AccountType } from '@/lib/supabase/shared'

type Props = { mode: 'sign-in' | 'sign-up'; role: AccountType; siteKey?: string }

type TurnstileApi = {
  render: (element: HTMLElement, options: { sitekey: string; callback: (token: string) => void; 'expired-callback': () => void; 'error-callback': () => void; theme?: 'light' | 'dark' }) => string
  reset: (widgetId?: string) => void
  remove: (widgetId?: string) => void
}

declare global { interface Window { turnstile?: TurnstileApi } }

const roleDetails = {
  member: { title: 'Member / Influencer', dashboard: '/member/dashboard' },
  client: { title: 'Client / Business', dashboard: '/client/dashboard' },
} as const

export default function AuthForm({ mode, role, siteKey = '' }: Props) {
  const router = useRouter()
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState('')
  const [notice, setNotice] = useState('')
  const [scriptReady, setScriptReady] = useState(false)
  const [captchaLoadError, setCaptchaLoadError] = useState(false)
  const [captchaWidgetError, setCaptchaWidgetError] = useState(false)
  const [captchaToken, setCaptchaToken] = useState('')
  const captchaRoot = useRef<HTMLDivElement>(null)
  const captchaId = useRef<string | null>(null)
  const isSignup = mode === 'sign-up'

  // next/script keeps this script mounted across client-side navigation.
  // When the user returns to this form, its onLoad callback may not fire again.
  useEffect(() => {
    if (siteKey && window.turnstile) setScriptReady(true)
  }, [siteKey])

  useEffect(() => {
    if (!siteKey || !scriptReady || !captchaRoot.current || !window.turnstile || captchaId.current) return
    try {
      captchaId.current = window.turnstile.render(captchaRoot.current, {
        sitekey: siteKey,
        theme: 'light',
        callback: (token) => {
          setCaptchaToken(token)
          setCaptchaWidgetError(false)
        },
        'expired-callback': () => setCaptchaToken(''),
        'error-callback': () => {
          setCaptchaToken('')
          setCaptchaWidgetError(true)
        },
      })
    } catch {
      setCaptchaWidgetError(true)
    }
    return () => {
      if (captchaId.current && window.turnstile) window.turnstile.remove(captchaId.current)
      captchaId.current = null
    }
  }, [siteKey, scriptReady])

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setBusy(true)
    setError('')
    setNotice('')
    if (!siteKey || !captchaToken) {
      setBusy(false)
      setError(siteKey ? 'Complete the security check before continuing.' : 'The security check is not configured. Please contact CCB support.')
      return
    }
    const form = new FormData(event.currentTarget)
    const email = String(form.get('email') ?? '').trim()
    const password = String(form.get('password') ?? '')

    try {
      const supabase = createClient()
      if (isSignup) {
        const displayName = String(form.get('name') ?? '').trim()
        const { data, error: authError } = await supabase.auth.signUp({
          email,
          password,
          options: {
            data: { account_type: role, display_name: displayName },
            emailRedirectTo: `${window.location.origin}/auth/callback`,
            ...(captchaToken ? { captchaToken } : {}),
          },
        })
        if (authError) throw authError
        if (!data.session) {
          if (captchaId.current && window.turnstile) window.turnstile.reset(captchaId.current)
          setCaptchaToken('')
          setNotice('Check your email to confirm your account. You can sign in after confirming it.')
          return
        }
      } else {
        const { error: authError } = await supabase.auth.signInWithPassword({ email, password, options: captchaToken ? { captchaToken } : undefined })
        if (authError) throw authError
      }

      const { data: userData, error: userError } = await supabase.auth.getUser()
      if (userError) throw userError
      if (!userData.user) throw new Error('Your session could not be loaded. Please try signing in again.')

      const { data: profile, error: profileError } = await supabase
        .from('user_profiles')
        .select('account_type')
        .eq('id', userData.user.id)
        .maybeSingle()
      if (profileError) throw profileError

      if (isAccountType(profile?.account_type)) {
        router.replace(roleDetails[profile.account_type].dashboard)
        router.refresh()
        return
      }

      if (!profile) throw new Error('Your account profile is not ready yet. Please contact CCB support.')
      setError('This account does not have a Member or Client workspace. Please contact CCB support.')
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Something went wrong. Please try again.')
      if (captchaId.current && window.turnstile) window.turnstile.reset(captchaId.current)
      setCaptchaToken('')
    } finally {
      setBusy(false)
    }
  }

  async function continueWithGoogle() {
    if (!siteKey || !captchaToken) {
      setError(siteKey ? 'Complete the security check before continuing with Google.' : 'The security check is not configured. Please contact CCB support.')
      return
    }
    setBusy(true)
    setError('')
    setNotice('')
    try {
      const supabase = createClient()
      const { error: authError } = await supabase.auth.signInWithOAuth({
        provider: 'google',
        options: { redirectTo: `${window.location.origin}/auth/callback?role=${role}`, ...(captchaToken ? { captchaToken } : {}) },
      })
      if (authError) throw authError
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : 'Google sign-in could not start.')
      if (captchaId.current && window.turnstile) window.turnstile.reset(captchaId.current)
      setCaptchaToken('')
      setBusy(false)
    }
  }

  return (
    <main className="auth-page">
      {siteKey ? <Script src="https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit" strategy="afterInteractive" onLoad={() => setScriptReady(true)} onError={() => setCaptchaLoadError(true)}/> : null}
      <div className="auth-wrap auth-form-wrap">
        <Link className="auth-brand" href="/">CCB <span>INDIA</span></Link>
        <Link className="auth-back-link" href="/auth"><ArrowLeft size={14}/> Change account type</Link>
        <div className="auth-heading auth-form-heading">
          <span className="eyebrow">{roleDetails[role].title}</span>
          <h1>{isSignup ? 'Create your account' : 'Welcome back'}</h1>
          <p>{isSignup ? 'Set up your CCB workspace to get started.' : 'Sign in to continue to your CCB dashboard.'}</p>
        </div>

        {siteKey ? <div className="auth-turnstile" ref={captchaRoot} aria-label="Cloudflare security check"/> : <p className="auth-alert auth-error" role="alert">Cloudflare Turnstile is not configured. Add NEXT_PUBLIC_TURNSTILE_SITE_KEY and restart the app.</p>}
        {captchaLoadError && <p className="auth-alert auth-error" role="alert">The security check could not load. Check your Turnstile site key and domain settings.</p>}
        {captchaWidgetError && <p className="auth-alert auth-error" role="alert">Cloudflare could not display the security check. Verify the site key and allow localhost in the Turnstile widget settings.</p>}

        <button className="google-button" type="button" onClick={continueWithGoogle} disabled={busy || !siteKey || !captchaToken}>
          <GoogleMark/> Continue with Google
        </button>
        <div className="auth-divider"><span>or continue with email</span></div>

        <form className="auth-fields" onSubmit={handleSubmit}>
          {isSignup && <label className="auth-field">Full name<input name="name" autoComplete="name" required minLength={2} placeholder="Your name"/></label>}
          <label className="auth-field">Email address<input name="email" type="email" autoComplete="email" required placeholder="you@example.com"/></label>
          <label className="auth-field">Password<input name="password" type="password" autoComplete={isSignup ? 'new-password' : 'current-password'} required minLength={8} placeholder={isSignup ? 'At least 8 characters' : 'Your password'}/></label>
          {error && <p className="auth-alert auth-error" role="alert">{error}</p>}
          {notice && <p className="auth-alert auth-success" role="status">{notice}</p>}
          <button className="btn btn-primary auth-submit" type="submit" disabled={busy || !siteKey || !captchaToken}>
            {busy ? <><LoaderCircle className="auth-spinner" size={16}/> Please wait</> : <>{isSignup ? 'Create account' : 'Sign in'} <ArrowRight size={15}/></>}
          </button>
        </form>

        <p className="auth-switch">
          {isSignup ? 'Already have an account?' : 'New to CCB India?'}{' '}
          <Link href={`/auth/${role}/${isSignup ? 'sign-in' : 'sign-up'}`}>{isSignup ? 'Sign in' : 'Create an account'}</Link>
        </p>
        <p className="auth-terms">By continuing, you agree to CCB India's terms and privacy policy.</p>
      </div>
    </main>
  )
}

function GoogleMark() {
  return <svg aria-hidden="true" viewBox="0 0 48 48" className="google-mark"><path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5Z"/><path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.91c-.58 2.96-2.26 5.48-4.76 7.18l7.73 6C44.39 38.04 46.98 31.9 46.98 24.55Z"/><path fill="#FBBC05" d="M10.53 28.59A14.4 14.4 0 0 1 9.75 24c0-1.59.27-3.13.76-4.59l-7.98-6.2A23.9 23.9 0 0 0 0 24c0 3.87.93 7.54 2.56 10.78l7.97-6.19Z"/><path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.9-5.8l-7.73-6c-2.14 1.44-4.88 2.3-8.17 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48Z"/></svg>
}
