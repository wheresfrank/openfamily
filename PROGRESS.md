# Whereabouts — Gauntlet Loop Progress

**Bar:** the reference family-tracker app's shipped UI — its map, member list,
places, and SOS screens (from App Store / Play Store listings and marketing pages).

## Pieces

| Piece | Status | Rounds | Winner |
|---|---|---|---|
| Bar inventory (reference app screens) | ✅ complete | — | — |
| Backend API + scaffold | ✅ complete (compiles, vet clean, smoke-tested) | — | — |
| Map screen (+ member list, places, SOS, safety, keys, settings) | ✅ complete (critic picked ours decisively, r11/r13/r14) | 14 | **Ours** |
| Onboarding (sign-up → permissions → circle code → invite) | ✅ complete (critic picked ours decisively, r6/r7) | 7 | **Ours** |
| Geofencing (enter/exit alert engine) | ✅ complete (critic picked ours decisively, r18) | 18 | **Ours** |
| Flutter compile verification (flutter analyze) | ✅ complete — "No issues found!" (8 errors + 24 deprecations fixed) | 1 | — |
| Android APK build | ✅ complete — `app-debug.apk` (154 MB) built successfully | — | — |
| Backend WebSocket fan-out hub | ✅ complete (critic "ours wins" + 5 fixes applied, build+vet clean) | 2 | **Ours** |
| Flutter API client + auth + device registration | ✅ complete (critic 10 gaps → fixed; re-review 9 gaps → fixed; flutter analyze clean) | 3 | **Ours** |
| Flutter map wiring (real `/family/members` + `/ws/stream`) | ✅ complete (critic 14 gaps → 4 blocking fixed; flutter analyze clean) | 2 | **Ours** |
| Flutter places + location reporting wiring | ✅ complete (places: critic "ours wins" r3; location reporting: critic "ours wins" r5) | 5 | **Ours** |
| Background location reporting (`background_locator_2`) | ✅ complete (critic "ours wins" r3) | 3 | **Ours** |
| Deployment polish | ✅ complete (critic "ours wins" r3) | 3 | **Ours** |

## Log

- **Round 1** — gathering the bar (reference app screen inventory) and scaffolding the
  backend + Flutter skeleton in parallel.
- **Rounds 2–15** — builder produced the Go backend incrementally: models,
  config, auth (Argon2id password, JWT, TOTP), db, middleware, handlers
  (auth/device/family/location/ws), `main.go`, and PostGIS/TimescaleDB
  migrations. Now compiling (`go build`). Bar-gatherer still researching
  the reference app's screens. Both subagents still in flight.
- **Foundation done** — backend compiles + vets clean, migrations apply,
  API smoke-tested, Docker stack exercised. Bar inventory persisted.
- **Map screen r1** — builder implemented the map screen; critic judged
  the reference app's better (biggest gap: no bubble clustering). Builder now fixing
  15 concrete gaps.
- **Map screen done (14 rounds)** — critic picked ours decisively (r11/r13/r14).
  Now has: full-bleed map, zoom-aware clustering with tap-to-fan-out, photo
  avatars + status rings, all 5 status colors + 9 movement icons, locked
  member sheet, large SOS + Places/Keys/Safety/Settings, satellite toggle,
  live movement simulation, and real screens for places/keys/settings/safety/
  check-in/help-alert/join-circle. Remaining minor polish (not verdict-flipping):
  `+` FAB placement, bottom-bar crowding, SOS red-at-rest, error ring+badge.
- **Onboarding done (7 rounds)** — critic picked ours decisively (r6/r7). Full
  6-step funnel: welcome (map-first, no premature location prompt) → sign-up
  (phone/email/password/photo, real validation) → permissions (location Always
  + iOS Open-Settings fix, notifications, conditional motion, WHY + skip
  consequences) → create-or-join → invite (Send Code + tap-to-copy) → add
  locations (real map-picker geofence capture with radius + arrive/leave bell,
  Home/Work/School/Gym + custom). Deferred to backend wiring: real sign-up
  HTTP, real join link, self-hosted Nominatim geocoding + OSM tiles.
- **Geofencing done (18 rounds)** — critic picked ours decisively (r18). The
  arrive/leave engine survived 11 critic reviews: first-observation baseline,
  enter/exit detection, 60s debounce with pending-notification model (suppressed
  transitions fire via reconcile, never silently dropped except documented
  rapid-reversal), stale place_id race closed in both processGeofence and
  firePendingNotification, per-device push timeout, permanent-failure
  dead-lettering, platform↔credential validation, ws token moved off the URL +
  origin restriction, TLS enforced in all envs. Build+vet clean.
