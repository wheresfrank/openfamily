// Package models defines the core domain types shared across the API.
package models

import "time"

// Role is a user's permission level within a family.
type Role string

const (
	RoleAdmin  Role = "admin"
	RoleMember Role = "member"
	RoleChild  Role = "child"
)

// Valid reports whether r is a known role.
func (r Role) Valid() bool {
	switch r {
	case RoleAdmin, RoleMember, RoleChild:
		return true
	}
	return false
}

// Family groups users, devices, places, and geofences.
type Family struct {
	ID        string          `json:"id"`
	Name      string          `json:"name"`
	Settings  map[string]any  `json:"settings"`
	CreatedAt time.Time       `json:"created_at"`
}

// User is an account. A user belongs to at most one family.
type User struct {
	ID           string     `json:"id"`
	FamilyID     *string    `json:"family_id,omitempty"`
	Email        string     `json:"email"`
	Name         string     `json:"name"`
	Role         Role       `json:"role"`
	PasswordHash string     `json:"-"`
	TOTPSecret   string     `json:"-"`
	TOTPEnabled  bool       `json:"totp_enabled"`
	CreatedAt    time.Time  `json:"created_at"`
	UpdatedAt    time.Time  `json:"updated_at"`
}

// MemberWithLocation is a family member joined to their latest location (if
// any). It embeds User for the identity fields and adds nullable location
// fields; a member who has never reported a location has null lat/lon/ts.
type MemberWithLocation struct {
	User
	Lat            *float64   `json:"lat,omitempty"`
	Lon            *float64   `json:"lon,omitempty"`
	TS             *time.Time `json:"ts,omitempty"`
	BatteryPct     *float64   `json:"battery_pct,omitempty"`
	SpeedMPS       *float64   `json:"speed_mps,omitempty"`
	MotionState    *string    `json:"motion_state,omitempty"`
	AccuracyMeters *float64   `json:"accuracy_meters,omitempty"`
}

// Device is a phone/tablet that reports location for a user.
type Device struct {
	ID                 string     `json:"id"`
	UserID             string     `json:"user_id"`
	Platform           string     `json:"platform"` // ios | android | web
	Name               string     `json:"name"`
	PushToken          string     `json:"-"`
	UnifiedPushEndpoint string    `json:"-"`
	LastSeen           *time.Time `json:"last_seen,omitempty"`
	AppVersion         string     `json:"app_version,omitempty"`
	CreatedAt          time.Time  `json:"created_at"`
}

// Location is a single reported position point.
type Location struct {
	DeviceID       string    `json:"device_id"`
	TS             time.Time `json:"ts"`
	Lat            float64   `json:"lat"`
	Lon            float64   `json:"lon"`
	AccuracyMeters *float64  `json:"accuracy_meters,omitempty"`
	AltitudeMeters *float64  `json:"altitude_meters,omitempty"`
	SpeedMPS       *float64  `json:"speed_mps,omitempty"`
	HeadingDeg     *float64  `json:"heading_deg,omitempty"`
	BatteryPct     *float64  `json:"battery_pct,omitempty"`
	MotionState    string    `json:"motion_state,omitempty"`
	Source         string    `json:"source,omitempty"`
}

// Place is a named point of interest (home, school, work, custom).
type Place struct {
	ID           string  `json:"id"`
	FamilyID     string  `json:"family_id"`
	Name         string  `json:"name"`
	Type         string  `json:"type"`
	Lat          float64 `json:"lat"`
	Lon          float64 `json:"lon"`
	RadiusMeters *float64 `json:"radius_meters,omitempty"`
	CreatedAt    time.Time `json:"created_at"`
}

// Geofence links a place to a user with enter/exit notification flags.
type Geofence struct {
	ID          string    `json:"id"`
	FamilyID    string    `json:"family_id"`
	PlaceID     *string   `json:"place_id,omitempty"`
	UserID      *string   `json:"user_id,omitempty"`
	EnterNotify bool      `json:"enter_notify"`
	ExitNotify  bool      `json:"exit_notify"`
	Enabled     bool      `json:"enabled"`
	CreatedAt   time.Time `json:"created_at"`
}
