// Command server runs the Whereabouts API.
package main

import (
	"context"
	"errors"
	"io/fs"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/whereabouts/whereabouts/backend/internal/auth"
	"github.com/whereabouts/whereabouts/backend/internal/config"
	"github.com/whereabouts/whereabouts/backend/internal/db"
	handlers "github.com/whereabouts/whereabouts/backend/internal/handlers"
	mid "github.com/whereabouts/whereabouts/backend/internal/middleware"
	"github.com/whereabouts/whereabouts/backend/internal/push"
	"github.com/whereabouts/whereabouts/backend/internal/sms"
	web "github.com/whereabouts/whereabouts/backend/web"
)

func main() {
	cfg := config.Load()

	logger := slog.New(slog.NewTextHandler(os.Stdout, nil))
	slog.SetDefault(logger)

	// Fail fast on insecure configuration (missing/insecure JWT secret, and
	// insecure database/TLS defaults in production).
	if err := cfg.Validate(); err != nil {
		slog.Error("invalid configuration", "err", err)
		os.Exit(1)
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	// Apply migrations before serving.
	if err := db.Migrate(cfg.DatabaseURL); err != nil {
		slog.Error("migration failed", "err", err)
		os.Exit(1)
	}
	slog.Info("migrations applied")

	pool, err := db.Connect(ctx, cfg.DatabaseURL)
	if err != nil {
		slog.Error("database connection failed", "err", err)
		os.Exit(1)
	}
	defer pool.Close()

	tm := auth.NewTokenManager(cfg.JWTSecret, cfg.AccessTokenTTL, cfg.RefreshTokenTTL)
	dispatcher := push.NewDispatcher(push.APNsConfig{
		KeyFile:    cfg.APNsKeyFile,
		KeyID:      cfg.APNsKeyID,
		TeamID:     cfg.APNsTeamID,
		Topic:      cfg.APNsTopic,
		Production: cfg.APNsProduction,
	})
	srv := handlers.New(pool, tm, dispatcher)
	srv.VerbosePush = cfg.VerbosePush
	srv.NtfyBaseURL = cfg.NtfyBaseURL
	srv.APNsConfigured = cfg.APNsKeyFile != ""
	srv.SMS = sms.New(sms.Config{
		AccountSID: cfg.TwilioAccountSID,
		AuthToken:  cfg.TwilioAuthToken,
		From:       cfg.TwilioFrom,
	})
	srv.AlertLimit = sms.NewLimiter()
	srv.PublicBaseURL = cfg.PublicBaseURL
	srv.AllowedOrigin = cfg.AllowedOrigin
	srv.APKDir = cfg.APKDir
	srv.FlutterAppDir = cfg.FlutterAppDir
	// A managed server (one with a configured platform admin) closes open
	// registration: new users must present an invite code.
	srv.RequireInvite = cfg.PlatformAdminEmail != ""

	// Promote (or auto-create) the configured platform admin (idempotent, every
	// startup). This is the secure bootstrap for the first platform admin: no
	// credentials are hardcoded; it requires the env vars and, when the account
	// does not exist yet, PLATFORM_ADMIN_PASSWORD to create it.
	srv.BootstrapPlatformAdmin(ctx, cfg.PlatformAdminEmail, cfg.PlatformAdminPassword)

	// Background reconciliation self-heals any geofence evaluation that failed
	// or was interrupted during ingest.
	go srv.ReconcileGeofences(ctx)

	r := chi.NewRouter()
	r.Use(middleware.RequestID)
	r.Use(middleware.RealIP)
	r.Use(middleware.Recoverer)
	r.Use(cors(cfg.AllowedOrigin))

	r.Get("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"status":"ok"}`))
	})
	r.Get("/config", srv.GetConfig)

	// Auth (unauthenticated).
	r.Post("/auth/register", srv.Register)
	r.Post("/auth/login", srv.Login)
	r.Post("/auth/refresh", srv.Refresh)

	// WebSocket stream (authenticates via Bearer header or Sec-WebSocket-Protocol subprotocol).
	r.Get("/ws/stream", srv.Stream)

	// Platform-admin live WebSocket stream (all families). Registered at the top
	// level like /ws/stream because the Sec-WebSocket-Protocol token carrier
	// cannot be seen by the RequireAuth/RequirePlatformAdmin middleware; the
	// handler enforces both checks itself (see AdminStream).
	r.Get("/api/admin/ws", srv.AdminStream)

	// Authenticated API.
	r.Group(func(r chi.Router) {
		r.Use(mid.RequireAuth(tm))

		r.Get("/me", srv.GetMe)
		r.Patch("/me", srv.UpdateMe)
		r.Get("/me/contacts", srv.ListEmergencyContacts)
		r.Post("/me/contacts", srv.CreateEmergencyContact)
		r.Delete("/me/contacts/{id}", srv.DeleteEmergencyContact)

		// Account profile and avatar are deliberately private to the caller.
		r.Get("/api/profile", srv.GetProfile)
		r.Get("/api/profile/avatar", srv.GetProfileAvatar)
		r.Put("/api/profile/avatar", srv.PutProfileAvatar)
		r.Delete("/api/profile/avatar", srv.DeleteProfileAvatar)

		r.Post("/families", srv.CreateFamily)
		r.Get("/family", srv.GetFamily)
		r.Patch("/family", srv.RenameFamily)
		r.Post("/family/leave", srv.LeaveFamily)
		r.Get("/family/members", srv.ListMembers)
		r.Get("/family/members/{id}/avatar", srv.GetFamilyMemberAvatar)
		r.Get("/family/members/{id}/history", srv.GetMemberHistory)
		r.Patch("/family/members/{id}/role", srv.UpdateMemberRole)
		r.Post("/family/invites", srv.CreateFamilyInvite)
		r.Post("/family/join", srv.JoinFamily)

		r.Get("/family/geofences", srv.ListGeofences)
		r.Post("/family/geofences", srv.CreateGeofence)
		r.Patch("/family/geofences/{id}", srv.UpdateGeofence)
		r.Delete("/family/geofences/{id}", srv.DeleteGeofence)

		r.Get("/family/places", srv.ListPlaces)
		r.Post("/family/places", srv.CreatePlace)
		r.Patch("/family/places/{id}", srv.UpdatePlace)
		r.Delete("/family/places/{id}", srv.DeletePlace)

		r.Get("/audit", srv.ListAudit)

		r.Post("/devices", srv.RegisterDevice)
		r.Get("/devices", srv.ListDevices)
		r.Patch("/devices/{id}", srv.UpdateDevice)

		r.Post("/locations", srv.IngestLocation)
	})

	// Platform admin API, namespaced under /api/admin/* so it never collides
	// with the admin SPA served at /admin/* (which falls back to index.html for
	// client-side routing). RequireAuth runs first (injects claims);
	// RequirePlatformAdmin re-reads the platform_admin flag from the DB on
	// every request (never trusts the JWT).
	r.Group(func(r chi.Router) {
		r.Use(mid.RequireAuth(tm))
		r.Use(mid.RequirePlatformAdmin(pool))

		r.Get("/api/admin/families", srv.AdminListFamilies)
		r.Post("/api/admin/families", srv.AdminCreateFamily)
		r.Patch("/api/admin/families/{id}", srv.AdminRenameFamily)
		r.Delete("/api/admin/families/{id}", srv.AdminDeleteFamily)
		r.Get("/api/admin/families/{id}/members", srv.AdminListFamilyMembers)
		r.Get("/api/admin/members", srv.AdminListMembers)
		r.Get("/api/admin/members/{id}/avatar", srv.GetAdminMemberAvatar)
		r.Get("/api/admin/members/{id}/history", srv.AdminGetMemberHistory)
		r.Patch("/api/admin/members/{id}/family", srv.AdminMoveMember)
		r.Get("/api/admin/users", srv.AdminListUsers)
		r.Post("/api/admin/users", srv.AdminCreateUser)
		r.Patch("/api/admin/users/{id}/family", srv.AdminAssignUser)
		r.Patch("/api/admin/users/{id}/role", srv.AdminUpdateUserRole)
		r.Patch("/api/admin/users/{id}/password", srv.AdminResetUserPassword)
		r.Get("/api/admin/places", srv.AdminListPlaces)
		r.Get("/api/admin/invites", srv.AdminListInvites)
		r.Post("/api/admin/invites", srv.AdminCreateInvite)

		r.Get("/api/admin/apk", srv.AdminDownloadAPK)
		r.Post("/api/admin/apk/build", srv.AdminBuildAPK)
		r.Get("/api/admin/apk/status", srv.AdminAPKStatus)
	})

	// Admin web panel (embedded static SPA) at /admin/*, served public. The page
	// loads unauthenticated and the client authenticates against the /api/admin/*
	// API above. The API lives under a separate /api/admin/* prefix, so it never
	// collides with this /admin/* catch-all. Unknown paths fall back to index.html
	// for client-side routing.
	adminFS, err := fs.Sub(web.Dist, "dist")
	if err != nil {
		slog.Error("admin web embed failed", "err", err)
		os.Exit(1)
	}
	adminIndex, err := web.Dist.ReadFile("dist/index.html")
	if err != nil {
		slog.Error("admin web index.html missing from embed", "err", err)
		os.Exit(1)
	}
	adminStatic := adminStaticHandler(adminFS, adminIndex)
	r.Get("/admin", adminIndexHandler(adminIndex))
	r.Get("/admin/", adminIndexHandler(adminIndex))
	r.Get("/admin/*", adminStatic)

	httpServer := &http.Server{
		Addr:              cfg.HTTPAddr,
		Handler:           r,
		ReadHeaderTimeout: 10 * time.Second,
	}

	go func() {
		if cfg.TLSCertFile != "" && cfg.TLSKeyFile != "" {
			slog.Info("listening (https)", "addr", cfg.HTTPAddr)
			if err := httpServer.ListenAndServeTLS(cfg.TLSCertFile, cfg.TLSKeyFile); err != nil && !errors.Is(err, http.ErrServerClosed) {
				slog.Error("server error", "err", err)
				stop()
			}
			return
		}
		slog.Info("listening (http)", "addr", cfg.HTTPAddr)
		if err := httpServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			slog.Error("server error", "err", err)
			stop()
		}
	}()

	<-ctx.Done()
	slog.Info("shutting down")

	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_ = httpServer.Shutdown(shutdownCtx)
}

