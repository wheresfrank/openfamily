# Self-Hosted Family Location Tracking — Project Plan

A privacy-first, self-hosted family location tracker. Track your family's location
without handing that data to a third party. Runs on a VPS or a Synology NAS, with
companion Android and iPhone apps.

> **Status:** Core implementation complete. The Go backend (auth with
> Argon2id + JWT + TOTP, families, devices, location ingest, WebSocket live
> streaming, places, geofences, ntfy/APNs push, audit logging, 90-day retention)
> and the Flutter app (login/signup with 2FA, live map,
> member list, places with geofence alerts, onboarding with circle invites,
> foreground + background location reporting) are built and run via Docker
> Compose (Caddy, API, TimescaleDB+PostGIS, ntfy). Encryption at rest is a
> deployment responsibility (host disk encryption / PostgreSQL TDE), not an
> app feature. Remaining work is polish and the roadmap items in §11.

---

## 1. Vision & Goals

- **Self-hosted** — you own the server, the data, and the keys. Deployable on a
  cheap VPS or a Synology NAS (Docker / Container Manager).
- **No third-party location data** — no analytics SDKs, no Google/Apple location
  aggregation, no vendor cloud. Location data lives only on your server.
- **Polished & feature-rich** — real-time map, geofencing, history, places, SOS,
  battery-aware tracking, driving safety.
- **Strict privacy & security** — TLS everywhere, strong auth (2FA/passkeys),
  encrypted at rest, minimal retention, audit logging, a written threat model.

### Non-goals (v1)
- Fleet/asset tracking (that's Traccar's domain).
- Public social features, sharing outside the family.
- Full end-to-end encryption of location (see §8 — it conflicts with server-side
  geofencing/history; documented as a future option).

---

## 2. Prior Art — Build vs. Adopt

Before building, know what already exists so we don't reinvent the wheel:

