# Whereabouts

A self-hosted, privacy-first family location tracker you run yourself.
Your family's location data never leaves your
server.

> **Status:** fully functional self-hosted family location tracker. The Go
> backend implements auth (Argon2id + JWT + TOTP 2FA), families, devices,
> location ingest, WebSocket live streaming, places, geofences, and push
> (ntfy/APNs). The Flutter app covers login/signup with 2FA, a live map with
> member positions, a member list, places with geofence alerts, onboarding with
> circle invites, and foreground + background location reporting. A **web admin
> panel** (served by the backend at `/admin`) lets a platform admin view a live
> map of every family and member, browse groups, and download the Android APK.
> Privacy is first-class: self-hosted, configurable tile URLs, geocoding
> disabled by default, 90-day retention, and audit logging.

## Architecture

```
┌──────────┐   ┌──────────┐   ┌──────────────────────────────┐
│  Caddy   │──▶│  Go API  │──▶│  PostgreSQL + PostGIS        │
│  (TLS)   │   │ (REST+WS)│   │  + TimescaleDB (history)     │
└──────────┘   └────┬─────┘   └──────────────────────────────┘
                    │
              ┌─────▼─────┐
              │   ntfy    │  (Android UnifiedPush — no Google)
              └───────────┘
```

Map tiles are an **optional** component: for full privacy, self-host them with
[tileserver-gl](https://github.com/maptiler/tileserver-gl) (see
[Self-hosting map tiles](#self-hosting-map-tiles-recommended-for-privacy)) and
point the app at them via `WHEREABOUTS_TILE_URL`. On iOS, push goes through
**APNs**, which requires an Apple Developer account and an APNs auth key (see
[Configuration](#configuration-environment-variables)).

| Component | Path | Notes |
|---|---|---|
| Go API | `backend/` | REST + WebSocket, Argon2id + JWT + TOTP auth |
| Flutter app | `app/` | Android + iOS |
| Web admin panel | `web/` | Vite + React + Leaflet SPA, embedded in the Go binary and served at `/admin` |
| Docker Compose | `docker-compose.yml` | caddy, api, postgres, ntfy |
| Migrations | `backend/internal/db/migrations/` | PostGIS + TimescaleDB schema |

## Directory layout

```
location/
├── backend/
│   ├── cmd/server/main.go          # entrypoint + router
│   ├── internal/
│   │   ├── auth/                   # Argon2id, JWT, TOTP
│   │   ├── config/                 # env-based config
│   │   ├── db/                     # pgx pool + embedded migrations
│   │   │   └── migrations/         # 000001_init.{up,down}.sql
│   │   ├── handlers/               # auth, family, device, location, place, geofence, ws
│   │   ├── middleware/             # JWT auth middleware
│   │   ├── models/                 # domain types
│   │   └── push/                   # ntfy + APNs dispatch
│   ├── Dockerfile
│   └── go.mod
├── app/
│   ├── lib/
│   │   ├── main.dart
│   │   ├── models/                 # member, place
│   │   ├── screens/                # add_locations, check_in, create_circle,
│   │   │                           #   create_or_join_circle, day_detail,
│   │   │                           #   help_alert, invite, join_circle, keys,
│   │   │                           #   login, map, member_profile,
│   │   │                           #   permissions, place_picker, places,
│   │   │                           #   safety, settings, sign_up, sos, welcome
│   │   ├── services/               # api_client, app_config, auth_service,
│   │   │                           #   background_credential_store,
│   │   │                           #   background_location_service,
│   │   │                           #   device_service, family_service,
│   │   │                           #   geocoding_service, geofence_service,
│   │   │                           #   invite_service, join_service,
│   │   │                           #   location_reporter, location_service,
│   │   │                           #   member_mapper, permission_service,
│   │   │                           #   place_service, profile_storage,
│   │   │                           #   token_storage
│   │   ├── widgets/                # circle_switcher, map_bottom_bar,
│   │   │                           #   member_avatar_bubble, member_list_sheet,
│   │   │                           #   movement_icon, onboarding_step_indicator
│   │   ├── utils/                  # member_clustering
│   │   └── theme/                  # app_theme
│   ├── android/                    # Android platform files
│   ├── ios/                        # iOS platform files
│   └── pubspec.yaml
├── web/                            # Web admin panel (Vite + React + Leaflet)
│   ├── src/
│   │   ├── components/             # shell: sidebar, top bar, ⌘K, primitives
│   │   ├── pages/                  # dashboard, groups, builds, settings
│   │   └── map/                    # live map: bubbles, clustering, places, WS
│   ├── vite.config.ts
│   └── package.json
├── caddy/Caddyfile
├── docker-compose.yml
├── .env.example
├── PLAN.md
└── README.md
```

## API surface (current)

| Method | Path | Purpose |
|---|---|---|
| GET | `/healthz` | Health check |
| POST | `/auth/register` | Create account |
| POST | `/auth/login` | Password + optional TOTP → token pair |
| POST | `/auth/refresh` | Rotate refresh token |
| POST | `/families` | Create a family (caller becomes admin) |
| GET | `/family` | Get your family |
| GET | `/family/members` | List members |
| PATCH | `/family/members/{id}/role` | Change a member's role |
| POST | `/family/invites` | Create an invite code for your family (admin only) |
| POST | `/family/join` | Join a family by invite code |
| GET | `/family/places` | List places |
| POST | `/family/places` | Create a place |
| PATCH | `/family/places/{id}` | Update a place |
| DELETE | `/family/places/{id}` | Delete a place |
| GET | `/family/geofences` | List geofences |
| POST | `/family/geofences` | Create a geofence |
| PATCH | `/family/geofences/{id}` | Update a geofence |
| DELETE | `/family/geofences/{id}` | Delete a geofence |
| GET | `/audit` | List recent audit log entries (admin only) |
| POST | `/devices` | Register a device |
| GET | `/devices` | List your devices |
| POST | `/locations` | Ingest a location point |
| WS | `/ws/stream` | Live position stream (family-scoped) |

### Platform-admin API (web admin panel)

All routes require a platform admin (see `PLATFORM_ADMIN_EMAIL` below). The
admin SPA is served at `/admin` and calls these under `/api/admin/*`.

| Method | Path | Purpose |
|---|---|---|
| GET | `/api/admin/families` | List every family |
| POST | `/api/admin/families` | Create a family |
| PATCH | `/api/admin/families/{id}` | Rename a family |
| DELETE | `/api/admin/families/{id}` | Delete a family |
| GET | `/api/admin/families/{id}/members` | List one family's members |
| GET | `/api/admin/members` | List every member across all families |
| PATCH | `/api/admin/members/{id}/family` | Move a member to another family |
| GET | `/api/admin/places` | List every saved place (Home/School/Work) across all families |
| GET | `/api/admin/invites` | List every invite code |
| POST | `/api/admin/invites` | Create an invite code for any family |
| GET | `/api/admin/apk` | Download the Android APK (served from `APK_DIR`) |
| POST | `/api/admin/apk/build` | Kick off an APK build (optional; requires Flutter on the server) |
| GET | `/api/admin/apk/status` | Poll APK build status (optional) |
| WS | `/api/admin/ws` | Live position stream across all families |

## Run locally

### Prerequisites

- Docker + Docker Compose
- Go 1.25+ (only if running the API outside Docker)
- Flutter 3.x (only for the app)

### 1. Start the stack

```bash
cp .env.example .env
# edit .env: set a strong POSTGRES_PASSWORD and JWT_SECRET
docker compose up -d --build
```

The API is reachable at `http://localhost` (via Caddy). Check it:

```bash
curl http://localhost/healthz
# {"status":"ok"}
```

### 2. Try the API

```bash
# Register
curl -X POST http://localhost/auth/register \
  -H 'Content-Type: application/json' \
  -d '{"email":"alice@example.com","password":"supersecret1","name":"Alice"}'

# Login (capture the access_token)
curl -X POST http://localhost/auth/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"alice@example.com","password":"supersecret1"}'
```

### 3. Run the API directly (without Docker)

```bash
cd backend
go build ./...
DATABASE_URL="postgres://whereabouts:whereabouts@localhost:5432/whereabouts?sslmode=disable" \
JWT_SECRET="$(openssl rand -base64 48)" \
./server
```

Migrations run automatically at startup (embedded in the binary).

### 4. Run the Flutter app

The app talks to the Go backend, so you must point it at your API URL with a
`--dart-define` at build/run time. Without it the app fails loudly with
"API URL not configured".

```bash
cd app
flutter create .        # generates any missing platform scaffolding (icons, Xcode project)
flutter pub get
flutter run --dart-define=WHEREABOUTS_API_URL=http://localhost
```

The host depends on where the emulator/simulator runs:

| Target | `WHEREABOUTS_API_URL` |
|---|---|
| iOS simulator | `http://localhost` (shares the host network) |
| Android emulator | `http://10.0.2.2` (host loopback from inside the emulator) |
| Physical device | `http://<your-machine-LAN-IP>` (e.g. `http://192.168.1.20`) |

Auth (login/sign-up with 2FA), device registration, token storage
(`flutter_secure_storage`), the live map, member list, places, and geofence
alerts are all wired to the real backend. The app also reports location in the
background (see [Background location](#background-location)).

#### Background location

The app uses [`background_locator_2`](https://pub.dev/packages/background_locator_2)
for always-on background location tracking:

- **Android:** a foreground service with a persistent notification keeps
  reporting even when the app is backgrounded or killed, and restarts after a
  device reboot.
- **iOS:** the `location` background mode keeps updates flowing while
  backgrounded.
- Tracking **starts after login** and **stops on logout**.
- Credentials are mirrored to `shared_preferences` so the background isolate
  (which cannot reach `flutter_secure_storage`) can authenticate and refresh
  tokens itself. See the security note on this tradeoff below.

#### Map tiles (privacy)

By default the map loads tiles from the public OpenStreetMap and Esri ArcGIS
servers, which receive your family's map viewport (i.e. roughly where they
are) on every pan/zoom. For a privacy-first deployment, self-host your tiles
and point the app at them:

```bash
flutter run \
  --dart-define=WHEREABOUTS_API_URL=http://localhost \
  --dart-define=WHEREABOUTS_TILE_URL=https://tiles.your.server/{z}/{x}/{y}.png \
  --dart-define=WHEREABOUTS_SATELLITE_TILE_URL=https://tiles.your.server/sat/{z}/{y}/{x}
```

`WHEREABOUTS_TILE_URL` is the street layer and
`WHEREABOUTS_SATELLITE_TILE_URL` the satellite layer; both use `{z}`/`{x}`/`{y}`
placeholders (note the satellite layer's `{y}`/`{x}` order matches the ArcGIS
default).

#### Self-hosting map tiles (recommended for privacy)

For a fully private deployment, host your own tile server. The simplest option is
[tileserver-gl](https://github.com/maptiler/tileserver-gl), which serves raster
tiles from an MBTiles file:

1. Download an OSM extract for your region from [Geofabrik](https://download.geofabrik.de/)
   or [Protomaps](https://docs.protomaps.com/).
2. Add a tileserver service to your `docker-compose.yml`:

   ```yaml
   tiles:
     image: maptiler/tileserver-gl:latest
     restart: unless-stopped
     volumes:
       - ./tiles/data.mbtiles:/data/data.mbtiles:ro
     expose:
       - "80"
   ```

3. Add a Caddy reverse proxy for TLS:

   ```
   tiles.example.com {
       reverse_proxy tiles:80
   }
   ```

4. Point the app at your tile server:

   ```bash
   flutter run \
     --dart-define=WHEREABOUTS_API_URL=https://whereabouts.example.com \
     --dart-define=WHEREABOUTS_TILE_URL=https://tiles.example.com/{z}/{x}/{y}.png
   ```

#### Geocoding (privacy)

Address search and reverse geocoding (in the place picker) are **disabled by
default** so the app never sends a family member's coordinates or address
queries to the public OSM Nominatim endpoint. To enable them against your own
Nominatim instance:

```bash
flutter run \
  --dart-define=WHEREABOUTS_API_URL=http://localhost \
  --dart-define=WHEREABOUTS_NOMINATIM_URL=https://nominatim.your.server
```

Without `WHEREABOUTS_NOMINATIM_URL`, the place picker still works by tapping
the map; only address search and auto-fill are unavailable.

## Web admin panel

The backend serves a web admin panel at `/admin` (the SPA is embedded in the Go
binary via `go:embed`, so no separate web server is needed). It lets a
**platform admin** — a user who can see *all* families, not just their own —
view a live map of every group and member, browse groups, and download the
Android APK.

### Grant platform-admin access

Platform admin is a per-user flag (`users.platform_admin`, migration `000013`),
distinct from family admin. There is no self-service signup for it; the only way
to grant it is to bootstrap the first admin via environment variables:

1. Set `PLATFORM_ADMIN_EMAIL=admin@example.com` and
   `PLATFORM_ADMIN_PASSWORD=<a strong password>` in `.env`.
2. Start the API. On startup it **auto-creates** that account (if it doesn't
   already exist), marks it `platform_admin = true`, and creates a family for
   it — so the admin is the **first user to log in**. If the account already
   exists, it is simply promoted (idempotent — safe to leave set across
   restarts).

Setting `PLATFORM_ADMIN_EMAIL` also **closes open registration**: new users must
register with a valid invite code (see [Invite codes](#invite-codes)). Leave it
empty to keep open registration (and disable the admin panel).

### Use it

1. Start the stack (`docker compose up -d --build`) and open
   `https://<your-host>/admin`.
2. Log in with the platform-admin account (the panel reuses the normal
   `/auth/login` flow, including TOTP 2FA if enabled).
3. The **Dashboard** shows a live map of every family's members (with
   per-member color rings, status dots, movement badges, and Home/School/Work
   place pins), streaming updates over `/api/admin/ws`. The **Families** page
   lists families and members and lets you **move a member to another family**,
   rename/delete/create families, and generate invite codes; **APK** downloads
   the Android APK; **Settings** shows your session token and API endpoints.

### Invite codes

When `PLATFORM_ADMIN_EMAIL` is set, registration is closed: a new user must
present a valid invite code to register. Each code is bound to a family and
assigns the joining user that family and role (admin/member/child), with a
default 7-day expiry and single use.

Codes are 8-character alphanumeric strings drawn from a Crockford-style
alphabet (digits and letters, with the ambiguous `0`/`O` and `1`/`I`/`L`
removed) — about 40 bits of entropy. They are case-insensitive and tolerate
spaces/dashes on input (e.g. `ab12-cd34` matches `AB12CD34`).

- **Family admins** generate codes from the app (the "Invite" flow calls
  `POST /family/invites`).
- **Platform admins** generate codes for any family from the web panel's
  **Families** page (`POST /api/admin/invites`).
- A new user registers with the code (`POST /auth/register` with
  `invite_code`), or an already-registered user joins a family with
  `POST /family/join`.

### Terminology

The shared-location group is called a **family** everywhere (backend, web
admin, and app). Earlier builds used "group" and "circle" interchangeably for
the same concept; those have been standardized to "family".

### APK builds (CI)

The server does **not** build APKs itself — that would require a multi-GB
Flutter/Android toolchain in the server image. Instead, the APK is built in CI
and the admin panel's **APK** page just serves it.

1. Push a release tag (e.g. `v0.1.0`). The
   [`.github/workflows/apk.yml`](.github/workflows/apk.yml) workflow builds the
   release APK and attaches it to the GitHub release.
2. Download the APK from the release and copy it into the server's `APK_DIR`
   directory (see `.env.example`), e.g. `./apk/whereabouts-release.apk`.
3. The **APK** page's **Download** button then serves it via
   `GET /api/admin/apk`.

The app has a runtime server-config screen, so one generic APK works for any
deployment — no per-deployment rebuild is needed.

### Build the web panel (development)

The panel is a Vite + React + TypeScript + Leaflet app in `web/`. To rebuild the
embedded bundle after changing it:

```bash
cd web
npm install
npm run build          # outputs web/dist/
cd ../backend
go build ./...         # re-embeds web/dist/ into the binary
```

## Run on a Synology NAS

1. **Requirements:** an x86_64 model with **Container Manager** (Docker) and
   **4 GB+ RAM** (Postgres + TimescaleDB is the main consumer).
2. Copy this repo to the NAS (e.g. via `git clone` or a shared folder).
3. In Container Manager → **Project**, create a new project pointing at the
   `docker-compose.yml`, or use SSH:

   ```bash
   cd /path/to/location
   cp .env.example .env   # set strong secrets
   docker compose up -d --build
   ```

4. **Storage:** the `pgdata` volume holds all data. Put it on a NAS volume with
   snapshots enabled, and back it up (e.g. `pg_dump` on a schedule).
5. **Remote access (recommended):** do **not** expose ports publicly. Use
   **Tailscale** or **WireGuard** to reach the NAS, then set
   `SITE_ADDRESS=whereabouts.<your-tailnet>.ts.net` so Caddy gets a real
   certificate. For a public domain, set `SITE_ADDRESS=whereabouts.example.com`
   and open ports 80/443.
6. **ntfy / UnifiedPush:** set `PUSH_ADDRESS=push.example.com` (or a Tailscale
   name) and `NTFY_BASE_URL=https://push.example.com` so Android push works
   over TLS without Google. Note that `PUSH_ADDRESS` alone does not enable TLS —
   you must also add a Caddy site block for ntfy (see the commented example in
   `caddy/Caddyfile`).

## Configuration (environment variables)

### Backend

| Variable | Default | Purpose |
|---|---|---|
| `HTTP_ADDR` | `:8080` | API listen address |
| `DATABASE_URL` | local dev URL | PostgreSQL connection string |
| `JWT_SECRET` | `change-me-in-production` | JWT signing secret (set this!) |
| `ACCESS_TOKEN_TTL` | `15m` | Access token lifetime |
| `REFRESH_TOKEN_TTL` | `720h` | Refresh token lifetime |
| `ALLOWED_ORIGIN` | *(empty)* | CORS origin |
| `APP_ENV` | `development` | `development` or `production` (production fails fast on insecure defaults) |
| `TLS_CERT_FILE` / `TLS_KEY_FILE` | *(empty)* | Direct HTTPS cert/key (optional; Caddy is the recommended path) |
| `TLS_BEHIND_PROXY` | `false` | Set `true` when a reverse proxy terminates TLS |
| `INSECURE_HTTP` | `false` | Explicit opt-out of TLS (trusted private networks only) |
| `VERBOSE_PUSH` | `false` | Include the user's name in push payloads (default omits it) |
| `PLATFORM_ADMIN_EMAIL` | *(empty)* | Email of the first platform admin. On startup the matching user is promoted to `platform_admin = true`; if no such user exists, the account is auto-created (see `PLATFORM_ADMIN_PASSWORD`). Setting it also closes open registration (invite codes required). |
| `PLATFORM_ADMIN_PASSWORD` | *(empty)* | Password for the auto-created first admin account (only used when `PLATFORM_ADMIN_EMAIL` is set and the account does not exist yet). |
| `APNS_KEY_FILE` | *(empty)* | Path to the APNs `.p8` auth key (empty disables APNs) |
| `APNS_KEY_ID` | *(empty)* | APNs key ID |
| `APNS_TEAM_ID` | *(empty)* | Apple Developer team ID |
| `APNS_TOPIC` | *(empty)* | App bundle ID |
| `APNS_PRODUCTION` | `false` | Use the APNs production endpoint |

### Flutter app (build-time `--dart-define`)

| Variable | Default | Purpose |
|---|---|---|
| `WHEREABOUTS_API_URL` | *(empty)* | Backend base URL (required; app fails loudly if unset) |
| `WHEREABOUTS_TILE_URL` | OSM public tiles | Street tile URL template (`{z}`/`{x}`/`{y}`) |
| `WHEREABOUTS_SATELLITE_TILE_URL` | ArcGIS public tiles | Satellite tile URL template |
| `WHEREABOUTS_NOMINATIM_URL` | *(empty)* | Self-hosted Nominatim base URL (geocoding disabled when empty) |

## Security notes

- Passwords are hashed with **Argon2id**; TOTP 2FA is verified at login when
  enabled on the account.
- Access tokens are short-lived; refresh tokens rotate via `/auth/refresh`.
- Set a strong `JWT_SECRET` and `POSTGRES_PASSWORD` before exposing anything.
- The `JWT_SECRET` default is intentionally insecure — it exists only so the
  stack boots out of the box.
- **Encryption at rest is a deployment responsibility** — the app does **not**
  encrypt data at rest itself. The operator must enable PostgreSQL TDE or
  full-disk encryption (e.g. LUKS) on the host so location data is not readable
  from a stolen disk.
- **90-day location retention** — TimescaleDB auto-purges location history older
  than 90 days; the last-known position per member is preserved in a separate
  `member_positions` table so inactive members remain visible on the map.
- **Audit logging** — sensitive operations (auth, role changes, location ingest,
  place/geofence management) are recorded.
- **No third-party location data** — self-hosted tiles and self-hosted push
  (ntfy) keep map viewports and notifications off third-party servers; iOS push
  uses APNs (Apple is the platform vendor, and payloads carry no location).
- **Background credentials** live in `shared_preferences` (not secure storage) —
  a documented tradeoff so the background isolate can authenticate and refresh
  tokens. `android:allowBackup="false"` prevents these credentials from being
  backed up to the cloud.

## Roadmap

Done: auth (Argon2id + JWT + TOTP), families, devices, location ingest,
WebSocket live streaming, places, geofences, ntfy/APNs push, the Flutter map,
onboarding, foreground + background location reporting, 90-day retention,
audit logging, a location history timeline (day detail; synthetic fallback
until backend history is wired), and the web admin panel (platform-admin live
map of all families, groups, APK build/download, served at `/admin`).

Pending: app icon, the "Bubble" privacy feature, self-hosted Nominatim
deployment, a phone field, member join/leave presence, activity recognition
(`motion_state`), adaptive battery-aware tracking, and wiring the location
history UI to real backend history.
See `PLAN.md` for the full plan.
