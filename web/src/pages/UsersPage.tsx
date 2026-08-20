import React from 'react'
import { assignUser, createUser, listFamilies, listUsers, resetUserPassword, updateUserRole } from '../lib/api'
import { Badge, Button, Card, ErrorState, Spinner } from '../components/primitives'
import { formatDate, initialsOf } from '../lib/format'
import type { AdminUser, Family, Role } from '../lib/types'
import './pages.css'
import './UsersPage.css'

const roles: Role[] = ['admin', 'member', 'child']

export function UsersPage() {
  const [users, setUsers] = React.useState<AdminUser[]>([])
  const [families, setFamilies] = React.useState<Family[]>([])
  const [loading, setLoading] = React.useState(true)
  const [error, setError] = React.useState<string | null>(null)
  const [refreshKey, setRefreshKey] = React.useState(0)

  React.useEffect(() => {
    let active = true
    setLoading(true)
    Promise.all([listUsers(), listFamilies()])
      .then(([nextUsers, nextFamilies]) => {
        if (!active) return
        setUsers(nextUsers)
        setFamilies(nextFamilies)
        setError(null)
      })
      .catch((e: unknown) => {
        if (active) setError(e instanceof Error ? e.message : 'Could not load users')
      })
      .finally(() => {
        if (active) setLoading(false)
      })
    return () => { active = false }
  }, [refreshKey])

  const reload = () => setRefreshKey((key) => key + 1)

  const replaceUser = (updated: AdminUser) => {
    setUsers((current) => current.map((user) => user.id === updated.id ? updated : user))
  }

  if (loading) {
    return <div className="wb-page"><div className="wb-page-loading"><Spinner /> Loading users…</div></div>
  }
  if (error) {
    return <div className="wb-page"><ErrorState title="Couldn’t load users" description={error} onRetry={reload} /></div>
  }

  return (
    <div className="wb-page">
      <div className="wb-page-header">
        <div>
          <h1 className="wb-page-title">Users</h1>
          <p className="wb-page-subtitle">Create accounts and manage family membership and roles.</p>
        </div>
        <Button variant="secondary" size="sm" onClick={reload}>Refresh</Button>
      </div>
      <CreateUserCard families={families} onCreated={(user) => setUsers((current) => [...current, user].sort((a, b) => a.name.localeCompare(b.name)))} />
      <Card padded={false}>
        <div className="wb-user-table-wrap">
          <table className="wb-table wb-user-table">
            <thead>
              <tr><th>User</th><th>Family</th><th>Role</th><th>Created</th><th /></tr>
            </thead>
            <tbody>
              {users.map((user) => (
                <UserRow key={user.id} user={user} families={families} onUpdated={replaceUser} />
              ))}
            </tbody>
          </table>
          {users.length === 0 && <div className="wb-user-empty">No users yet.</div>}
        </div>
      </Card>
    </div>
  )
}

function CreateUserCard({ families, onCreated }: { families: Family[]; onCreated: (user: AdminUser) => void }) {
  const [name, setName] = React.useState('')
  const [email, setEmail] = React.useState('')
  const [password, setPassword] = React.useState('')
  const [role, setRole] = React.useState<Role>('member')
  const [familyId, setFamilyId] = React.useState('')
  const [error, setError] = React.useState<string | null>(null)
  const [saving, setSaving] = React.useState(false)

  const submit = async (event: React.FormEvent) => {
    event.preventDefault()
    setSaving(true)
    setError(null)
    try {
      const user = await createUser({ email, password, name, role, family_id: familyId || undefined })
      onCreated(user)
      setName(''); setEmail(''); setPassword(''); setRole('member'); setFamilyId('')
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : 'Could not create user')
    } finally {
      setSaving(false)
    }
  }

  return (
    <Card className="wb-create-card">
      <div className="wb-section-heading">
        <div><h2>Create user</h2><p>Accounts can be assigned to a family immediately.</p></div>
      </div>
      <form className="wb-form-grid" onSubmit={submit}>
        <label>Name<input value={name} onChange={(e) => setName(e.target.value)} required maxLength={120} /></label>
        <label>Email<input type="email" value={email} onChange={(e) => setEmail(e.target.value)} required /></label>
        <label>Password<input type="password" value={password} onChange={(e) => setPassword(e.target.value)} required minLength={8} /></label>
        <label>Role<select value={role} onChange={(e) => setRole(e.target.value as Role)}>{roles.map((value) => <option key={value} value={value}>{value}</option>)}</select></label>
        <label>Family<select value={familyId} onChange={(e) => setFamilyId(e.target.value)}><option value="">No family yet</option>{families.map((family) => <option key={family.id} value={family.id}>{family.name}</option>)}</select></label>
        <div className="wb-form-submit"><Button type="submit" loading={saving}>Create user</Button></div>
      </form>
      {error && <p className="wb-inline-error">{error}</p>}
    </Card>
  )
}

function UserRow({ user, families, onUpdated }: { user: AdminUser; families: Family[]; onUpdated: (user: AdminUser) => void }) {
  const [familyId, setFamilyId] = React.useState(user.family_id ?? '')
  const [role, setRole] = React.useState<Role>(user.role)
  const [saving, setSaving] = React.useState(false)
  const [message, setMessage] = React.useState<string | null>(null)

  React.useEffect(() => {
    setFamilyId(user.family_id ?? '')
    setRole(user.role)
  }, [user.family_id, user.role])

  const save = async () => {
    setSaving(true); setMessage(null)
    try {
      let updated = user
      if (familyId !== (user.family_id ?? '')) updated = await assignUser(user.id, familyId || null)
      if (role !== updated.role) updated = await updateUserRole(user.id, role)
      onUpdated(updated)
      setMessage('Saved')
    } catch (e: unknown) {
      setMessage(e instanceof Error ? e.message : 'Could not update user')
    } finally { setSaving(false) }
  }

  const resetPassword = async () => {
    const password = window.prompt(`New password for ${user.email} (minimum 8 characters)`)
    if (!password) return
    setMessage(null)
    try {
      await resetUserPassword(user.id, password)
      setMessage('Password reset')
    } catch (e: unknown) {
      setMessage(e instanceof Error ? e.message : 'Could not reset password')
    }
  }

  return (
    <tr>
      <td><div className="wb-member-cell"><span className="wb-member-dot">{initialsOf(user.name)}</span><span><div className="wb-member-name">{user.name}{user.platform_admin && <Badge tone="pink">Platform admin</Badge>}</div><div className="wb-member-email">{user.email}</div></span></div></td>
      <td><select className="wb-inline-select" value={familyId} onChange={(e) => setFamilyId(e.target.value)}><option value="">No family</option>{families.map((family) => <option key={family.id} value={family.id}>{family.name}</option>)}</select></td>
      <td><select className="wb-inline-select" value={role} onChange={(e) => setRole(e.target.value as Role)}>{roles.map((value) => <option key={value} value={value}>{value}</option>)}</select></td>
      <td className="wb-muted">{formatDate(user.created_at)}</td>
      <td><div className="wb-row-actions"><Button size="sm" onClick={save} loading={saving}>Save</Button><Button size="sm" variant="ghost" onClick={resetPassword}>Reset password</Button>{message && <span className="wb-row-message">{message}</span>}</div></td>
    </tr>
  )
}
