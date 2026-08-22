// Place pins — saved locations (Home/School/Work/…) drawn on the map as
// first-class pins with a type glyph and a name label. Each place is tagged
// with its owning family so the platform-admin map can show places across
// families.

import L from "leaflet";
import type { Place } from "./types";

/** Distinct accent per place type (falls back to grey for "other"/unknown).
 *  Reuses the shared --status-* / brand tokens so place pins match the rest of
 *  the map instead of introducing ad-hoc hexes. */
const PLACE_COLORS: Record<string, string> = {
  home: "var(--status-green)",
  school: "var(--status-orange)",
  work: "var(--purple)",
  gym: "var(--status-purple)",
  other: "var(--status-grey)",
};

function placeColor(type: string): string {
  return PLACE_COLORS[type.toLowerCase()] ?? PLACE_COLORS.other!;
}

/** Simple 24×24 stroke glyph per place type (house / cap / briefcase / pin). */
function placeGlyph(type: string): string {
  switch (type.toLowerCase()) {
    case "home":
      return '<path d="M3 11.5 12 4l9 7.5" /><path d="M5.5 10v9h13v-9" />';
    case "school":
      return '<path d="M12 4 2 9l10 5 10-5-10-5Z" /><path d="M6 11.5V16c0 1.5 2.7 3 6 3s6-1.5 6-3v-4.5" /><path d="M22 9v5" />';
    case "work":
      return '<rect x="3" y="8" width="18" height="12" rx="2" /><path d="M9 8V6a2 2 0 0 1 2-2h2a2 2 0 0 1 2 2v2" /><path d="M3 13h18" />';
    case "gym":
      return '<path d="M7 10v4M17 10v4M5 8h2v8H5zM17 8h2v8h-2zM7 11h10" />';
    default:
      return '<path d="M12 21s-7-5.5-7-11a7 7 0 0 1 14 0c0 5.5-7 11-7 11Z" /><circle cx="12" cy="10" r="2.5" />';
  }
}

function esc(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

/** Leaflet divIcon for a saved place: a colored glyph badge + name label. */
export function placeBubbleIcon(place: Place): L.DivIcon {
  const color = placeColor(place.type);
  const glyph = placeGlyph(place.type);
  const label = esc(place.name);
  return L.divIcon({
    className: "wb-marker",
    html: `<div class="wb-place" title="${esc(place.name)}">
      <span class="wb-place-badge" style="--place-color:${color}">
        <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${glyph}</svg>
      </span>
      <span class="wb-place-label">${label}</span>
    </div>`,
    iconSize: [80, 40],
    iconAnchor: [40, 20],
    tooltipAnchor: [0, -20],
  });
}
