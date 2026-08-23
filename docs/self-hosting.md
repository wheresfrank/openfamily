# Self-hosting Whereabouts

Production checklist for operators. The README [Quick start](../README.md#quick-start)
is enough for a laptop. Use this before you invite a family onto a VPS or NAS
that is reachable from the internet.

## Before `docker compose up`

1. Copy `.env.example` to `.env`. Do not commit `.env`.
2. Set `APP_ENV=production`.
3. Set `JWT_SECRET` to at least 32 random bytes (`openssl rand -base64 48`).
4. Set `POSTGRES_PASSWORD` (and `DATABASE_URL` with `sslmode=require` if Postgres
   is not on the Compose network).
5. Set `SITE_ADDRESS=whereabouts.example.com` (Caddy will request a certificate).
6. Set `PLATFORM_ADMIN_EMAIL` and `PLATFORM_ADMIN_PASSWORD`. This creates the
   first admin and **closes open registration** (invite codes required).
7. Set `TLS_BEHIND_PROXY=true` (Compose default) so the API accepts HTTP from
   Caddy on the private network.

## Android push (ntfy)

Do **not** publish ntfy on `0.0.0.0:2586`. Current Compose binds loopback only.

For phones on the public internet:

```bash
PUSH_ADDRESS=push.example.com
NTFY_BASE_URL=https://push.example.com
CADDYFILE=Caddyfile.with-push
```

Install the [ntfy Android app](https://ntfy.sh/) on each phone. UnifiedPush
registration is silent; if alerts never arrive, ntfy is usually missing.

## Map tiles

Default street tiles are public OSM; satellite is Esri. Those hosts see the
viewport. To use another raster provider (API key goes in the URL):

```bash
TILE_URL=https://tiles.example.com/{z}/{x}/{y}.png?api_key=xxx
SATELLITE_TILE_URL=
```

The API returns these on `GET /config`. The generic APK does not need a rebuild.
A key in `TILE_URL` is visible to every phone.

## Optional SMS

Set `TWILIO_*` and `PUBLIC_BASE_URL=https://whereabouts.example.com` so SOS
messages carry a share link instead of raw coordinates.

## Backups and disk encryption

- Volume `pgdata` is the family database. Snapshot it. Schedule `pg_dump`.
- Enable host disk encryption (LUKS, Synology volume encryption, cloud disk
  encryption). The app does not encrypt rows itself.
- Keep `app/android/upload-keystore.jks` (or CI signing secrets) backed up.
  Losing the keystore forces every phone to uninstall before they can update.

## Family setup (give this to members)

1. Install the Android APK from the admin **Builds** page (or the GitHub
   Release).
2. Enter `https://whereabouts.example.com` and Connect.
3. Create an account (invite code if the server requires one).
4. Allow **Always** location, notifications, and the battery exemption.
5. Install **ntfy** so alerts arrive when the app is closed.
