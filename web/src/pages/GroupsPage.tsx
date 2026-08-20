// Groups page — list of families with member counts and a "view members"
// action that expands an inline member table for a family.

import React from 'react'
import { createFamily, listFamilyMembers, listUsers, listFamilies, renameFamily } from '../lib/api'
import { useAsync, isAccessDenied } from '../lib/useAsync'
import {
  AccessDenied,
  Badge,
  Button,
  Card,
  EmptyState,
  ErrorState,
  Spinner,
} from '../components/primitives'
import {
  formatAccuracy,
  formatBattery,
  formatDate,
  formatRelativeTime,
  formatSpeed,
  initialsOf,
  motionLabel,
} from '../lib/format'
import type { AdminUser, Family, Member } from '../lib/types'
import './pages.css'
import './FamilyManagement.css'

export function GroupsPage() {
  const families = useAsync(listFamilies, [])

  if (families.loading) return <GroupsSkeleton />
  if (isAccessDenied(families.error)) {
    return <div className="wb-page"><AccessDenied /></div>
  }
  if (families.error) {
    return (
      <div className="wb-page">
        <ErrorState title="Couldn’t load groups" description={families.error.message} onRetry={families.refetch} />
      </div>
    )
  }

  const list = families.data ?? []
  return (
    <div className="wb-page">
      <div className="wb-page-header">
        <div>
          <h1 className="wb-page-title">Groups</h1>
          <p className="wb-page-subtitle">
            {list.length} {list.length === 1 ? 'family' : 'families'} on this server.
          </p>
        </div>
        <Button variant="secondary" size="sm" onClick={families.refetch}>Refresh</Button>
      </div>
      <CreateFamilyCard onCreated={families.refetch} />
      {list.length === 0 ? (
        <Card><EmptyState title="No groups yet" description="Create a family here, then assign users to it from the Users page." icon={<GroupsIcon />} /></Card>
      ) : (
        <div className="wb-groups-list">
          {list.map((family) => <FamilyRow key={family.id} family={family} onChanged={families.refetch} />)}
        </div>
      )}
    </div>
  )
}

function CreateFamilyCard({ onCreated }: { onCreated: () => void }) {
  const users = useAsync(listUsers, [])
  const [name, setName] = React.useState('')
  const [ownerUserId, setOwnerUserId] = React.useState('')
  const [saving, setSaving] = React.useState(false)
  const [error, setError] = React.useState<string | null>(null)

  const submit = async (event: React.FormEvent) => {
    event.preventDefault(); setSaving(true); setError(null)
    try {
      await createFamily(name, ownerUserId || undefined)
      setName(''); setOwnerUserId(''); onCreated()
    } catch (e: unknown) {
      setError(e instanceof Error ? e.message : 'Could not create family')
    } finally { setSaving(false) }
  }

  return (
    <Card className="wb-create-card">
      <div className="wb-section-heading"><div><h2>Create family</h2><p>Optionally assign an existing user as the first family admin.</p></div></div>
      <form className="wb-form-grid wb-family-form" onSubmit={submit}>
        <label>Family name<input value={name} onChange={(e) => setName(e.target.value)} required maxLength={120} placeholder="The Smiths" /></label>
        <label>First admin<select value={ownerUserId} onChange={(e) => setOwnerUserId(e.target.value)}><option value="">Assign later</option>{(users.data ?? []).filter((user: AdminUser) => !user.family_id).map((user) => <option key={user.id} value={user.id}>{user.name} · {user.email}</option>)}</select></label>
        <div className="wb-form-submit"><Button type="submit" loading={saving}>Create family</Button></div>
      </form>
      {users.error && <p className="wb-inline-error">Could not load unassigned users: {users.error.message}</p>}
      {error && <p className="wb-inline-error">{error}</p>}
    </Card>
  )
}


