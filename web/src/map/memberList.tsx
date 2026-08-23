// Member list panel — the side panel listing every member with name, status,
// last-seen, battery, and speed. Clicking a row centers the map on that member.
// Mirrors app/lib/widgets/member_list_sheet.dart (rows, status chips, address).

import { useMemo, useState } from "react";
import {
  BatteryGlyph,
  ClockGlyph,
  MovementGlyph,
  StatusAvatar,
  statusLabel,
} from "./memberBubble";
import { isSpeeding, lastSeenLabel } from "./status";
import type { Member } from "./types";
import { EmptyState } from "../components/primitives";

export interface MemberListProps {
  members: Member[];
  selectedId: string | null;
  onSelect: (member: Member) => void;
  /** Whether the panel is currently collapsed (controlled by the parent). */
  collapsed: boolean;
  onToggleCollapsed: () => void;
  /** Heading shown above the list (e.g. the active group name + count). */
  title: string;
  /** Reference "now" (epoch ms) used for last-seen labels; advances on a timer. */
  nowMs: number;
}

export function MemberList({
  members,
  selectedId,
  onSelect,
  collapsed,
  onToggleCollapsed,
  title,
  nowMs,
}: MemberListProps): JSX.Element {
  const [query, setQuery] = useState("");

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase();
    if (!q) return members;
    return members.filter(
      (m) =>
        m.name.toLowerCase().includes(q) ||
        m.familyName.toLowerCase().includes(q),
    );
  }, [members, query]);

  if (collapsed) {
    return (
      <button
        type="button"
        className="wb-panel-open"
        onClick={onToggleCollapsed}
        title="Show member list"
        aria-label="Show member list"
      >
        <ListIcon />
      </button>
    );
  }

  return (
    <aside className="wb-panel" aria-label="Members">
      <div className="wb-panel-head">
        <span className="wb-panel-title">{title}</span>
        <button
          type="button"
          className="wb-panel-toggle"
          onClick={onToggleCollapsed}
          title="Hide member list"
          aria-label="Hide member list"
        >
          <ChevronIcon dir="right" />
        </button>
      </div>
      <label className="wb-panel-search">
        <SearchIcon />
        <input
          type="search"
          placeholder="Search members"
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          aria-label="Search members"
        />
      </label>
      <div className="wb-panel-list">
        {filtered.length === 0 ? (
          <EmptyState
            title={members.length === 0 ? "No members yet" : "No matches"}
            description={
              members.length === 0
                ? "Members will appear here once they share a location."
                : "No members match your search."
            }
          />
        ) : (
          filtered.map((m) => (
            <button
              type="button"
              key={m.id}
              className="wb-member-row"
              data-selected={selectedId === m.id ? "true" : "false"}
              onClick={() => onSelect(m)}
            >
              <StatusAvatar member={m} size={44} />
              <span className="wb-member-row-info">
                <span className="wb-member-row-name">
                  <span>{m.name}</span>
                </span>
                <span className="wb-member-row-group">{m.familyName}</span>
                <span className="wb-member-row-status" data-status={m.status}>
                  <span className="wb-member-row-status-dot" />
                  {statusLabel(m.status)}
                </span>
                <span className="wb-member-row-meta">
                  {m.batteryPercent > 0 ? (
                    <span
                      className={`wb-chip ${
                        m.batteryPercent <= 20
                          ? "wb-chip-battery-low"
                          : m.batteryPercent <= 50
                            ? "wb-chip-battery-mid"
                            : "wb-chip-battery-ok"
                      }`}
                    >
                      <BatteryGlyph pct={m.batteryPercent} />
                      {m.batteryPercent}%
                    </span>
                  ) : m.status === "stopped" ? (
                    <span className="wb-chip wb-chip-offline">
                      Offline
                    </span>
                  ) : null}
                  {m.movement === "car" && m.speedMph != null ? (
                    <span
                      className={`wb-chip ${isSpeeding(m.movement, m.speedMph) ? "wb-chip-speeding" : "wb-chip-car"}`}
                    >
                      <MovementGlyph movement="car" size={12} />
                      {m.speedMph} mph
                    </span>
                  ) : null}
                  <span className="wb-chip wb-chip-meta">
                    <ClockGlyph size={12} />
                    {lastSeenLabel(m, nowMs)}
                  </span>
                </span>
                <span className="wb-member-row-addr">
                  <PinIcon />
                  {m.position == null ? "No location yet" : m.address}
                </span>
              </span>
              {m.movement !== "none" ? (
                <span className="wb-member-row-mover" style={{ color: "var(--accent-ink)" }}>
                  <MovementGlyph movement={m.movement} size={20} />
                </span>
              ) : null}
            </button>
          ))
        )}
      </div>
    </aside>
  );
}

/* --- small inline icons --- */

function ListIcon(): JSX.Element {
  return (
    <svg viewBox="0 0 24 24" width="18" height="18" fill="currentColor" aria-hidden="true">
      <path d="M4 6h16v2H4V6zm0 5h16v2H4v-2zm0 5h10v2H4v-2z" />
    </svg>
  );
}
function SearchIcon(): JSX.Element {
  return (
    <svg viewBox="0 0 24 24" width="15" height="15" fill="var(--text-faint)" aria-hidden="true">
      <path d="M10 2a8 8 0 1 0 5.3 14l4.7 4.7 1.4-1.4-4.7-4.7A8 8 0 0 0 10 2zm0 2a6 6 0 1 1 0 12 6 6 0 0 1 0-12z" />
    </svg>
  );
}
function PinIcon(): JSX.Element {
  return (
    <svg viewBox="0 0 24 24" width="12" height="12" fill="var(--text-faint)" aria-hidden="true">
      <path d="M12 2a7 7 0 0 0-7 7c0 5 7 13 7 13s7-8 7-13a7 7 0 0 0-7-7zm0 9.5A2.5 2.5 0 1 1 12 6.5a2.5 2.5 0 0 1 0 5z" />
    </svg>
  );
}
function ChevronIcon({ dir }: { dir: "right" | "left" }): JSX.Element {
  const d = dir === "right" ? "M9 6l6 6-6 6" : "M15 6l-6 6 6 6";
  return (
    <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d={d} />
    </svg>
  );
}