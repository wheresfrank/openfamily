// Command server runs the Whereabouts API.
package main

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
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
	srv.AllowedOrigin = cfg.AllowedOrigin

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

	// Auth (unauthenticated).
	r.Post("/auth/register", srv.Register)
	r.Post("/auth/login", srv.Login)
	r.Post("/auth/refresh", srv.Refresh)

	// WebSocket stream (authenticates via Bearer header or Sec-WebSocket-Protocol subprotocol).
	r.Get("/ws/stream", srv.Stream)

	// Authenticated API.
	r.Group(func(r chi.Router) {
		r.Use(mid.RequireAuth(tm))

		r.Post("/families", srv.CreateFamily)
		r.Get("/family", srv.GetFamily)
		r.Get("/family/members", srv.ListMembers)
		r.Patch("/family/members/{id}/role", srv.UpdateMemberRole)

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

		r.Post("/locations", srv.IngestLocation)
	})

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
				w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PATCH, DELETE, OPTIONS")
			}
			if r.Method == http.MethodOptions {
				w.WriteHeader(http.StatusNoContent)
				return
			}
			next.ServeHTTP(w, r)
		})
	}
}