function FamilyRow({ family, onChanged }: { family: Family; onChanged: () => void }) {
  const [open, setOpen] = React.useState(false)
  const members = useAsync(
    () => (open ? listFamilyMembers(family.id) : Promise.resolve([] as Member[])),
    [family.id, open],
  )

  return (
    <Card padded={false} className="wb-group-card">
      <button
        type="button"
        className="wb-group-head"
        aria-expanded={open}
        onClick={() => setOpen((o) => !o)}
      >
        <span className="wb-group-avatar" aria-hidden="true">
          {initialsOf(family.name)}
        </span>
        <span className="wb-group-meta">
          <span className="wb-group-name">{family.name}</span>
          <span className="wb-group-sub">
            Created {formatDate(family.created_at)}
          </span>
        </span>
        <span className="wb-group-count">
          <Badge tone="purple">
            {family.member_count} {family.member_count === 1 ? 'member' : 'members'}
          </Badge>
        </span>
        <span className={`wb-group-chevron ${open ? 'is-open' : ''}`} aria-hidden="true">
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none">
            <path d="m6 9 6 6 6-6" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
          </svg>
        </span>
      </button>
      <RenameFamily family={family} onChanged={onChanged} />

      {open && (
        <div className="wb-group-body">
          {members.loading ? (
            <div className="wb-group-body-loading">
              <Spinner size={16} /> Loading members…
            </div>
          ) : members.error ? (
            <ErrorState
              title="Couldn’t load members"
              description={members.error.message}
              onRetry={members.refetch}
            />
          ) : (members.data?.length ?? 0) === 0 ? (
            <EmptyState
              title="No members yet"
              description="This family hasn’t added any members."
            />
          ) : (
            <div className="wb-table-wrap">
              <table className="wb-table">
                <thead>
                  <tr>
                    <th>Member</th>
                    <th>Role</th>
                    <th>Last seen</th>
                    <th>Battery</th>
                    <th>Speed</th>
                    <th>Accuracy</th>
                  </tr>
                </thead>
                <tbody>
                  {(members.data ?? []).map((m) => (
                    <tr key={m.id}>
                      <td>
                        <div className="wb-member-cell">
                          <span className="wb-member-dot" aria-hidden="true">
                            {initialsOf(m.name)}
                          </span>
                          <span>
                            <div className="wb-member-name">{m.name}</div>
                            <div className="wb-member-email">{m.email}</div>
                          </span>
                        </div>
                      </td>
                      <td>
                        <RoleBadge role={m.role} />
                      </td>
                      <td className="wb-muted">{formatRelativeTime(m.ts)}</td>
                      <td className="wb-num">
                        <BatteryPct pct={m.battery_pct} />
                      </td>
                      <td className="wb-num">{formatSpeed(m.speed_mps)}</td>
                      <td className="wb-muted wb-num">{formatAccuracy(m.accuracy_meters)}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </div>
      )}
    </Card>
  )
}

function RenameFamily({ family, onChanged }: { family: Family; onChanged: () => void }) {
  const [name, setName] = React.useState(family.name)
  const [editing, setEditing] = React.useState(false)
  const [saving, setSaving] = React.useState(false)
  const [error, setError] = React.useState<string | null>(null)

  if (!editing) {
    return <div className="wb-family-actions"><Button variant="ghost" size="sm" onClick={() => setEditing(true)}>Rename</Button></div>
  }

  const save = async (event: React.FormEvent) => {
    event.preventDefault(); setSaving(true); setError(null)
    try { await renameFamily(family.id, name); setEditing(false); onChanged() }
    catch (e: unknown) { setError(e instanceof Error ? e.message : 'Could not rename family') }
    finally { setSaving(false) }
  }

  return <form className="wb-family-rename" onSubmit={save}><input value={name} onChange={(e) => setName(e.target.value)} maxLength={120} required aria-label={`Rename ${family.name}`} /><Button size="sm" type="submit" loading={saving}>Save</Button><Button size="sm" variant="ghost" type="button" onClick={() => setEditing(false)}>Cancel</Button>{error && <span className="wb-inline-error">{error}</span>}</form>
}

function RoleBadge({ role }: { role: Member['role'] }) {
  const tone = role === 'admin' ? 'pink' : role === 'member' ? 'purple' : 'grey'
  return <Badge tone={tone}>{motionLabel(role)}</Badge>
}

function BatteryPct({ pct }: { pct: number | null }) {
  const text = formatBattery(pct)
  if (pct === null) return <span className="wb-muted">{text}</span>
  const tone = pct <= 15 ? 'red' : pct <= 30 ? 'orange' : 'green'
  return <Badge tone={tone} dot>{text}</Badge>
}

function GroupsSkeleton() {
  return (
    <div className="wb-page">
      <div className="wb-page-header">
        <div>
          <h1 className="wb-page-title">Groups</h1>
          <p className="wb-page-subtitle">Families using this Whereabouts server.</p>
        </div>
      </div>
      <div className="wb-stack">
        {Array.from({ length: 4 }).map((_, i) => (
          <div key={i} className="wb-skeleton wb-skeleton-row" />
        ))}
      </div>
    </div>
  )
}

function GroupsIcon() {
  return (
    <svg width="28" height="28" viewBox="0 0 24 24" fill="none">
      <path
        d="M16 11a3 3 0 1 0-2.6-4.5M8 11a3 3 0 1 1 2.6-4.5M3 20c0-2.8 2-5 4.5-5h9C19 15 21 17.2 21 20"
        stroke="currentColor"
        strokeWidth="1.6"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  )
}