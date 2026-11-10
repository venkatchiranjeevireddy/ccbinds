import { redirect } from 'next/navigation'
import { AdminConsole } from '@/zadmin/components/admin-console'
import { getAdminSession, hasAdminConfiguration } from '@/zadmin/lib/server'

export const dynamic = 'force-dynamic'

export default async function AdminPage() {
  if (!hasAdminConfiguration()) redirect('/zadmin/login?setup=required')
  const session = await getAdminSession()
  if (!session) redirect('/zadmin/login')
  return <AdminConsole adminId={session.adminId} />
}
