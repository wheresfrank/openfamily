// Member detail card — the tap-to-open surface that answers "who, where, how's
// their battery, how fresh is this" without hunting the list.

import { BatteryGlyph, MovementBadge, StatusAvatar, statusColor, statusLabel } from './memberBubble'
import { lastSeenLabel } from './status'
import type { Member } from './types'

interface MemberCardProps {
  member: Member
  nowMs: number
  onClose: () => void
  onRequestLocation?: () => void
  locationRequestStatus?: string | null
  requestingLocation?: boolean
}

export function MemberCard({
  member,
  nowMs,
  onClose,
  onRequestLocation,
  locationRequestStatus,
  requestingLocation = false,
}: MemberCardProps) {
  return (
    <div className="wb-member-card" role="dialog" aria-label={`${member.name} details`}>
      <button
        type="button"
        className="wb-member-card-close"
        onClick={onClose}
        aria-label="Close member details"
      >
        <svg width="14" height="14" viewBox="0 0 24 24" fill="none" aria-hidden="true">
          <path d="M6 6l12 12M18 6 6 18" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
        </svg>
      </button>

      <div className="wb-member-card-head">
        <StatusAvatar member={member} size={48} />
        <div className="wb-member-card-id">
          <div className="wb-member-card-name">{member.name}</div>
          <div className="wb-member-card-family">{member.familyName}</div>
        </div>
      </div>

      <div className="wb-member-card-status" data-status={member.status}>
        <span
          className="wb-member-card-status-dot"
          style={{ background: statusColor(member.status) }}
        />
        {statusLabel(member.status)}
      </div>

      <div className="wb-member-card-rows">
        <div className="wb-member-card-row">
          <span className="wb-member-card-k">Battery</span>
          <span className="wb-member-card-v">
            {member.batteryPercent > 0 ? (
              <>
                <BatteryGlyph pct={member.batteryPercent} />
                <span>{member.batteryPercent}%</span>
              </>
            ) : (
              <span>—</span>
            )}
          </span>
        </div>
        <div className="wb-member-card-row">
          <span className="wb-member-card-k">Last seen</span>
          <span className="wb-member-card-v">{lastSeenLabel(member, nowMs)}</span>
        </div>
        {member.movement !== 'none' && (
          <div className="wb-member-card-row">
            <span className="wb-member-card-k">Activity</span>
            <span className="wb-member-card-v">
              <MovementBadge member={member} />
            </span>
          </div>
        )}
        {member.address && (
          <div className="wb-member-card-row">
            <span className="wb-member-card-k">Status</span>
            <span className="wb-member-card-v">{member.address}</span>
          </div>
        )}
      </div>

      {onRequestLocation && (
        <>
          <button
            type="button"
            className="wb-member-card-refresh"
            onClick={onRequestLocation}
            disabled={requestingLocation}
          >
            {requestingLocation ? "Requesting…" : "Update location"}
          </button>
          {locationRequestStatus && (
            <div className="wb-member-card-refresh-status" role="status">
              {locationRequestStatus}
            </div>
          )}
        </>
      )}

      <a
        className="wb-member-card-history"
        href={`#/history?member=${encodeURIComponent(member.id)}`}
      >
        View history
      </a>
    </div>
  )
}
