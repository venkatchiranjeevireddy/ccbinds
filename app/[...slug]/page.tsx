import { notFound } from 'next/navigation'
import { PublicPage } from '../page'

export const dynamic = 'force-dynamic'

const staticPages = new Set([
  'about', 'ecosystem', 'programs', 'events', 'membership', 'partnerships',
  'knowledge-hub', 'recognition', 'leadership', 'news', 'contact',
  'membership-application', 'partnership-enquiry', 'event-registration',
])

export default async function PublicRoute({ params }: { params: Promise<{ slug: string[] }> }) {
  const { slug } = await params
  const path = slug.join('/')
  const isContentDetail = /^(events|programs|knowledge-hub|news)\/[a-z0-9][a-z0-9-]{0,119}$/i.test(path)
  if (!staticPages.has(path) && !isContentDetail) notFound()
  return <PublicPage path={path}/>
}