| Project | What it is | Why it's not enough |
|---|---|---|
| [OwnTracks](https://owntracks.org/) | MQTT-based self-hosted location recorder | Great protocol, but a "recorder," not a polished family app; no built-in geofencing UI, SOS, or family map experience |
| [Traccar](https://www.traccar.org/) | Self-hosted GPS tracking server | Fleet-oriented; real-time tracking is strong but family UX, SOS, and privacy polish are weak |
| [Dawarich](https://dawarich.app/) | Self-hosted location *history* (Google Timeline replacement) | Focuses on history/timeline, not real-time family sharing or geofencing |
| [Hauk](https://github.com/bilde2910/Hauk) | Simple self-hosted location sharing | Minimal feature set |
| Home Assistant person tracking | HA companion app + zones | Not a standalone polished family app |

**Decision:** Build a purpose-built app. We can *borrow* good ideas and even
interoperate with the OwnTracks MQTT protocol as an optional ingestion path, but
none of the above delivers the polished family-tracker experience.

---

## 3. High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                          Your server (VPS / NAS)                     │
│                                                                      │
│  ┌────────────┐   ┌──────────────┐   ┌───────────────────────────┐  │
│  │  Caddy     │──▶│  Go API      │──▶│  PostgreSQL + PostGIS     │  │
│  │  (TLS)     │   │  (REST+WS)   │   │  + TimescaleDB (history)  │  │
│  └────────────┘   └──────┬───────┘   └───────────────────────────┘  │
│                          │                                           │
│              ┌───────────┼───────────────┐                          │
│              ▼           ▼               ▼                          │
│        ┌──────────┐ ┌──────────┐  ┌──────────────┐                  │
│        │ Geofence │ │ Push     │  │ Map tiles    │                  │
│        │ engine   │ │ sender   │  │ (self-host)  │                  │
│        └──────────┘ └──────────┘  └──────────────┘                  │
│              │           │                                           │
└──────────────┼───────────┼───────────────────────────────────────────┘
               │           │
        ┌──────▼───┐  ┌────▼─────────────────────────────┐
        │ ntfy     │  │ APNs (iOS)  ·  UnifiedPush/ntfy   │
        │ (Android)│  │             (Android, no Google)  │
        └──────────┘  └──────────────────────────────────┘
               │
        ┌──────▼──────────────────────────────┐
        │  Flutter app (Android + iPhone)     │
        │  background location · map · SOS    │
        └─────────────────────────────────────┘
```

### Components

1. **Go API server** — single static binary. REST for CRUD, WebSocket for live
   position streaming. Handles auth, location ingest, geofence evaluation,
   history queries, SOS, and push dispatch.
2. **PostgreSQL + PostGIS** — source of truth for users, families, places,
   geofences, devices, and current positions. PostGIS gives `ST_DWithin`,
   `ST_Contains`, etc. for geofencing and "who's near me."
3. **TimescaleDB** (Postgres extension) — time-series storage for location
   history: hypertables, automatic compression, and retention policies.
4. **Geofence engine** — evaluates enter/exit events on each location update.
5. **Push sender** — dispatches notifications (see §7).
6. **Map tile server** — self-hosted tiles so map requests don't leak location
   to a third party (see §9).
7. **Caddy** — reverse proxy with automatic HTTPS (Let's Encrypt).
8. **Flutter app** — one codebase for Android + iOS.

### Why Go
- Single static binary → trivial to deploy on a NAS (no runtime, low RAM).
- Excellent concurrency for WebSocket fan-out and geofence evaluation.
- Strong stdlib (`net/http`, `crypto`, `slog`) and mature libs (`pgx`, `chi`,
  `coder/websocket`, `pquerna/otp`, `go-webauthn`).

---

## 4. Data Model (draft)

```
family            id, name, created_at, settings(jsonb)
user              id, family_id, email, name, role(admin|member|child),
                  password_hash, totp_secret, webauthn_credentials, avatar
device            id, user_id, platform(ios|android), push_token,
                  unifiedpush_endpoint, last_seen, app_version
location          (TimescaleDB hypertable)
                  device_id, ts, lat, lon, accuracy, altitude, speed,
                  heading, battery, motion_state, source
place             id, family_id, name, type(home|school|work|custom),
                  geom(geometry), radius
geofence          id, family_id, place_id, user_id, enter_notify,
                  exit_notify, enabled
geofence_event    id, geofence_id, device_id, event(enter|exit), ts
sos_event         id, user_id, family_id, ts, location, status, resolved_by
trip              id, device_id, started_at, ended_at, distance, max_speed
audit_log         id, actor_id, action, target, ip, ts, metadata
session/refresh   token records (or stateless JWT + revocation list)
```

**Retention (configurable per family):**
- Current/last-known position: kept indefinitely (small).
- Location history: default 90 days, auto-purged by TimescaleDB retention policy.
- Audit log: 1 year.

---

## 5. API Surface (draft)

| Method | Path | Purpose |
|---|---|---|
| POST | `/auth/register` | Create account (invite-only in v1) |
| POST | `/auth/login` | Password + optional TOTP |
| POST | `/auth/refresh` | Rotate access token |
| POST | `/auth/webauthn/*` | Passkey registration/login |
| POST | `/locations` | Ingest a location point (device) |
| GET | `/family/members` | List members + last-known position |
| WS | `/ws/stream` | Live position stream (family-scoped) |
| GET | `/history?from&to&device` | Location history (downsampled) |
| CRUD | `/places`, `/geofences` | Manage places & geofences |
| POST | `/sos` | Trigger SOS |
| POST | `/sos/:id/resolve` | Resolve SOS |
| GET | `/trips` | Trip list/stats |
| CRUD | `/devices` | Register/revoke devices |
| GET | `/healthz` | Health check |

---

## 6. Mobile App (Flutter)

### Background location — the critical decision

This is the single most important technical choice. Two realistic options:

| Option | Pros | Cons |
|---|---|---|
| **`flutter_background_geolocation`** (Transistorsoft) | Most sophisticated: motion-detection intelligence (accelerometer/gyro/magnetometer), battery-conscious, robust iOS+Android background behavior, built-in geofencing | **Commercial SDK** — free for development, paid license for production apps |
| **`background_locator_2`** | Open source, free | Less polished, needs manual tuning, weaker motion detection, more edge cases |

**Recommendation:** Start with `background_locator_2` (or `geolocator` +
`workmanager`) to keep the project fully open-source and free, and treat
`flutter_background_geolocation` as a paid upgrade path if battery/robustness
becomes a pain point. This is a decision to confirm before Phase 4.

### OS-specific realities (must design around)

**iOS**
- Requires **"Always"** authorization for background tracking; iOS 13+ shows
  "Allow Once / While Using / Always" and iOS 17+ adds a "Precise Location"
  toggle. The app must explain *why* it needs Always access.
- Use **Significant Location Change (SLC)** monitoring for battery-friendly
  background updates; the system can relaunch the app after termination.
- Region monitoring (geofencing) works in background, **max 20 regions/app** —
  so server-side geofencing is still required for more than 20 places.
- Declare the `location` background mode in `Info.plist`.

**Android**
- Android 10+ requires **"Allow all the time"** for background location.
- **Android 14+ (API 34)** requires declaring the `location` **foreground
  service type** in the manifest and the `FOREGROUND_SERVICE_LOCATION` runtime
  permission — without it the app crashes on start of the FGS.
- Doze/App Standby throttle background work → request battery-optimization
  exemption and use a foreground service with a persistent notification.
- Use the **Activity Recognition API** to detect still/walking/driving and
  adapt update frequency (this is the "battery-aware" core).

### Battery-aware tracking strategy
- **Motion state machine:** still → update rarely (or on SLC); walking → medium;
  driving → frequent. Driven by activity recognition + accelerometer.
- **Adaptive distance filter:** only report when moved > N meters (N scales with
  speed).
- **Geofence-assisted wakeups:** rely on OS geofencing to wake the app near
  important places instead of constant polling.
- **Battery floor:** pause high-frequency tracking below a configurable battery %.

### Feature → implementation map

| Feature | Approach |
|---|---|
| Real-time map | WebSocket stream + `flutter_map`/MapLibre; last-known positions on load |
| Geofencing alerts | Server-side `ST_DWithin` evaluation + OS region monitoring as a battery hint |
| Location history | TimescaleDB query, downsampled polyline + heatmap |
| Places/POI | CRUD + reverse-geocode (self-hosted Nominatim, optional) |
| SOS | One-tap → POST `/sos` → push + WS broadcast + high-frequency tracking for N min |
| Battery-aware | Motion state machine + adaptive filters (above) |
| Driving safety | Trip detection (activity API), speed from GPS, optional crash detection (accelerometer) as a stretch goal |

### App stack
- **State management:** Riverpod (or Bloc).
- **Maps:** `flutter_map` (open) with self-hosted tiles, or `maplibre_gl`.
- **Notifications:** `flutter_local_notifications`; UnifiedPush client on
  Android; APNs via server on iOS.
- **Auth:** token storage in platform secure storage (Keychain / Keystore).

---

## 7. Push Notifications — No Google, No Third Party

This is the trickiest privacy constraint. The honest reality:

- **iOS:** There is **no** self-hosted alternative to **APNs**. Apple forces all
  remote notifications through APNs. This is acceptable: Apple is the *platform
  vendor*, not a data broker, and we send only a **silent "wake and fetch"**
  push (no location in the payload) — the app then fetches the actual content
  from *your* server over TLS. Location never touches Apple.
- **Android:** Use **[UnifiedPush](https://unifiedpush.org/)** with a self-hosted
  **[ntfy](https://ntfy.sh/)** server as the distributor. This completely
  removes Google/FCM. The app registers with ntfy; your server POSTs to ntfy;
  ntfy delivers to the device. 100% self-hosted on Android.

**Push architecture:**
- iOS → your server → APNs (silent push) → app fetches from your server.
- Android → your server → self-hosted ntfy (UnifiedPush) → app.

**Fallback:** if a family member won't run ntfy, the app can also poll the
WebSocket while foregrounded and use a lightweight background fetch as a
degraded mode.

---

## 8. Privacy & Security Design

### Threat model (who are we defending against?)

1. **Third parties / data brokers** — the core requirement. Mitigated by
   self-hosting, zero analytics SDKs, self-hosted push and maps.
2. **Network eavesdroppers** — TLS everywhere (Caddy auto-HTTPS), HSTS.
3. **Server compromise** — encrypted at rest, minimal retention, least-privilege
   containers, read-only DB user for the API, regular updates, no SSH password
   auth.
4. **Account takeover** — strong password policy, TOTP 2FA, passkeys (WebAuthn),
   rate limiting, lockout, refresh-token rotation + revocation.
5. **Compromised/lost device** — per-device revocation, remote sign-out, device
   list in the app.
6. **Malicious family member** — role-based permissions (admin vs member vs
   child), audit log, admin can remove members.
7. **App MITM / reverse engineering** — TLS certificate pinning (best-effort),
   code obfuscation (limited value; note honestly).

### The E2E encryption trade-off (important, be explicit)

True end-to-end encryption of location data means the server cannot read it —
which **breaks** server-side geofencing, history, and cross-device live maps
(the server needs plaintext to evaluate "is Alice inside the school geofence?").

**Recommendation for v1:** *server-side processing* with these compensating
controls:
- TLS in transit (mandatory).
- **Encrypted at rest** (LUKS/FDE on the host + Postgres TDE or app-level
  encryption with a per-family key).
- **Minimal retention** (90-day default, auto-purge).
- **Self-hosted** (no third party sees anything).
- **Audit logging** of all location access.

This gives strong privacy (no third party, encrypted at rest, short retention)
while keeping all features. Document **E2E with client-side geofencing** as a
future option for users who want the server to be fully blind.

### Security checklist (v1)
- [ ] Caddy auto-HTTPS + HSTS + security headers.
- [ ] Argon2id password hashing.
- [ ] TOTP 2FA + WebAuthn passkeys.
- [ ] Short-lived access tokens + rotating refresh tokens + revocation list.
- [ ] Rate limiting + account lockout.
- [ ] Per-family data isolation (row-level security or scoped queries).
- [ ] Encrypted at rest (host FDE + DB encryption).
- [ ] Encrypted, offsite backups (restic/age).
- [ ] Audit log of auth + location access.
- [ ] Secrets via env/`.env` + Docker secrets, never in git.
- [ ] Dependency scanning + regular base-image updates.
- [ ] Certificate pinning in the app (best-effort).

---

## 9. Maps — Self-Hosted Tiles

Using a public tile server (OSM, Mapbox) leaks your family's map-view location
to that provider. For strict privacy, self-host tiles:

- **Option A (recommended):** self-host **OpenMapTiles + tileserver-gl** with a
  regional extract (e.g., your country/state) — vector tiles, small footprint,
  no per-request leakage.
- **Option B:** serve OSM raster tiles via a lightweight tile server/proxy.
- **Option C (pragmatic fallback):** use OSM public tiles but route through your
  own caching proxy so requests appear to come from your server, not each phone.

**Recommendation:** Option A for the map, with Option C as a quick start.
Reverse-geocoding (address for a coordinate) via self-hosted **Nominatim** if
needed, or skip it in v1 (places are user-named).

---

## 10. Deployment

### Docker Compose (works on both VPS and Synology)

```yaml
services:
  caddy:        # TLS + reverse proxy
  api:          # Go binary
  postgres:     # PostGIS + TimescaleDB
  ntfy:         # Android push (UnifiedPush)
  tileserver:   # self-hosted map tiles (optional)
  # optional: nominatim, prometheus, grafana
```

### Synology NAS considerations
- Requires an **x86_64** model with **Container Manager** (Docker). ARM models
  are possible but slower and some images lack ARM builds.
- **RAM budget:** Postgres+TimescaleDB (~512 MB–1 GB), Go API (~50–100 MB),
  ntfy (~50 MB), tileserver (~200–500 MB). A NAS with **4 GB+ RAM** is
  comfortable; 2 GB is tight.
- Use a **volume** on the NAS for Postgres data + backups; enable NAS snapshots.
- **Tailscale/WireGuard** for remote access instead of exposing ports publicly
  (strongly recommended for a NAS).

### VPS considerations
- Any 1–2 vCPU / 2 GB VPS is plenty for 10–30 devices.
- Caddy handles Let's Encrypt automatically; open only 80/443.
- Consider a firewall (ufw) + fail2ban.

---

## 11. Roadmap

| Phase | Deliverable | Rough effort |
|---|---|---|
| **0. Decisions** | Confirm name, map strategy, background-location plugin, E2E stance | — |
| **1. Backend core** | Go API: auth (password+TOTP), families, devices, location ingest, PostGIS schema, migrations | 1–2 wks |
| **2. Realtime + map** | WebSocket stream, last-known positions, web map view (or app map) | 1 wk |
| **3. Geofencing + push** | Geofence engine, enter/exit events, ntfy + APNs dispatch | 1–2 wks |
| **4. Mobile apps** | Flutter: auth, background location, map, settings | 2–4 wks |
| **5. Features** | History, places, SOS, battery-aware, trips/driving | 2–4 wks |
| **6. Hardening + polish** | Security checklist, retention, backups, docs, onboarding UX | 1–2 wks |

**Total rough estimate:** 8–14 weeks of focused part-time work to a polished v1.

---

## 12. Open Decisions (to confirm before Phase 1)

1. **Project name** — suggestions: *Hearth, Kin, Homestead, Whereabouts, Nest,
   Herd, Beacon.*
2. **Background-location plugin** — open-source (`background_locator_2`) vs
   commercial (`flutter_background_geolocation`). See §6.
3. **Map strategy** — self-hosted OpenMapTiles (A) vs caching proxy (C). See §9.
4. **E2E stance** — server-side processing (recommended) vs E2E. See §8.
5. **Invite model** — invite-only (admin creates accounts) vs open registration
   with a family code.
6. **Crash detection** — include in v1 or defer (it's hard to do reliably).
7. **Reverse geocoding** — self-hosted Nominatim now, or defer.

---

## 13. Risks & Honest Caveats

- **iOS background tracking is inherently limited** by Apple — expect "Always"
  authorization friction and occasional gaps; SLC is the battery-friendly path.
- **Android OEM battery killers** (Samsung, Xiaomi, etc.) can kill background
  services despite correct implementation — needs per-OEM exemption guidance.
- **Crash detection** is unreliable without dedicated hardware; treat as a
  stretch goal, not a safety guarantee.
- **E2E encryption** is not compatible with server-side geofencing/history —
  we're choosing server-side processing + strong compensating controls.
- **APNs is unavoidable on iOS** — Apple is the platform vendor; we minimize
  exposure with silent pushes (no location in payload).

---

## 14. Facts to Re-verify When Web Tools Are Stable

The following were confirmed via search but are fast-moving; re-check before
implementation:
- Exact Android 15 (API 35) background-location/FGS changes.
- Current `flutter_background_geolocation` licensing terms.
- Latest `background_locator_2` maintenance status.
- OpenMapTiles regional extract sizes for your target region.
