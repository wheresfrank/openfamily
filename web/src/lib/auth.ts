// Auth store — persists tokens in localStorage and exposes a tiny reactive
// subscription so the App can re-render on login/logout.

import type { LoginResponse } from './types'

const ACCESS_KEY = 'wb_access_token'
const REFRESH_KEY = 'wb_refresh_token'
const EMAIL_KEY = 'wb_email'

type Listener = () => void

const listeners = new Set<Listener>()

function emit(): void {
  listeners.forEach((l) => l())
}

export function getAccessToken(): string | null {
  try {
    return localStorage.getItem(ACCESS_KEY)
  } catch {
    return null
  }
}

export function getRefreshToken(): string | null {
  try {
    return localStorage.getItem(REFRESH_KEY)
  } catch {
    return null
  }
}

export function setTokens(tokens: LoginResponse): void {
  try {
    localStorage.setItem(ACCESS_KEY, tokens.access_token)
    localStorage.setItem(REFRESH_KEY, tokens.refresh_token)
  } catch {
    // storage may be unavailable (private mode) — non-fatal
  }
  emit()
}

export function setEmail(email: string): void {
  try {
    localStorage.setItem(EMAIL_KEY, email)
  } catch {
    // ignore
  }
  emit()
}

export function getEmail(): string | null {
  try {
    return localStorage.getItem(EMAIL_KEY)
  } catch {
    return null
  }
}

export function clearTokens(): void {
  try {
    localStorage.removeItem(ACCESS_KEY)
    localStorage.removeItem(REFRESH_KEY)
    localStorage.removeItem(EMAIL_KEY)
  } catch {
    // ignore
  }
  emit()
}

export function isAuthenticated(): boolean {
  return getAccessToken() !== null
}

export function subscribeAuth(listener: Listener): () => void {
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
}

// Cross-tab logout: if another tab clears tokens, this tab reacts too.
if (typeof window !== 'undefined') {
  window.addEventListener('storage', (e) => {
    if (e.key === ACCESS_KEY || e.key === REFRESH_KEY || e.key === EMAIL_KEY) emit()
  })
}