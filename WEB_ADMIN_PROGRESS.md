# Whereabouts — Web Admin Panel (Gauntlet Loop Progress)

**Branch:** `web-admin-panel`

**Bar:** Life360's live web map (life360.com) for the map + Vercel's dashboard for
the admin panel, screenshotted at desktop viewport.

**Goal:** a polished web admin panel where an admin can download/generate the
Android APK and view a live map of all groups (families) and their members'
locations, mirroring the app's map in the browser.

## Pieces

| Piece | Status | Rounds | Winner |
|---|---|---|---|
| Bar inventory (Life360 web map + Vercel dashboard) | ✅ complete | — | — |
| Backend: platform-admin API + live WS stream + places | ✅ built (build+vet+test clean) | — | — |
| Web admin panel shell | ✅ ours wins (r7, narrowly) | 7 | ours |
| Web live map | ✅ ours wins (r7) | 7 | ours |
| APK download/generate flow | ✅ built (BuildsPage + backend) | — | — |
| Integration (MapArea static import + token + admin WS) | ✅ done | — | — |
| Polish pass | ✅ done (token discipline, places, clean bubbles) | — | — |

## Log

- **Round 1** — gathered the bar (`docs/bar-inventory.md`): Vercel's public Geist design
  system (color roles, type scale, elevation, empty/loading states) + Life360's App Store
  map screenshots (member bubbles with per-member color rings, map-first layout, status
  indicators, circle switcher). Scaffolded the `web/` Vite+React+TS+Leaflet app with the
  Whereabouts brand tokens. Fanned out 3 builders in parallel: backend platform-admin API,
  admin shell, and live map.
- **Round 2** — all three builders landed clean (backend build+vet+test, web build). Added
  the platform-admin live WS stream (`/api/admin/ws`, all-families fan-out) and the
  `/api/admin/places` endpoint. Integrated the shell + map (static MapView import,
  token-driven self-managed mode, admin WS URL).
- **Round 3 (critic r1)** — both critics judged **the bar still wins**. Shell gaps: no
  Search/⌘K command menu, no color role ladder, off-scale font sizes, radii not keyed to
  elevation, no copy buttons, mono not used by role, no dashboard empty state, no
  middle-truncate, active-nav indistinguishable from hover. Map gaps: no per-member color
  identity, status buried in list, cluster hides movement, wrong cluster iconSize,
  teleporting markers, opaque member panel, no places, 20s staleness tick, emoji icons +
  reload hack.
- **Round 4 (fix r1)** — builders applied partial fixes (shell: color role ladder, font
  scale, 6px radius, mono, copy button, middle-truncate; map: memberList). Lead agent then
  applied the biggest gaps directly: per-member color identity (ring = member color, status
  demoted to a dot), 5s staleness tick, SVG state icons, in-place retry, cluster iconSize
  fix, marker position transition, translucent member panel, ⌘K command menu, dashboard
  empty state. Web build clean (106 modules). Re-critics dispatched.
- **Round 5 (critic r2)** — both critics still judged **the bar still wins**, but the gaps
  narrowed to polish. Shell: type scale defined but not enforced (hardcoded off-scale font
  sizes), command menu had no keyboard nav, hover role identical to neutral surface, radii
  off the 6/12/16 scale, CopyButton/Mono dead code, login hardcoded error colors. Map:
  battery/last-seen never on the bubble, no member detail card on tap, two-tap group
  switcher, no live pulse, walking/stationary invisible, member palette reused group hexes.
- **Round 6 (fix r2)** — lead agent applied all of the above directly: enforced the type
  scale (all hardcoded sizes → `var(--font-*)`), distinct hover/active roles, 6/12/16 radii
  only, keyboard-driven ⌘K menu (↑/↓/Enter + active highlight + spinner), CopyButton wired
  into Settings + Builds, login error colors → tokens, member detail card on tap (battery +
  last-seen + activity + place), one-tap chip-row group switcher (≤6 groups), pulsing LIVE
  badge, walking/running activity glyphs, distinct member palette, cluster iconSize +2px.
  Web build clean (107 modules). Re-critics dispatched.
