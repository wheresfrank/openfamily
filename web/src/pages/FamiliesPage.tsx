// Families page — list of families with member counts, per-member "move to
// family" repair, invite-code generation, and rename/delete/create actions.

import React from 'react'
import {
  createFamily,
  createInvite,
  deleteFamily,
  listFamilyMembers,
  listFamilies,
  listInvites,
  moveMember,
  renameFamily,
} from '../lib/api'
import { useAsync, isAccessDenied } from '../lib/useAsync'
import {
  AccessDenied,
  Badge,
  Button,
  Card,
  CopyButton,
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
} from '../lib/format'
import type { AdminInvite, Family, Member, Role } from '../lib/types'
import './pages.css'
import './FamiliesPage.css'

export function FamiliesPage() {
  const families = useAsync(listFamilies, [])
  const [creating, setCreating] = React.useState(false)
  const [newName, setNewName] = React.useState('')
  const [busy, setBusy] = React.useState(false)
  const [error, setError] = React.useState<string | null>(null)

  const submitNew = async () => {
    const name = newName.trim()
    if (!name) return
    setBusy(true)
    setError(null)
    try {
      await createFamily(name)
      setNewName('')
      setCreating(false)
      await families.refetch()
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to create family')
    } finally {
      setBusy(false)
    }
  }

  if (families.loading) return <FamiliesSkeleton />
  if (isAccessDenied(families.error)) {
    return (
      <div className="wb-page">
        <AccessDenied />
      </div>
    )
  }
  if (families.error) {
    return (
      <div className="wb-page">
        <ErrorState
          title="Couldn’t load families"
          description={families.error.message}
          onRetry={families.refetch}
        />
      </div>
    )
  }

  const list = families.data ?? []

  return (
    <div className="wb-page">
      <div className="wb-page-header">
        <div>
          <h1 className="wb-page-title">Families</h1>
          <p className="wb-page-subtitle">
            {list.length} {list.length === 1 ? 'family' : 'families'} on this server.
          </p>
        </div>
        <div className="wb-row">
          <Button variant="secondary" size="sm" onClick={families.refetch}>
            Refresh
          </Button>
          <Button size="sm" onClick={() => setCreating((c) => !c)}>
            New family
          </Button>
        </div>
      </div>

      {creating && (
        <Card className="wb-new-family">
          <div className="wb-row">
            <input
              className="wb-input"
              placeholder="Family name"
              value={newName}
              autoFocus
              onChange={(e) => setNewName(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') submitNew()
              }}
            />
            <Button size="sm" loading={busy} onClick={submitNew}>
              Create
            </Button>
            <Button variant="ghost" size="sm" onClick={() => setCreating(false)}>
              Cancel
            </Button>
          </div>
          {error && <p className="wb-error-text">{error}</p>}
        </Card>
      )}

      {list.length === 0 ? (
        <Card>
          <EmptyState
            title="No families yet"
            description="Create a family, then generate an invite code so people can join it."
            icon={<FamiliesIcon />}
            action={
              <Button size="sm" onClick={() => setCreating(true)}>
                New family
              </Button>
            }
          />
        </Card>
      ) : (
        <div className="wb-groups-list">
          {list.map((f) => (
            <FamilyRow key={f.id} family={f} families={list} onChanged={families.refetch} />
          ))}
        </div>
      )}
    </div>
  )
}

