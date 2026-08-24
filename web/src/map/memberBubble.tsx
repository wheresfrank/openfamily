// Member avatar bubble + movement badges, and Leaflet divIcon builders for the
// map. Mirrors app/lib/widgets/member_avatar_bubble.dart:
//   - a circular avatar (photo or initials on the group accent) at full size,
//   - a colored status RING drawn around it (never a fill behind it),
//   - a small circular movement glyph on the ring (icon only — never a card
//     covering the face),
//   - driving speed as a caption hanging *below* the pin, like a place label,
//   - a red "!" error badge top-right for the location-error state.
//
// On the map these render as Leaflet `divIcon`s (HTML). In the member list they
// render as a real React `StatusAvatar` so rows stay interactive and crisp.

import L from "leaflet";
import type { CSSProperties } from "react";
import { initials, isSpeeding, showsDrivingSpeed } from "./status";
import type { Member, MemberStatus, MovementType } from "./types";

/** Status → brand token color (mirrors AppColors / styles.css tokens). */
export function statusColor(status: MemberStatus): string {
  switch (status) {
    case "normal":
      return "var(--status-green)";
    case "warning":
      return "var(--status-orange)";
    case "gpsIssue":
      return "var(--status-purple)";
    case "stopped":
      return "var(--status-grey)";
    case "error":
      return "var(--status-red)";
  }
}

/** Short human-readable status label for the list row. */
export function statusLabel(status: MemberStatus): string {
  switch (status) {
    case "normal":
      return "Live";
    case "warning":
      return "Low battery";
    case "gpsIssue":
      return "GPS issue";
    case "stopped":
      return "Updates stopped";
    case "error":
      return "Location error";
  }
}

/* ------------------------------------------------------------------ icons */

/** Inline SVG movement icons (car / bike). "none" renders nothing. */
export function MovementGlyph({
  movement,
  size = 13,
}: {
  movement: MovementType;
  size?: number;
}): JSX.Element | null {
  if (movement === "none") return null;
  const s = { width: size, height: size };
  if (movement === "car") {
    return (
      <svg viewBox="0 0 24 24" style={s} fill="currentColor" aria-hidden="true">
        <path d="M5 11l1.5-4.5A2 2 0 0 1 8.4 5h7.2a2 2 0 0 1 1.9 1.5L19 11v6h-2v1.5a1.5 1.5 0 0 1-3 0V17H10v1.5a1.5 1.5 0 0 1-3 0V17H5v-6zm2.4-1h9.2l-.9-2.7H8.3L7.4 10zM7.5 13a1 1 0 1 0 0-2 1 1 0 0 0 0 2zm9 0a1 1 0 1 0 0-2 1 1 0 0 0 0 2z" />
      </svg>
    );
  }
  if (movement === "bike") {
    return (
      <svg viewBox="0 0 24 24" style={s} fill="currentColor" aria-hidden="true">
        <path d="M5 20a4 4 0 1 1 .7-7.94l1.5-3.06H6V7h4.2l.6 1.2 1.7-.55.6 1.85-1.7.55.4.83A4 4 0 0 1 15 12l.6 1.2A4.5 4.5 0 1 1 12 16h-1.1l1.1-2.25.4.83A3 3 0 0 0 16.5 13l-1-2.05 1.7-.55-.6-1.85-3.4 1.1-.9-1.8H7.7l-.7 1.45L9 13.5 7.9 15.7A4 4 0 0 1 5 20zm0-2a2 2 0 1 0 0-4 2 2 0 0 0 0 4zm12 0a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5z" />
      </svg>
    );
  }
  if (movement === "walking" || movement === "running") {
    return (
      <svg viewBox="0 0 24 24" style={s} fill="currentColor" aria-hidden="true">
        <path d="M13.5 5.5c1.1 0 2-.9 2-2s-.9-2-2-2-2 .9-2 2 .9 2 2 2zM9.8 8.9 7 23h2.1l1.8-8 2.1 2v6h2v-7.5l-2.1-2 .6-3C14.8 12 16.8 13 19 13v-2c-1.9 0-3.5-1-4.3-2.4l-1-1.6c-.4-.6-1-1-1.7-1-.3 0-.5.1-.8.1L6 8.3V13h2V9.6l1.8-.7z" />
      </svg>
    );
  }
  // Fallback dot for the richer variants (boat/plane/home/…), kept for parity.
  return (
    <svg viewBox="0 0 24 24" style={s} fill="currentColor" aria-hidden="true">
      <circle cx="12" cy="12" r="6" />
    </svg>
  );
}