// cors adds a permissive CORS policy for the configured origin (or none).
func cors(allowedOrigin string) func(http.Handler) http.Handler {
	return func(next http.Handler) http.Handler {
		return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if allowedOrigin != "" {
				w.Header().Set("Access-Control-Allow-Origin", allowedOrigin)
				w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
				w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
			}
			if r.Method == http.MethodOptions {
				w.WriteHeader(http.StatusNoContent)
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}

// adminIndexHandler serves the embedded admin index.html (for /admin and
// /admin/). The body is pre-read so it does not re-read the embed per request.
func adminIndexHandler(index []byte) http.HandlerFunc {
	return func(w http.ResponseWriter, _ *http.Request) {
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		_, _ = w.Write(index)
	}
}

// adminStaticHandler serves the embedded admin SPA assets at /admin/*, with a
// fallback to index.html for unknown paths (client-side routing). Existing
// files are served via http.FileServerFS; missing files return index.html so
// the SPA can take over the path. The admin API lives under /api/admin/* (a
// separate prefix), so it is never matched by this /admin/* wildcard.
func adminStaticHandler(fsys fs.FS, index []byte) http.HandlerFunc {
	fileServer := http.StripPrefix("/admin/", http.FileServerFS(fsys))
	return func(w http.ResponseWriter, r *http.Request) {
		// Sub-path below /admin/ (chi wildcard already ensured we are here).
		p := strings.TrimPrefix(r.URL.Path, "/admin/")
		if p == "" {
			w.Header().Set("Content-Type", "text/html; charset=utf-8")
			_, _ = w.Write(index)
			return
		}
		if fi, err := fs.Stat(fsys, p); err == nil && !fi.IsDir() {
			fileServer.ServeHTTP(w, r)
			return
		}
		// SPA fallback for unknown paths.
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		_, _ = w.Write(index)
	}
}