function FamilyRow({
  family,
  families,
  onChanged,
}: {
  family: Family
  families: Family[]
  onChanged: () => void
}) {
  const [open, setOpen] = React.useState(false)
  const members = useAsync(
    () => (open ? listFamilyMembers(family.id) : Promise.resolve([] as Member[])),
    [family.id, open],
  )
  const invites = useAsync(
    () => (open ? listInvites() : Promise.resolve([] as AdminInvite[])),
    [open],
  )

  const [renaming, setRenaming] = React.useState(false)
  const [renameValue, setRenameValue] = React.useState(family.name)
  const [inviteCode, setInviteCode] = React.useState<string | null>(null)
  const [actionError, setActionError] = React.useState<string | null>(null)
  const [busy, setBusy] = React.useState(false)

  const familyInvites = (invites.data ?? []).filter((i) => i.family_id === family.id)
  const otherFamilies = families.filter((f) => f.id !== family.id)

  const doRename = async () => {
    const name = renameValue.trim()
    if (!name || name === family.name) {
      setRenaming(false)
      return
    }
    setBusy(true)
    setActionError(null)
    try {
      await renameFamily(family.id, name)
      setRenaming(false)
      onChanged()
    } catch (e) {
      setActionError(e instanceof Error ? e.message : 'Failed to rename')
    } finally {
      setBusy(false)
    }
  }

  const doDelete = async () => {
    if (!window.confirm(`Delete family “${family.name}”? Its members will become unassigned.`)) return
    setBusy(true)
    setActionError(null)
    try {
      await deleteFamily(family.id)
      onChanged()
    } catch (e) {
      setActionError(e instanceof Error ? e.message : 'Failed to delete')
    } finally {
      setBusy(false)
    }
  }

  const doInvite = async () => {
    setBusy(true)
    setActionError(null)
    try {
      const inv = await createInvite(family.id)
      setInviteCode(inv.code)
      invites.refetch()
    } catch (e) {
      setActionError(e instanceof Error ? e.message : 'Failed to create invite')
    } finally {
      setBusy(false)
    }
  }

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
          <span className="wb-group-sub">Created {formatDate(family.created_at)}</span>
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

      {open && (
        <div className="wb-group-body">
          <div className="wb-group-actions">
            <Button size="sm" variant="secondary" loading={busy} onClick={doInvite}>
              Invite code
            </Button>
            <Button size="sm" variant="ghost" onClick={() => setRenaming((r) => !r)}>
              Rename
            </Button>
            <Button size="sm" variant="danger" onClick={doDelete}>
              Delete
            </Button>
          </div>

          {actionError && <p className="wb-error-text wb-group-action-error">{actionError}</p>}

          {renaming && (
            <div className="wb-group-rename">
              <input
                className="wb-input"
                value={renameValue}
                autoFocus
                onChange={(e) => setRenameValue(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === 'Enter') doRename()
                  if (e.key === 'Escape') setRenaming(false)
                }}
              />
              <Button size="sm" loading={busy} onClick={doRename}>
                Save
              </Button>
              <Button size="sm" variant="ghost" onClick={() => setRenaming(false)}>
                Cancel
              </Button>
            </div>
          )}

          {inviteCode && (
            <div className="wb-invite-banner">
              <span className="wb-invite-label">Invite code</span>
              <span className="wb-invite-code">{inviteCode}</span>
              <CopyButton value={inviteCode} label="Copy invite code" />
              <span className="wb-invite-hint">Share this code; it expires in 7 days.</span>
            </div>
          )}

          {familyInvites.length > 0 && (
            <div className="wb-invite-list">
              <div className="wb-invite-list-title">Active invite codes</div>
              {familyInvites.map((i) => (
                <div key={i.id} className="wb-invite-row">
                  <span className="wb-invite-code">{i.code}</span>
                  <span className="wb-invite-meta">
                    {i.uses}/{i.max_uses} used · {i.role} · expires {formatDate(i.expires_at)}
                  </span>
                  <CopyButton value={i.code} label="Copy invite code" />
                </div>
              ))}
            </div>
          )}

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
              description="Generate an invite code above so someone can join this family."
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
                    <th>Move to family</th>
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
                      <td>
                        <MoveMember
                          member={m}
                          families={otherFamilies}
                          onMoved={() => {
                            members.refetch()
                            onChanged()
                          }}
                        />
                      </td>
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

function MoveMember({
  member,
  families,
  onMoved,
}: {
  member: Member
  families: Family[]
  onMoved: () => void
}) {
  const [target, setTarget] = React.useState('')
  const [busy, setBusy] = React.useState(false)
  const [error, setError] = React.useState<string | null>(null)

  if (families.length === 0) {
    return <span className="wb-muted">No other families</span>
  }

  const doMove = async () => {
    if (!target) return
    setBusy(true)
    setError(null)
    try {
      await moveMember(member.id, target)
      setTarget('')
      onMoved()
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Failed to move')
    } finally {
      setBusy(false)
    }
  }

  return (
    <div className="wb-move">
      <select
        className="wb-select wb-move-select"
        value={target}
        onChange={(e) => setTarget(e.target.value)}
        aria-label={`Move ${member.name} to family`}
      >
        <option value="">Choose…</option>
        {families.map((f) => (
          <option key={f.id} value={f.id}>
            {f.name}
          </option>
        ))}
      </select>
      <Button size="sm" variant="secondary" disabled={!target} loading={busy} onClick={doMove}>
        Move
      </Button>
      {error && <span className="wb-error-text">{error}</span>}
    </div>
  )
}

function RoleBadge({ role }: { role: Role }) {
  const tone = role === 'admin' ? 'pink' : role === 'member' ? 'purple' : 'grey'
  const label = role.charAt(0).toUpperCase() + role.slice(1)
  return <Badge tone={tone}>{label}</Badge>
}

function BatteryPct({ pct }: { pct: number | null }) {
  const text = formatBattery(pct)
  if (pct === null) return <span className="wb-muted">{text}</span>
  const tone = pct <= 15 ? 'red' : pct <= 30 ? 'orange' : 'green'
  return <Badge tone={tone} dot>{text}</Badge>
}

function FamiliesSkeleton() {
  return (
    <div className="wb-page">
      <div className="wb-page-header">
        <div>
          <h1 className="wb-page-title">Families</h1>
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

function FamiliesIcon() {
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
