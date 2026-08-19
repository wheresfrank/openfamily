// Package web embeds the platform-admin static frontend served at /admin/.
//
// The real frontend is built separately (see the top-level web/ project) and
// its production bundle is dropped into backend/web/dist/. This package
// embeds that directory via go:embed so the single server binary serves the
// admin panel with no external file dependencies. A minimal placeholder
// index.html is committed so the route works before the real bundle exists;
// the real build overwrites dist/ with no code change required here.
package web

import "embed"

// Dist is the embedded admin frontend directory. Files are served at /admin/*
// by the server. Use fs.Sub to strip the "dist" prefix when serving.
//
//go:embed dist
var Dist embed.FS