- **Backend WebSocket fan-out hub done** — `hub.go` (mutex-guarded per-family
  client map, buffered send chan 64, non-blocking broadcast drops slow clients),
  `ws.go` (welcome + members snapshot via LEFT JOIN member_positions,
  email redaction matching ListMembers), `location.go` broadcasts after commit.
  Critic "ours wins" + 5 fixes applied: heartbeat ping (30s ticker, 10s timeout)
  evicts half-open clients, welcome via json.Marshal, email redaction aligned
  with ListMembers, skip DB lookup when hub empty, stale route comment fixed.
  Build+vet clean.
- **Flutter API client + auth + device registration done** — `api_client.dart`
  (single-flight refresh, `SessionExpiredException`, at-most-once
  `onSessionExpired`, `hasValidSession()` JWT-exp check), `device_service.dart`
  (`ensureRegistered()`), real `auth_service.dart` (signUp/login/logout +
  `TotpRequiredException` + `AccountCreatedException`), `token_storage.dart`
  (clear() clears tokens+device id), `_SessionGate` (StatefulWidget, future in
  initState, validates token expiry). Critic 10 gaps → fixed; re-review 9 gaps →
  fixed (re-entrancy redirect made authoritative, README documents
  `--dart-define=WHEREABOUTS_API_URL`, dart:io removed for web, concurrent-401
  guard, refresh-token read inside try, session gate validates expiry, future
  not in build(), single LoginScreen on stack, TOTP reset clears code+error).
  `flutter analyze` clean.
- **Flutter map wiring done** — `family_service.dart` (REST `/family` +
  `/family/members` + `/ws/stream` WebSocket with token-as-subprotocol auth,
  welcome/members/location frames, exponential-backoff reconnect with member
  re-fetch), `member_mapper.dart` (backend JSON → `Member`, status/movement/
  speed/address derivation, `refreshStaleness`), `Member.position` made
  nullable + `lastSeen` added, `MapScreen` rewired (single family, loading/
  error states, "You" relabeling, null-position guards). Backend `ListMembers`
  now joins latest location (`MemberWithLocation`). Critic found 14 gaps (4
  blocking): third-party tile leak → tile URLs made configurable via
  `WHEREABOUTS_TILE_URL`/`WHEREABOUTS_SATELLITE_TILE_URL` (README documents
  self-hosting); staleness never re-evaluated → 30s `refreshStaleness` timer;
  `location` frame missing `ts` flipped member to stopped → falls back to
  `lastSeen`; `user_id` vs `id` was a false positive (backend uses `user_id`
  for location frames, `id` for members — code already correct). Also fixed:
  backoff reset on success, `fetchMembers` populates `_members` (race), cluster
  re-collapse only on user gesture, defensive casts, removed dead
  `clearPosition` + `mock_circles.dart`. `flutter analyze` clean. Re-review
  critic found 3 more third-party leak sites (GeocodingService sent coordinates
  to public Nominatim; welcome_screen + place_picker_screen hardcoded OSM
  tiles) → geocoding disabled-by-default (`WHEREABOUTS_NOMINATIM_URL`), all
  tile layers now use `kTileUrl`/`kSatelliteTileUrl` from `app_config.dart`.
  Also fixed: `movement` falls back to existing on empty `motion_state`,
  "Last seen" label advances over time, battery status falls back to existing
  on frames that omit `battery_pct`. Final critic: "No blocking defects — ours
  wins." `flutter analyze` clean.
- **Flutter places wiring done** — `place_service.dart` (GET/POST/DELETE
  /family/places), `geofence_service.dart` (GET/POST/DELETE /family/geofences),
  `Place` model gained `type` + `geofenceId` fields, `places_screen.dart`
  rewired (real fetch/create/delete, loading/error/empty states, alertsOn
  toggle wired to real geofences with optimistic flip + revert, role-gated for
  children, in-flight guard), `add_locations_screen.dart` `_finish()` POSTs
  places + creates geofences for alertsOn places (blocks navigation on place
  failure, warns on geofence failure, idempotent retry via `_createdPlaceIds`),
  `place_picker_screen.dart` gained `type` param + `hasGesture` guard. Backend:
  `GET /family` now returns caller's `role` + `user_id`, places gained `address`
  column (migration 000009), `"gym"` is a valid place type. Critic: 4 blocking
  → fixed (onboarding geofence creation, alertsOn default, role gating,
  _finish failure handling); re-review 2 blocking → fixed (onboarding geofence
  creation, _fromBackend alertsOn default); final critic "No blocking defects —
  ours wins." Non-blocking polish: fetchFamily failure warns user, alertsOn
  default consistent across model/picker/backend. `flutter analyze` clean.
