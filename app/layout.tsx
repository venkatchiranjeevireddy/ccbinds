import type { Metadata } from 'next'
import './globals.css'

export const metadata: Metadata = {
  title: { default: 'CCB India | Chamber of Creators and Brands', template: '%s | CCB India' },
  description: 'Advancing education, collaboration and professional development across India’s creator and brand ecosystem.',
  openGraph: { title: 'CCB India', description: 'Building connections. Empowering creators. Strengthening brands.', type: 'website' },
}

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return <html lang="en"><body>{children}</body></html>
}
