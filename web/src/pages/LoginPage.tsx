// Login screen — split layout with a branded gradient panel and a clean form.
// Shown when the user is not authenticated.

import React from 'react'
import { login } from '../lib/api'
import { setTokens, setEmail as setSessionEmail } from '../lib/auth'
import { Button, Spinner } from '../components/primitives'
import './LoginPage.css'

interface LoginPageProps {
  onLoggedIn: () => void
}

export function LoginPage({ onLoggedIn }: LoginPageProps) {
  const [email, setEmail] = React.useState('')
  const [password, setPassword] = React.useState('')
  const [submitting, setSubmitting] = React.useState(false)
  const [error, setError] = React.useState<string | null>(null)
  const formRef = React.useRef<HTMLFormElement>(null)

  const submit = async (e: React.FormEvent) => {
    e.preventDefault()
    if (submitting) return
    setError(null)
    setSubmitting(true)
    try {
      const tokens = await login(email.trim(), password)
      setTokens(tokens)
      setSessionEmail(email.trim())
      onLoggedIn()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Sign in failed')
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div className="wb-login">
      <aside className="wb-login-aside">
        <div className="wb-login-brand">
          <span className="wb-login-mark" aria-hidden="true">
            <svg width="28" height="28" viewBox="0 0 24 24" fill="none">
              <path
                d="M12 2.5c4.4 0 8 3.5 8 7.8 0 5.6-8 11.2-8 11.2s-8-5.6-8-11.2c0-4.3 3.6-7.8 8-7.8Z"
                fill="#fff"
              />
              <circle cx="12" cy="10.3" r="2.7" fill="#6c2bd9" />
            </svg>
          </span>
          <span className="wb-login-wordmark">Whereabouts</span>
        </div>
        <div className="wb-login-aside-body">
          <h2 className="wb-login-aside-title">Self-hosted family location, in your control.</h2>
          <p className="wb-login-aside-text">
            Manage groups, oversee members, and build the Android app — all from
            one admin console.
          </p>
        </div>
        <div className="wb-login-aside-foot">Whereabouts Admin · v0.1</div>
      </aside>

      <main className="wb-login-main">
        <div className="wb-login-card">
          <h1 className="wb-login-h1">Sign in</h1>
          <p className="wb-login-sub">Use your administrator account to continue.</p>

          <form ref={formRef} onSubmit={submit} className="wb-login-form" noValidate>
            <div className="wb-field">
              <label className="wb-label" htmlFor="wb-email">
                Email
              </label>
              <input
                id="wb-email"
                className="wb-input"
                type="email"
                autoComplete="username"
                placeholder="you@example.com"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                required
                autoFocus
              />
            </div>

            <div className="wb-field">
              <label className="wb-label" htmlFor="wb-password">
                Password
              </label>
              <input
                id="wb-password"
                className="wb-input"
                type="password"
                autoComplete="current-password"
                placeholder="••••••••"
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                required
              />
            </div>

            {error && (
              <div className="wb-login-error" role="alert">
                <svg width="16" height="16" viewBox="0 0 24 24" fill="none" aria-hidden="true">
                  <path
                    d="M12 8v5m0 3.5h.01M10.3 3.9 2.7 17a2 2 0 0 0 1.7 3h15.2a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0Z"
                    stroke="currentColor"
                    strokeWidth="1.6"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                  />
                </svg>
                <span>{error}</span>
              </div>
            )}

            <Button type="submit" disabled={submitting} className="wb-login-submit">
              {submitting ? (
                <>
                  <Spinner size={16} /> Signing in…
                </>
              ) : (
                'Sign in'
              )}
            </Button>
          </form>

          <p className="wb-login-footnote">
            Don’t have an account? Ask your server administrator to provision one.
          </p>
        </div>
      </main>
    </div>
  )
}