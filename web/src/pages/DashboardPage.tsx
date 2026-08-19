// Dashboard / live map page. The map is full-bleed within the content region.
// A slim stat strip sits above it; both fill the available content height.

import React from 'react'
import { listAllMembers, listFamilies } from '../lib/api'
import { useAsync, isAccessDenied } from '../lib/useAsync'
import { MapArea } from '../components/MapArea'
import { AccessDenied, Badge, Card, EmptyState, Spinner } from '../components/primitives'
import './pages.css'
import './DashboardPage.css'

export function DashboardPage() {
  const families = useAsync(listFamilies, [])
  const members = useAsync(listAllMembers, [])

  const totalFamilies = families.data?.length ?? 0
  const totalMembers = members.data?.length ?? 0
  const online = React.useMemo(() => {
    const now = Date.now()
    const list = members.data ?? []
    return list.filter((m) => {
      if (!m.ts) return false
      const age = now - new Date(m.ts).getTime()
      return age < 5 * 60 * 1000
    }).length
  }, [members.data])

  if (isAccessDenied(families.error) || isAccessDenied(members.error)) {
    return (
      <div className="wb-page">
        <AccessDenied />
      </div>
    )
  }

  const loading = families.loading || members.loading
  const empty = !loading && totalFamilies === 0 && totalMembers === 0

  return (
    <div className="wb-dashboard">
      <div className="wb-dashboard-strip">
        <div className="wb-dashboard-stats">
          <StatCard label="Families" value={loading ? null : totalFamilies} />
          <StatCard label="Members" value={loading ? null : totalMembers} />
          <StatCard
            label="Live now"
            value={loading ? null : online}
            hint={loading ? undefined : 'Updated in the last 5 minutes'}
            accent="green"
          />
        </div>
        <div className="wb-dashboard-status">
          {loading ? (
            <span className="wb-dashboard-status-loading">
              <Spinner size={14} /> Loading…
            </span>
          ) : families.error || members.error ? (
            <Badge tone="red" dot>
              Connection error
            </Badge>
          ) : (
            <Badge tone="green" dot>
              Streaming
            </Badge>
          )}
        </div>
      </div>

      <div className="wb-dashboard-map">
        <Card padded={false} className="wb-dashboard-mapcard">
          {empty ? (
            <EmptyState
              title="No groups yet"
              description="Create a family circle in the app and its members will appear here on the live map."
            />
          ) : (
            <MapArea />
          )}
        </Card>
      </div>
    </div>
  )
}

interface StatCardProps {
  label: string
  value: number | null
  hint?: string
  accent?: 'green' | 'purple'
}

function StatCard({ label, value, hint, accent }: StatCardProps) {
  const valueClass = accent === 'green' ? ' wb-stat-value-green' : accent === 'purple' ? ' wb-stat-value-purple' : ''
  return (
    <Card className="wb-dashboard-stat">
      <div className="wb-stat-label">{label}</div>
      <div className={`wb-stat-value${valueClass}`}>
        {value === null ? <span className="wb-stat-skeleton" /> : value}
      </div>
      {hint && <div className="wb-stat-hint">{hint}</div>}
    </Card>
  )
}