/** A battery glyph whose fill level reflects the percentage. */
export function BatteryGlyph({
  pct,
  size = 13,
}: {
  pct: number;
  size?: number;
}): JSX.Element {
  const level = Math.max(0, Math.min(100, pct));
  const color =
    level <= 20 ? "var(--status-red)" : level <= 50 ? "var(--status-orange)" : "var(--status-green)";
  return (
    <svg viewBox="0 0 24 14" style={{ width: size, height: (size * 14) / 24 }} aria-hidden="true">
      <rect x="1" y="2" width="19" height="10" rx="2" fill="none" stroke={color} strokeWidth="1.6" />
      <rect x="21" y="5" width="2" height="4" rx="1" fill={color} />
      <rect x="3" y="4" width={(15 * level) / 100} height="6" rx="1" fill={color} />
    </svg>
  );
}

/** A tiny walking-person glyph (used for stale/last-seen hint chips). */
function ClockGlyph({ size = 13 }: { size?: number }): JSX.Element {
  return (
    <svg viewBox="0 0 24 24" style={{ width: size, height: size }} fill="currentColor" aria-hidden="true">
      <path d="M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20zm0 18a8 8 0 1 1 0-16 8 8 0 0 1 0 16zm.5-13H11v6l5 3 .8-1.3-4.3-2.5V7z" />
    </svg>
  );
}

export { ClockGlyph };

/* ---------------------------------------------------- React StatusAvatar */

/** Circular avatar with a colored status ring — used in the member list rows. */
export function StatusAvatar({
  member,
  size = 44,
}: {
  member: Member;
  size?: number;
}): JSX.Element {
  const ring = Math.max(2.5, Math.min(4.5, size * 0.08));
  const face = size - ring * 2;
  const faceStyle: CSSProperties = member.avatarUrl
    ? {
        backgroundImage: `url(${member.avatarUrl})`,
        backgroundSize: "cover",
        backgroundPosition: "center",
        backgroundColor: member.memberColor,
      }
    : { backgroundColor: "#fff", color: member.memberColor };
  return (
    <div
      className="wb-avatar"
      style={{
        width: size,
        height: size,
        border: `${ring}px solid ${member.memberColor}`,
        ...faceStyle,
        fontSize: face * 0.4,
      }}
      aria-hidden="true"
    >
      {member.avatarUrl ? null : initials(member.name)}
      <span
        className="wb-status-dot"
        style={{ background: statusColor(member.status) }}
      />
    </div>
  );
}

/** Small movement badge (icon + speed) used in the list row's trailing slot. */
export function MovementBadge({ member }: { member: Member }): JSX.Element | null {
  if (member.movement === "none") return null;
  const speeding = isSpeeding(member.movement, member.speedMph);
  const showSpeed = showsDrivingSpeed(member.movement, member.speedMph);
  return (
    <span
      className={`wb-move${speeding ? " wb-speeding" : ""}`}
      style={{ position: "static" }}
    >
      <MovementGlyph movement={member.movement} size={14} />
      {showSpeed ? <>{member.speedMph} mph</> : null}
    </span>
  );
}

/* ---------------------------------------------------- Leaflet divIcon builders */

