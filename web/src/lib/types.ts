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

/** The authenticated user's account details. */
export interface Profile {
  id: string
  name: string
  email: string
  role: Role
  has_avatar: boolean
  avatar_updated_at: string | null
}

export interface Family {
  id: string
  name: string
  created_at: string
  member_count: number
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
  family_id: string
  family_name: string
}

/** Invite code as returned by the admin invite endpoints. */
export interface InviteCode {
  id: string
  code: string
  family_id: string
  created_by: string | null
  role: Role
  max_uses: number
  uses: number
  expires_at: string | null
  created_at: string
}

/** Invite code tagged with its family name (GET /api/admin/invites). */
export interface AdminInvite extends InviteCode {
  family_name: string
}

/** Discriminated result for the API client. */
export type ApiResult<T> =
  | { ok: true; value: T }
  | { ok: false; status: number; message: string }