- **Round 7 (critic r3)** — still "bar wins", gaps narrowed further. Shell: hover/active
  ladder only on 3 of ~9 surfaces, fake hardcoded "Live" badge, dead Mono component, map.css
  off-scale type. Map: bubbles teleport (no position tween), status dot redundant vs ring,
  addressFrom mislabels stationary as "Moving", empty state never fires with groups-but-no-
  members.
- **Round 8 (fix r3)** — lead agent applied: JS position tween (AnimatedMarker, animates
  only live changes not pan/zoom), "Stationary" label, empty state gated on map mount,
  hover/active ladder on all surfaces, removed fake Live badge, wired Mono component,
  tokenized map.css type. Re-critics dispatched.
- **Round 9 (critic r4)** — still "bar wins". Map: ring=identity/status=dot inverted the
  live signal (status should be the dominant ring), member colors unstable (sort-index),
  no place layer, empty-state flash, bubble clutter, last-seen inconsistency. Shell: map.css
  hover still `--surface-tint`.
- **Round 10 (fix r4)** — lead agent applied: ring=STATUS / face=member-identity swap
  (matches Life360), stable hashed member colors, removed redundant group dot, empty-state
  flash fix, last-seen "5m ago" consistency, map.css hover → `--surface-hover`. Web build
  clean (108 modules). Re-critics dispatched.
- **Round 11 (critic r5)** — shell: duplicate `<h1>` (TopBar + page), map.css off-scale
  radii/fonts, `.wb-spinner`/`.wb-row` class collisions, command-menu edge cases. Map:
  ring=status inverted the bar's "per-member color rings", photo avatars erase identity,
  status double-encoded, icon churn every 5s.
- **Round 12 (fix r5)** — lead agent applied: ring=IDENTITY / face=white+member-color
  initials / status=dot (settled per the bar's literal "per-member color rings"), TopBar
  `<h1>`→`<span>`, radii→6/12/16, fonts tokenized, `.wb-spinner`→`.wb-map-spinner`,
  `.wb-row`→`.wb-member-row`, command-menu Escape-clears-query + ArrowDown guard, removed
  battery/last-seen chip (clean 50×50 circle, fixes icon churn), removed dead `.wb-group-dot`.
- **Round 13 (critic r6)** — shell: map bypasses token system (inline ad-hoc colors, raw
  hexes, off-scale radii/fonts, `.wb-switcher-btn` 16px radius). Map: **Places entirely
  absent** (bar checklist #4) + "Place" row mislabels activity text; bubble chip a craft
  regression; status dot low-contrast.
- **Round 14 (fix r6)** — lead agent applied: **built the place layer** (`placeBubble.tsx`:
  Home/School/Work pins with type glyphs + name labels, fetched from `/api/admin/places`),
  "Place"→"Activity"→"Status" relabel, removed bubble chip, tokenized all inline ad-hoc
  colors (semantic `.wb-chip-*` classes, `--status-*` fg/bg pairs), status dot 2px white
  halo, collapsed `--surface-tint`→`--surface-soft`, EmptyState primitive in member list.
- **Round 15 (critic r7)** — shell: "bar still wins — narrowly" (hardcoded `rgba()` focus
  ring/live-pulse/spinner, inline status dot, hand-rolled box-shadows, duplicate
  `@keyframes wb-spin`). Map: **"ours beats the bar"** (first win) — with follow-ups: fix
  double "Activity" label, wire place-pin interaction, restore battery/last-seen on map.
- **Round 16 (fix r7)** — lead agent applied: focus ring→`var(--ring)`, live-pulse→
  `color-mix(var(--status-green))`, spinner→`--surface-active`, MovementBadge hexes→tokens,
  inline status dot→`data-status` class, box-shadows→`--shadow-*` ladder, deduped
  `@keyframes wb-spin`, fixed double "Activity"→"Status" label, battery added to bubble
  hover title. Web build clean (109 modules), backend build clean with embedded dist.
- **Round 17 (map critic r7 follow-up)** — map critic re-confirmed **"ours beats the bar"**
  and listed follow-ups. Lead agent applied: place pins now interactive (click → Popup with
  name/family/address/radius), place colors→`--status-*`/brand tokens, empty state no longer
  covers place pins (gated on `visiblePlaces.length === 0`), empty-state text distinguishes
  "no members" vs "no locations reported". Web build clean (109 modules), backend clean.
