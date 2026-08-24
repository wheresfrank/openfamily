import React from 'react'
import { ApiError, applyServerUpdate, getUpdateLog, getUpdateStatus } from '../lib/api'
import type { UpdateStatus } from '../lib/types'
import { Badge, Button, Card, Mono } from '../components/primitives'

// Poll cadence while an update is running.
const POLL_INTERVAL_MS = 3000

type CardMessage = { tone: 'success' | 'error'; text: string } | null

function messageFromError(error: unknown, fallback: string): string {
  if (error instanceof ApiError) return error.message || fallback
  if (error instanceof Error) return error.message || fallback
  return fallback
}

function RefChip({ label, value }: { label: string; value?: string }) {
  return (
    <span className="wb-update-ref">
      <span className="wb-label">{label}</span>{' '}
      {value ? <Mono truncate="none">{value}</Mono> : <span className="wb-help">unknown</span>}
    </span>
  )
}

/**
 * ServerUpdateCard shows which server commit is running, whether a newer one
 * exists upstream, and — when the updater sidecar is configured and the shared
 * token matches — a button that pulls and rebuilds. While an update runs the
 * card polls status and streams the updater's log tail.
 *
 * Render only for platform admins (see SettingsPage).
 */
export function ServerUpdateCard() {
  const [status, setStatus] = React.useState<UpdateStatus | null>(null)
  const [loading, setLoading] = React.useState(true)
  const [checking, setChecking] = React.useState(false)
  const [starting, setStarting] = React.useState(false)
  const [confirming, setConfirming] = React.useState(false)
  const [log, setLog] = React.useState<string | null>(null)
  const [message, setMessage] = React.useState<CardMessage>(null)

  const running = status?.busy || status?.job?.status === 'running'

  const refresh = React.useCallback(async (): Promise<UpdateStatus | null> => {
    try {
      const next = await getUpdateStatus()
      setStatus(next)
      setMessage(null)
      return next
    } catch (error) {
      setMessage({
        tone: 'error',
        text: messageFromError(error, 'Could not load update status.'),
      })
      return null
    }
  }, [])

  React.useEffect(() => {
    void refresh().finally(() => setLoading(false))
  }, [refresh])

  // Poll while an update runs so the card follows it to completion.
  React.useEffect(() => {
    if (!running) return
    const id = window.setInterval(() => {
      void refresh()
      void getUpdateLog()
        .then(setLog)
        .catch(() => setLog(null))
    }, POLL_INTERVAL_MS)
    return () => window.clearInterval(id)
  }, [running, refresh])

  const checkNow = async () => {
    setChecking(true)
    await refresh()
    setChecking(false)
  }

  const startUpdate = async () => {
    setStarting(true)
    try {
      await applyServerUpdate()
      setMessage({ tone: 'success', text: 'Update started. This can take several minutes; keep this page open.' })
      setConfirming(false)
      const next = await refresh()
      if (next?.busy) {
        void getUpdateLog()
          .then(setLog)
          .catch(() => setLog(null))
      }
    } catch (error) {
      setMessage({ tone: 'error', text: messageFromError(error, 'Could not start the update.') })
    } finally {
      setStarting(false)
    }
  }

  const showLog = async () => {
    try {
      setLog(await getUpdateLog())
    } catch {
      setLog('Could not load the update log.')
    }
  }

  const badge = (() => {
    if (loading || (!status && !message)) return <Badge tone="neutral">…</Badge>
    if (running) return <Badge tone="orange" dot>Updating</Badge>
    if (!status) return <Badge tone="red">Unavailable</Badge>
    if (status.check_error) return <Badge tone="grey">Version check failed</Badge>
    if (status.update_available) return <Badge tone="purple" dot>Update available</Badge>
    if (status.deployed_ref) return <Badge tone="green" dot>Up to date</Badge>
    return <Badge tone="neutral">Unknown version</Badge>
  })()

  const job = status?.job
  const lastRun =
    job && job.status !== 'idle' && job.status !== 'running' ? job : null

  return (
    <Card className="wb-settings-section">
      <div className="wb-settings-title-row">
        <h3 className="wb-settings-title">Server updates</h3>
        {badge}
      </div>
      <p className="wb-settings-section-help">
        Running version compared against the latest commit on the project's source repository.
      </p>

      {message && (
        <div className={message.tone === 'success' ? 'wb-success-text' : 'wb-profile-load-error'} role="alert">
          {message.text}
        </div>
      )}

      <div className="wb-update-refs">
        <RefChip label="Running" value={status?.deployed_ref} />
        <RefChip label="Latest" value={status?.latest_ref} />
      </div>

      {status?.check_error && (
        <p className="wb-error-text" role="alert">
          Could not reach GitHub to check for a newer version ({status.check_error}).
        </p>
      )}

      {!status?.can_update && !loading && (
        <p className="wb-help">
          One-click updates are not enabled on this deployment (set UPDATER_TOKEN in .env).
          Update manually with <code>git pull</code> then <code>docker compose up -d --build</code>.
        </p>
      )}

      {lastRun && !running && (
        <p className={lastRun.status === 'success' ? 'wb-help' : 'wb-error-text'} role={lastRun.status === 'success' ? undefined : 'alert'}>
          Last update {lastRun.status === 'success' ? 'succeeded' : lastRun.status === 'interrupted' ? 'was interrupted' : 'failed'}
          {lastRun.previous_ref && lastRun.new_ref ? ` (${lastRun.previous_ref} → ${lastRun.new_ref})` : ''}
          {lastRun.error ? `: ${lastRun.error}` : '.'}
          {' '}
          {lastRun.status === 'interrupted' && 'Verify container health, then run the update again.'}
          {lastRun.status === 'failed' && ' See the log below for details.'}
          {lastRun.status === 'success' && ' The API restarted onto the new build; reload the panel to pick it up.'}
        </p>
      )}

      <div className="wb-settings-form-actions">
        <Button variant="secondary" size="sm" loading={checking} onClick={() => void checkNow()}>
          Check now
        </Button>
        {status?.can_update &&
          (confirming ? (
            <>
              <Button variant="danger" size="sm" loading={starting} onClick={() => void startUpdate()}>
                Confirm: pull &amp; rebuild
              </Button>
              <Button variant="ghost" size="sm" disabled={starting} onClick={() => setConfirming(false)}>
                Cancel
              </Button>
            </>
          ) : (
            <Button
              variant="primary"
              size="sm"
              disabled={!running && !status.update_available}
              onClick={() => setConfirming(true)}
              title={
                status.update_available
                  ? undefined
                  : 'No newer commit detected'
              }
            >
              Update now
            </Button>
          ))}
        {log !== null && (
          <Button variant="ghost" size="sm" onClick={() => void showLog()} disabled={running}>
            Refresh log
          </Button>
        )}
        {status?.can_update && log === null && !loading && (
          <Button variant="ghost" size="sm" onClick={() => void showLog()}>
            View update log
          </Button>
        )}
      </div>

      {running && (
        <p className="wb-help" role="status">
          Update in progress — git pull and image rebuild are running. The API will restart when
          finished; this page reconnects automatically.
        </p>
      )}

      {log !== null && <pre className="wb-update-log">{log}</pre>}
    </Card>
  )
}
