// Shared API types for the Whereabouts admin panel.
// Mirrors the backend contract documented in the task brief.

export type Role = 'admin' | 'member' | 'child'

export type MotionState =
  | 'stationary'
  | 'walking'
  | 'running'
  | 'cycling'
  | 'driving'
  | 'unknown'

export interface LoginResponse {
  access_token: string
  refresh_token: string
  token_type: string
  expires_in: number
}

export interface Family {
  id: string
  name: string
  created_at: string
  member_count: number
}

export interface AdminUser {
  id: string
  family_id: string | null
  family_name: string | null
  email: string
  name: string
  role: Role
  platform_admin: boolean
  created_at: string
  updated_at: string
}

export interface Member {
  id: string
  name: string
  email: string
  role: Role
  lat: number | null
  lon: number | null
  ts: string | null
  battery_pct: number | null
  speed_mps: number | null
  motion_state: MotionState | null
  accuracy_meters: number | null
}

/** Member as returned by GET /api/admin/members — tagged with its family. */
export interface AdminMember extends Member {
  family_id: string | null
  family_name: string | null
}

/** Discriminated result for the API client. */
export type ApiResult<T> =
  | { ok: true; value: T }
  | { ok: false; status: number; message: string }