/** Pin width — wide enough for a 3-digit speed caption ("128 mph"). */
const PIN_WIDTH = 72;
/** Avatar circle size. Geographic anchor is the center of this circle. */
const BUBBLE_SIZE = 50;
/** Extra height hanging under the avatar for the speed caption. */
const SPEED_CAPTION_H = 28;

function esc(s: string): string {
  return s.replace(/[&<>"']/g, (c) =>
    c === "&" ? "&amp;" : c === "<" ? "&lt;" : c === ">" ? "&gt;" : c === '"' ? "&quot;" : "&#39;",
  );
}

/**
 * Builds the HTML for a single member pin (used by the Leaflet divIcon).
 * Mirrors MemberAvatarBubble: status ring around an initials/photo avatar,
 * a circular movement glyph on the ring (icon only), driving speed as a
 * caption below the pin (never a card covering the face), and an error
 * badge top-right.
 */
function bubbleHtml(member: Member, selected: boolean): string {
  // The ring carries per-member IDENTITY; the face is white with member-color
  // initials (or a photo); STATUS is the small dot. Speed lives *under* the
  // pin so the face stays fully visible.
  const ringColor = member.memberColor;
  const statusDot = `<span class="wb-status-dot" style="background:${statusColor(member.status)}"></span>`;
  const initialsTxt = esc(initials(member.name));
  const faceBg = member.avatarUrl
    ? `background-image:url('${esc(member.avatarUrl)}');background-size:cover;background-position:center;background-color:${member.memberColor};`
    : `background:#fff;color:${member.memberColor};`;
  const speeding = isSpeeding(member.movement, member.speedMph);
  const speedingCls = speeding ? " wb-speeding" : "";
  const glyph =
    member.movement !== "none"
      ? `<span class="wb-move-glyph${speedingCls}" aria-hidden="true">${movementSvg(member.movement)}</span>`
      : "";
  const speed = showsDrivingSpeed(member.movement, member.speedMph)
    ? `<span class="wb-speed${speedingCls}"><span class="wb-speed-n">${member.speedMph}</span><span class="wb-speed-unit">mph</span></span>`
    : "";
  const err = member.status === "error" ? `<span class="wb-err">!</span>` : "";
  return `<div class="wb-pin" title="${esc(bubbleTitle(member))}">
    <div class="wb-bubble" data-selected="${selected ? "true" : "false"}">
      <span class="wb-ring" style="--status-color:${ringColor}"></span>
      <span class="wb-face" style="${faceBg}">${member.avatarUrl ? "" : initialsTxt}</span>
      ${statusDot}${glyph}${err}
    </div>
    ${speed}
  </div>`;
}

/** Builds the HTML for a cluster count bubble (stacked mini avatars + count). */
function clusterHtml(members: Member[]): string {
  const preview = members.slice(0, 3);
  const minis = preview
    .map((m) => {
      const bg = m.avatarUrl
        ? `background-image:url('${esc(m.avatarUrl)}');background-size:cover;background-position:center;background-color:${m.memberColor};`
        : `background:#fff;color:${m.memberColor};`;
      return `<span class="wb-cmini" style="--status-color:${m.memberColor};${bg}">${m.avatarUrl ? "" : esc(initials(m.name))}</span>`;
    })
    .join("");
  return `<div class="wb-cluster" title="${esc(clusterTitle(members))}">${minis}<span class="wb-count">${members.length}</span></div>`;
}

/** Inline SVG for a movement glyph inside a divIcon (string form). */
function movementSvg(movement: MovementType): string {
  if (movement === "car") {
    return `<svg viewBox="0 0 24 24" width="13" height="13" fill="currentColor"><path d="M5 11l1.5-4.5A2 2 0 0 1 8.4 5h7.2a2 2 0 0 1 1.9 1.5L19 11v6h-2v1.5a1.5 1.5 0 0 1-3 0V17H10v1.5a1.5 1.5 0 0 1-3 0V17H5v-6z"/></svg>`;
  }
  if (movement === "bike") {
    return `<svg viewBox="0 0 24 24" width="13" height="13" fill="currentColor"><path d="M5 20a4 4 0 1 1 .7-7.94l1.5-3.06H6V7h4.2l.6 1.2 1.7-.55.6 1.85-1.7.55.4.83A4 4 0 0 1 15 12l.6 1.2A4.5 4.5 0 1 1 12 16h-1.1l1.1-2.25.4.83A3 3 0 0 0 16.5 13l-1-2.05 1.7-.55-.6-1.85-3.4 1.1-.9-1.8H7.7l-.7 1.45L9 13.5 7.9 15.7A4 4 0 0 1 5 20z"/></svg>`;
  }
  if (movement === "walking" || movement === "running") {
    return `<svg viewBox="0 0 24 24" width="13" height="13" fill="currentColor"><path d="M13.5 5.5c1.1 0 2-.9 2-2s-.9-2-2-2-2 .9-2 2 .9 2 2 2zM9.8 8.9 7 23h2.1l1.8-8 2.1 2v6h2v-7.5l-2.1-2 .6-3C14.8 12 16.8 13 19 13v-2c-1.9 0-3.5-1-4.3-2.4l-1-1.6c-.4-.6-1-1-1.7-1-.3 0-.5.1-.8.1L6 8.3V13h2V9.6l1.8-.7z"/></svg>`;
  }
  return "";
}

function bubbleTitle(m: Member): string {
  let t = `${m.name} — ${statusLabel(m.status)}`;
  if (m.batteryPercent > 0) t += ` · ${m.batteryPercent}% battery`;
  if (m.movement !== "none") {
    const activity = isSpeeding(m.movement, m.speedMph)
      ? "Speeding"
      : m.movement === "car"
        ? "Driving"
        : m.movement === "bike"
          ? "Biking"
          : m.movement === "walking"
            ? "Walking"
            : m.movement === "running"
              ? "Running"
              : m.movement;
    t += ` · ${activity}`;
    if (showsDrivingSpeed(m.movement, m.speedMph)) t += ` ${m.speedMph} mph`;
  }
  return t;
}

function clusterTitle(members: Member[]): string {
  let t = `${members.length} people here`;
  for (const m of members.slice(0, 3)) {
    t += ` · ${m.name}: ${statusLabel(m.status)}`;
    if (showsDrivingSpeed(m.movement, m.speedMph)) t += ` ${m.speedMph} mph`;
  }
  return t;
}

/** Leaflet divIcon for a single member bubble. */
export function memberBubbleIcon(member: Member, selected: boolean): L.DivIcon {
  const hasSpeed = showsDrivingSpeed(member.movement, member.speedMph);
  const h = hasSpeed ? BUBBLE_SIZE + SPEED_CAPTION_H : BUBBLE_SIZE + 8;
  return L.divIcon({
    className: "wb-marker",
    html: bubbleHtml(member, selected),
    iconSize: [PIN_WIDTH, h],
    // Keep the geographic point at the avatar center, even when a caption hangs below.
    iconAnchor: [PIN_WIDTH / 2, BUBBLE_SIZE / 2],
    tooltipAnchor: [0, -BUBBLE_SIZE / 2],
  });
}

/** Leaflet divIcon for a cluster count bubble. */
export function clusterBubbleIcon(members: Member[]): L.DivIcon {
  // Stack width: 30px per mini avatar, each subsequent one overlapping by 14px
  // (16px step), plus the count badge (2px margin + ~22px). Matches the Flutter
  // ClusterBubble (stackWidth + 22) plus the badge's leading margin so the count
  // badge and tap anchor sit at the true center.
  const n = Math.min(members.length, 3);
  const stackWidth = 30 + (n - 1) * 16;
  const w = stackWidth + 24;
  return L.divIcon({
    className: "wb-marker",
    html: clusterHtml(members),
    iconSize: [w, 40],
    iconAnchor: [w / 2, 20],
    tooltipAnchor: [0, -20],
  });
}