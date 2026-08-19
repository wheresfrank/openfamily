// Groups page — list of families with member counts and a "view members"
// action that expands an inline member table for a family.

import React from 'react'
import { listFamilyMembers, listFamilies } from '../lib/api'
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
import type { Family, Member } from '../lib/types'
import './pages.css'

export function GroupsPage() {
  const families = useAsync(listFamilies, [])

  if (families.loading) return <GroupsSkeleton />
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
          title="Couldn’t load groups"
          description={families.error.message}
          onRetry={families.refetch}
        />
      </div>
    )
  }

  const list = families.data ?? []
  if (list.length === 0) {
    return (
      <div className="wb-page">
        <div className="wb-page-header">
          <div>
            <h1 className="wb-page-title">Groups</h1>
            <p className="wb-page-subtitle">Families using this Whereabouts server.</p>
          </div>
        </div>
        <Card>
          <EmptyState
            title="No groups yet"
            description="Families will appear here once members sign up and create a group. Invite people from the mobile app to get started."
            icon={<GroupsIcon />}
          />
        </Card>
      </div>
    )
  }

  return (
    <div className="wb-page">
      <div className="wb-page-header">
        <div>
          <h1 className="wb-page-title">Groups</h1>
          <p className="wb-page-subtitle">
            {list.length} {list.length === 1 ? 'family' : 'families'} on this server.
          </p>
        </div>
        <Button variant="secondary" size="sm" onClick={families.refetch}>
          Refresh
        </Button>
      </div>

      <div className="wb-groups-list">
        {list.map((f) => (
          <FamilyRow key={f.id} family={f} />
        ))}
      </div>
    </div>
  )
}

function FamilyRow({ family }: { family: Family }) {
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

function RoleBadge({ role }: { role: Member['role'] }) {
  const tone = role === 'admin' ? 'pink' : role === 'parent' ? 'purple' : 'grey'
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