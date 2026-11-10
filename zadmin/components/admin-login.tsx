'use client'

import Script from 'next/script'
import { FormEvent, useEffect, useRef, useState } from 'react'
import { ArrowUpRight, Eye, EyeOff, Fingerprint, ShieldCheck } from 'lucide-react'

type TurnstileApi = {
  render: (element: HTMLElement, options: { sitekey: string; callback: (token: string) => void; 'expired-callback': () => void; 'error-callback': () => void; theme?: 'light' | 'dark' }) => string
  reset: (widgetId?: string) => void
  remove: (widgetId?: string) => void
}

declare global {
  interface Window { turnstile?: TurnstileApi }
}

export function AdminLogin({ siteKey }: { siteKey: string }) {
  const widgetRoot = useRef<HTMLDivElement>(null)
  const widgetId = useRef<string | null>(null)
  const [scriptReady, setScriptReady] = useState(false)
  const [captchaLoadError, setCaptchaLoadError] = useState(false)
  const [adminId, setAdminId] = useState('')
  const [password, setPassword] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [turnstileToken, setTurnstileToken] = useState('')
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)

  useEffect(() => {
    if (!siteKey || !scriptReady || !widgetRoot.current || !window.turnstile || widgetId.current) return
    widgetId.current = window.turnstile.render(widgetRoot.current, {
      sitekey: siteKey,
      theme: 'light',
      callback: setTurnstileToken,
      'expired-callback': () => setTurnstileToken(''),
      'error-callback': () => setTurnstileToken(''),
    })
    return () => {
      if (widgetId.current && window.turnstile) window.turnstile.remove(widgetId.current)
      widgetId.current = null
    }
  }, [siteKey, scriptReady])

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()
    setBusy(true)
    setError('')
    try {
      const response = await fetch('/api/zadmin/login', {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ adminId, password, turnstileToken }),
      })
      const result = await response.json() as { error?: string; redirectTo?: string }
      if (!response.ok) throw new Error(result.error ?? 'Could not sign in.')
      window.location.assign(result.redirectTo ?? '/zadmin')
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : 'Could not sign in. Please try again.')
      if (widgetId.current && window.turnstile) window.turnstile.reset(widgetId.current)
      setTurnstileToken('')
    } finally {
      setBusy(false)
    }
  }

  return (
    <main className="za-login-page">
      {siteKey ? <Script src="https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit" strategy="afterInteractive" onLoad={() => setScriptReady(true)} onError={() => setCaptchaLoadError(true)} /> : null}
      <section className="za-login-story">
        <a href="/" className="za-login-brand"><span className="za-brand-monogram">CCB</span><span>INDIA<span className="za-brand-dot">.</span></span></a>
        <div className="za-story-copy">
          <span className="za-kicker">ADMINISTRATOR ACCESS</span>
          <h1>One workspace.<br /><em>Every connection.</em></h1>
          <p>Manage the CCB India platform, its community, events and stories from one secure workspace.</p>
        </div>
        <div className="za-story-foot"><ShieldCheck size={16} /> Private access for authorised administrators <ArrowUpRight size={15} /></div>
        <div className="za-orbit za-orbit-one" /><div className="za-orbit za-orbit-two" /><div className="za-orbit-core">CCB</div>
      </section>
      <section className="za-login-side">
        <div className="za-login-card">
          <div className="za-login-symbol"><Fingerprint size={22} strokeWidth={1.7} /></div>
          <span className="za-kicker">WELCOME BACK</span>
          <h2>Sign in to your<br />Admin workspace</h2>
          <p className="za-login-intro">Use the Admin ID and password provisioned for you.</p>
          <form onSubmit={submit} className="za-login-form">
            <label className="za-field"><span>Admin ID</span><input autoComplete="username" value={adminId} onChange={(event) => setAdminId(event.target.value)} placeholder="Enter your Admin ID" required /></label>
            <label className="za-field"><span>Password</span><span className="za-password-wrap"><input autoComplete="current-password" type={showPassword ? 'text' : 'password'} value={password} onChange={(event) => setPassword(event.target.value)} placeholder="Enter your password" required /><button type="button" onClick={() => setShowPassword(!showPassword)} aria-label={showPassword ? 'Hide password' : 'Show password'}>{showPassword ? <EyeOff size={17} /> : <Eye size={17} />}</button></span></label>
            {siteKey ? <div className="za-turnstile" ref={widgetRoot} /> : <div className="za-captcha-note">Security verification will appear here once Turnstile is configured.</div>}
            {captchaLoadError ? <p className="za-form-error" role="alert">The security check could not load. Check your Turnstile site key and domain settings.</p> : null}
            {error ? <p className="za-form-error" role="alert">{error}</p> : null}
            <button className="za-login-submit" type="submit" disabled={busy || (Boolean(siteKey) && !turnstileToken)}>{busy ? 'Checking credentials…' : 'Sign in securely'}<ArrowUpRight size={17} /></button>
          </form>
          <div className="za-login-security"><ShieldCheck size={15} /><span>Your session stays active for 7 days on this device.</span></div>
        </div>
        <div className="za-login-copyright">© {new Date().getFullYear()} CCB India · Chamber of Creators and Brands</div>
      </section>
    </main>
  )
}
