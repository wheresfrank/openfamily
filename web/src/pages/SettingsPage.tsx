// Settings page — server info, the signed-in account, and a sign-out action.
// Read-only for the shell; further settings hooks land with the backend.

import { getAccessToken } from '../lib/auth'
import { Button, Card, CopyButton, Mono } from '../components/primitives'
import './pages.css'
import './SettingsPage.css'

interface SettingsPageProps {
  email: string | null
  onLogout: () => void
}

export function SettingsPage({ email, onLogout }: SettingsPageProps) {
  const token = getAccessToken()

  return (
    <div className="wb-page">
      <div className="wb-page-header">
        <div>
          <h1 className="wb-page-title">Settings</h1>
          <p className="wb-page-subtitle">Account and server configuration.</p>
        </div>
      </div>

      <div className="wb-settings-grid">
        <Card>
          <h3 className="wb-settings-title">Account</h3>
          <dl className="wb-settings-list">
            <div>
              <dt>Email</dt>
              <dd>{email ?? '—'}</dd>
            </div>
            <div>
              <dt>Role</dt>
              <dd>Administrator</dd>
            </div>
            <div>
              <dt>Session token</dt>
              <dd className="wb-settings-mono">
                {token ? <Mono truncate="middle" max={20}>{token}</Mono> : '—'}
                {token && <CopyButton value={token} label="Copy session token" />}
              </dd>
            </div>
          </dl>
          <div className="wb-settings-actions">
            <Button variant="danger" onClick={onLogout}>
              Sign out
            </Button>
          </div>
        </Card>

        <Card>
          <h3 className="wb-settings-title">Server</h3>
          <dl className="wb-settings-list">
            <div>
              <dt>API base</dt>
              <dd className="wb-settings-mono"><Mono>/api</Mono></dd>
            </div>
            <div>
              <dt>WebSocket</dt>
              <dd className="wb-settings-mono"><Mono>/ws/stream</Mono></dd>
            </div>
            <div>
              <dt>Build</dt>
              <dd>v0.1</dd>
            </div>
          </dl>
          <p className="wb-settings-note">
            More settings — member invitations, family management, and feature
            flags — will appear here as the backend grows.
          </p>
        </Card>
      </div>
    </div>
  )
}