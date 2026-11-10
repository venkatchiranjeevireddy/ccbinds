import Link from 'next/link'
import { ArrowRight, BriefcaseBusiness, UserRound } from 'lucide-react'

export default async function AuthChoicePage({ searchParams }: { searchParams: Promise<{ error?: string }> }) {
  const query = await searchParams
  return (
    <main className="auth-page">
      <div className="auth-wrap auth-choice-wrap">
        <Link className="auth-brand" href="/">CCB <span>INDIA</span></Link>
        <div className="auth-heading">
          <span className="eyebrow">Welcome to CCB India</span>
          <h1>Choose your workspace</h1>
          <p>Sign in or create an account for the right CCB experience.</p>
        </div>
        {query.error === 'oauth' && <p className="auth-alert auth-error auth-choice-error" role="alert">Google sign-in could not be completed. Please try again or use email and password.</p>}
        <div className="account-choice-grid">
          <article className="account-choice-card">
            <div className="account-choice-icon"><UserRound size={22}/></div>
            <h2>Member / Influencer</h2>
            <p>For creators, influencers and creative professionals.</p>
            <div className="account-choice-actions">
              <Link className="btn btn-primary" href="/auth/member/sign-in">Sign in <ArrowRight size={15}/></Link>
              <Link className="auth-text-link" href="/auth/member/sign-up">Create account</Link>
            </div>
          </article>
          <article className="account-choice-card">
            <div className="account-choice-icon"><BriefcaseBusiness size={22}/></div>
            <h2>Client / Business</h2>
            <p>For brands, businesses, agencies and organisations.</p>
            <div className="account-choice-actions">
              <Link className="btn btn-primary" href="/auth/client/sign-in">Sign in <ArrowRight size={15}/></Link>
              <Link className="auth-text-link" href="/auth/client/sign-up">Create account</Link>
            </div>
          </article>
        </div>
        <Link className="auth-back-link" href="/">Back to CCB India</Link>
      </div>
    </main>
  )
}
