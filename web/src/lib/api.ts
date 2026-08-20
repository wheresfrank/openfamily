// API client — a small fetch wrapper that injects the Bearer token, handles
// 401 with a single refresh attempt, and normalizes errors into ApiResult.

import { clearTokens, getAccessToken, getRefreshToken, setTokens } from './auth'
import type {
  AdminInvite,
  AdminMember,
  ApiResult,
  Family,
  InviteCode,
  LoginResponse,
  Member,
  Role,
} from './types'

const API_BASE = '/api'
const AUTH_BASE = '/auth'

export class ApiError extends Error {
  status: number
  constructor(status: number, message: string) {
    super(message)
    this.status = status
    this.name = 'ApiError'
  }
}

/** Special status meaning "auth required and refresh failed" — handled upstream. */
export const REDIRECT_TO_LOGIN = 'REDIRECT_TO_LOGIN'
export class RedirectToLogin extends Error {
  constructor() {
    super(REDIRECT_TO_LOGIN)
    this.name = 'RedirectToLogin'
  }
}

async function refreshTokens(): Promise<boolean> {
  const refreshToken = getRefreshToken()
  if (!refreshToken) return false
  try {
    const res = await fetch(`${AUTH_BASE}/refresh`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ refresh_token: refreshToken }),
    })
    if (!res.ok) return false
    const tokens = (await res.json()) as LoginResponse
    setTokens(tokens)
    return true
  } catch {
    return false
  }
}

interface RequestOptions {
  method?: string
  body?: unknown
  /** Set to true to skip the auth header (used by login itself). */
  noAuth?: boolean
  /** Expect a binary response instead of JSON. */
  binary?: boolean
}

async function request<T>(path: string, opts: RequestOptions = {}): Promise<T> {
  const headers: Record<string, string> = {
    Accept: 'application/json',
  }
  if (opts.body !== undefined) headers['Content-Type'] = 'application/json'
  if (!opts.noAuth) {
    const token = getAccessToken()
    if (token) headers.Authorization = `Bearer ${token}`
  }

  const doFetch = (): Promise<Response> =>
    fetch(path.startsWith('http') ? path : `${path.startsWith('/api') || path.startsWith('/auth') ? '' : API_BASE}${path}`, {
      method: opts.method ?? 'GET',
      headers,
      body: opts.body !== undefined ? JSON.stringify(opts.body) : undefined,
    })

  let res = await doFetch()

  // 401 — try one refresh, then replay once.
  if (res.status === 401 && !opts.noAuth) {
    const refreshed = await refreshTokens()
    if (refreshed) {
      const token = getAccessToken()
      if (token) headers.Authorization = `Bearer ${token}`
      res = await doFetch()
    } else {
      clearTokens()
      throw new RedirectToLogin()
    }
  }

  if (!res.ok) {
    let message = res.statusText || 'Request failed'
    try {
      const body = await res.json()
      if (body && typeof body === 'object' && 'message' in body) {
        message = String((body as { message: unknown }).message)
      } else if (body && typeof body === 'object' && 'error' in body) {
        message = String((body as { error: unknown }).error)
      }
    } catch {
      // non-JSON error body — keep statusText
    }
    throw new ApiError(res.status, message)
  }

  if (opts.binary) {
    // Caller wants the raw blob.
    return (await res.blob()) as unknown as T
  }
  if (res.status === 204) return undefined as unknown as T
  return (await res.json()) as T
}

/** Wrap a call so a thrown ApiError becomes a structured ApiResult. */
export async function result<T>(p: Promise<T>): Promise<ApiResult<T>> {
  try {
    const value = await p
    return { ok: true, value }
  } catch (e) {
    if (e instanceof ApiError) {
      return { ok: false, status: e.status, message: e.message }
    }
    // Network / unexpected error.
    return { ok: false, status: 0, message: e instanceof Error ? e.message : 'Network error' }
  }
}

// ---- Auth ----

export async function login(email: string, password: string): Promise<LoginResponse> {
  return request<LoginResponse>('/auth/login', {
    method: 'POST',
    noAuth: true,
    body: { email, password },
  })
}

// ---- Admin endpoints ----

export function listFamilies(): Promise<Family[]> {
  return request<Family[]>('/api/admin/families')
}

export function listFamilyMembers(familyId: string): Promise<Member[]> {
  return request<Member[]>(`/api/admin/families/${encodeURIComponent(familyId)}/members`)
}

export function listAllMembers(): Promise<AdminMember[]> {
  return request<AdminMember[]>('/api/admin/members')
}

export function createFamily(name: string): Promise<Family> {
  return request<Family>('/api/admin/families', { method: 'POST', body: { name } })
}

export function renameFamily(familyId: string, name: string): Promise<{ status: string }> {
  return request<{ status: string }>(`/api/admin/families/${encodeURIComponent(familyId)}`, {
    method: 'PATCH',
    body: { name },
  })
}

export function deleteFamily(familyId: string): Promise<{ status: string }> {
  return request<{ status: string }>(`/api/admin/families/${encodeURIComponent(familyId)}`, {
    method: 'DELETE',
  })
}

export function moveMember(
  memberId: string,
  familyId: string,
  role?: Role,
): Promise<{ status: string }> {
  return request<{ status: string }>(`/api/admin/members/${encodeURIComponent(memberId)}/family`, {
    method: 'PATCH',
    body: { family_id: familyId, role },
  })
}

export function listInvites(): Promise<AdminInvite[]> {
  return request<AdminInvite[]>('/api/admin/invites')
}

export function createInvite(
  familyId: string,
  opts?: { role?: Role; max_uses?: number; expires_in_hours?: number },
): Promise<InviteCode> {
  return request<InviteCode>('/api/admin/invites', {
    method: 'POST',
    body: { family_id: familyId, ...opts },
  })
}

/** Returns a blob; caller should trigger a download. */
export function downloadApk(): Promise<Blob> {
  return request<Blob>('/api/admin/apk', { binary: true })
}