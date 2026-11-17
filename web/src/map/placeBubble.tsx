// Place pins — saved locations (Home/School/Work/…) drawn on the map as
// first-class pins with a type glyph and a name label. Each place is tagged
// with its owning family so the platform-admin map can show places across
// families.

import L from "leaflet";
import type { Place } from "./types";

/** Badge fill and glyph color per place type (falls back to grey for
 *  "other"/unknown). Reuses the shared --status-* / brand tokens so place pins
 *  match the rest of the map. The glyph uses dark ink on bright fills (white
 *  on lime or orange would fail contrast) and white on the darker blue/red. */
const PLACE_STYLES: Record<string, { color: string; ink: string }> = {
  home: { color: "var(--status-green)", ink: "var(--on-accent)" },
  school: { color: "var(--status-orange)", ink: "var(--on-accent)" },
  work: { color: "var(--purple)", ink: "var(--on-accent)" },
  gym: { color: "var(--status-purple)", ink: "var(--on-accent)" },
  family: { color: "var(--sky)", ink: "#fff" },
  friend: { color: "var(--status-purple)", ink: "var(--on-accent)" },
  store: { color: "var(--status-orange)", ink: "var(--on-accent)" },
  health: { color: "var(--status-red)", ink: "#fff" },
  park: { color: "var(--status-green)", ink: "var(--on-accent)" },
  food: { color: "var(--status-orange)", ink: "var(--on-accent)" },
  worship: { color: "var(--sky)", ink: "#fff" },
  other: { color: "var(--status-grey)", ink: "var(--on-accent)" },
};

function placeStyle(type: string): { color: string; ink: string } {
  return PLACE_STYLES[type.toLowerCase()] ?? PLACE_STYLES.other!;
}

/** Simple 24×24 stroke glyph per place type. */
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
    case "family":
      return '<circle cx="8" cy="8" r="3" /><circle cx="17" cy="9.5" r="2.5" /><path d="M2.5 20v-1.5a5.5 5.5 0 0 1 11 0V20" /><path d="M15 15.5a4.5 4.5 0 0 1 6.5 4V20" />';
    case "friend":
      return '<path d="M12 20s-7-4.4-7-10a4 4 0 0 1 7-2.6A4 4 0 0 1 19 10c0 5.6-7 10-7 10Z" />';
    case "store":
      return '<path d="M4 9l1.5-5h13L20 9" /><path d="M4 9a2.7 2.7 0 0 0 5.3 0 2.7 2.7 0 0 0 5.4 0A2.7 2.7 0 0 0 20 9" /><path d="M5 12v8h14v-8" />';
    case "health":
      return '<path d="M9 4h6v5h5v6h-5v5H9v-5H4V9h5V4Z" />';
    case "park":
      return '<path d="M12 21v-5" /><path d="M12 3 6 11h3l-3 5h12l-3-5h3L12 3Z" />';
    case "food":
      return '<path d="M7 3v8M4.5 3v5a2.5 2.5 0 0 0 5 0V3M7 11v10" /><path d="M17 3c-2 2-2.5 5-2.5 8h2.5v10" />';
    case "worship":
      return '<path d="M12 3v4" /><path d="M10.5 5h3" /><path d="M6 21v-9l6-5 6 5v9" /><path d="M10 21v-4h4v4" />';
    default:
      return '<path d="M12 21s-7-5.5-7-11a7 7 0 0 1 14 0c0 5.5-7 11-7 11Z" /><circle cx="12" cy="10" r="2.5" />';
  }
}

function esc(s: string): string {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

/** Leaflet divIcon for a saved place: a colored glyph badge + name label. */
export function placeBubbleIcon(place: Place): L.DivIcon {
  const { color, ink } = placeStyle(place.type);
  const glyph = placeGlyph(place.type);
  const label = esc(place.name);
  return L.divIcon({
    className: "wb-marker",
    html: `<div class="wb-place" title="${esc(place.name)}">
      <span class="wb-place-badge" style="--place-color:${color};--place-ink:${ink}">
        <svg viewBox="0 0 24 24" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${glyph}</svg>
      </span>
      <span class="wb-place-label">${label}</span>
    </div>`,
    iconSize: [80, 40],
    iconAnchor: [40, 20],
    tooltipAnchor: [0, -20],
  });
}