- **Flutter location reporting done** — `location_reporter.dart` (foreground
  GPS stream via geolocator → POST /locations with device_id/battery/speed/
  heading/accuracy/altitude, source="foreground"), `battery_plus` dep added,
  wired into MapScreen (start in initState, stop in dispose, AppLifecycleState
  pause/resume). Critic rounds: r1 3 blocking (registration retry, POST
  serialization/throttle/dedup, UTC ts) + 5 non-blocking (web battery,
  deniedForever stop, altitude/heading guards, specific catches, lifecycle);
  r2 2 blocking (stop defeated by in-flight startStream, second concurrent
  subscription); r3 1 blocking (re-entrancy: `_running` boolean insufficient,
  generation counter added but not monotonic); r4 1 blocking (generation
  reset to 0 = boolean in disguise, fixed with separate `_active` flag +
  truly monotonic `_generation`); r5 "No blocking defects — ours wins."
  `device_service.dart` gained single-flight guard for `ensureRegistered`.
  `flutter analyze` clean.
- **Background location reporting done** — `background_locator_2` plugin for
  always-on GPS tracking when app is backgrounded/killed. `background_location_service.dart`
  (top-level `@pragma('vm:entry-point')` callback: reads creds from
  shared_preferences, POSTs /locations via dart:http, refreshes on 401, writes
  to both stores, skips isMocked, battery_pct with 5s timeout, source="background"),
  `background_credential_store.dart` (mirrors creds to shared_preferences for
  background isolate), `token_storage.dart` syncs to both stores +
  `syncFromBackgroundStore()` for recovery, `api_client.dart` `_recoverOrClear()`
  recovers from background-refreshed tokens before clearing on foreground refresh
  failure, `auth_service.dart` starts background tracking after login/signup,
  `main.dart` cold-start sync + start, `map_screen.dart` resume sync, Android
  manifest (FOREGROUND_SERVICE/WAKE_LOCK/RECEIVE_BOOT_COMPLETED +
  IsolateHolderService + BootBroadcastReceiver + allowBackup=false +
  exported=false), iOS Info.plist already had UIBackgrounds location. `kApiBaseUrl`
  moved to `app_config.dart` (circular import eliminated). Critic: r1 2 blocking
  (token rotation race, start-after-login) + 6 non-blocking (battery_pct,
  isMocked, allowBackup, exported, kApiBaseUrl, permission check); r2 1 blocking
  (foreground clear destroys background tokens — fixed with `_recoverOrClear()`)
  + 3 non-blocking (start/stop race, battery timeout, cold-start sync); r3 "No
  blocking defects — ours wins." Non-blocking polish: `_recoverOrClear()`
  try-catch, cold-start sync before `hasValidSession()`. `flutter analyze` clean.
- **Deployment polish done** — README.md updated (status, architecture, API
  surface with places/geofences/audit endpoints, directory layout, background
  location docs, self-hosted tile server guide, configuration tables, security
  notes, roadmap). PLAN.md status updated to "Core implementation complete."
  .env.example expanded (DATABASE_URL, TLS vars, APNs vars). docker-compose.yml
  fixed (TLS_BEHIND_PROXY, DATABASE_URL overridable, APNs key mount). Backend:
  90-day retention migration (000010), audit_log table + handler (000011 +
  audit.go with logAudit in auth/family/geofence/place/location handlers +
  GET /audit admin-only endpoint), member_positions table (000012, preserves
  last-known position from 90-day retention purge, backfilled from existing
  locations, ListMembers + ws.go snapshot switched from LATERAL to JOIN).
  Critic: r1 4 blocking (false claims: retention/audit/encryption, prod boot
  failure) + 5 non-blocking; r2 2 blocking (retention purges last-known
  position, "location access" audited is false) + 3 non-blocking; r3 "No
  blocking defects — ours wins." Non-blocking polish: member_positions
  backfill, motion_state nullIfEmpty consistency, DB-resolved family_id in
  audit, Go version in README. `go build` + `go vet` + `flutter analyze` clean.
