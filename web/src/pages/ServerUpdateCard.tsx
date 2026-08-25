import React from 'react'
import { ApiError, applyServerUpdate, getUpdateLog, getUpdateStatus } from '../lib/api'
import type { UpdateStatus } from '../lib/types'
import { Badge, Button, Card, Mono } from '../components/primitives'

const POLL_INTERVAL_MS = 3000

type CardMessage = { tone: 'success' | 'error'; text: string } | null

function messageFromError(error: unknown, fallback: string): string {
  if (error instanceof ApiError) return error.message || fallback
  if (error instanceof Error) return error.message || fallback
  return fallback
}

function RefChip({ label, value }: { label: string; value?: string }) {
  const displayValue = value === 'dev' ? undefined : value
  return (
    <div className="wb-update-ref">
      <span className="wb-update-ref-label">{label}</span>
      {displayValue ? (
        <Mono truncate="none">{displayValue}</Mono>
      ) : (
        <span className="wb-update-ref-unknown">Not reported</span>
      )}
    </div>
  )
}

/** Server version comparison and automatic update controls for platform admins. */
export function ServerUpdateCard() {
  const [status, setStatus] = React.useState<UpdateStatus | null>(null)
  const [loading, setLoading] = React.useState(true)
  const [checking, setChecking] = React.useState(false)
  const [starting, setStarting] = React.useState(false)
  const [confirming, setConfirming] = React.useState(false)
  const [log, setLog] = React.useState<string | null>(null)
  const [message, setMessage] = React.useState<CardMessage>(null)
  const [lastChecked, setLastChecked] = React.useState<Date | null>(null)

  const running = status?.busy || status?.job?.status === 'running'

  const refresh = React.useCallback(async (): Promise<UpdateStatus | null> => {
    try {
      const next = await getUpdateStatus()
      setStatus(next)
      setLastChecked(new Date())
      setMessage(null)
      return next
    } catch (error) {
      setMessage({ tone: 'error', text: messageFromError(error, 'Could not load update status.') })
      return null
    }
  }, [])

  React.useEffect(() => {
    void refresh().finally(() => setLoading(false))
  }, [refresh])

  React.useEffect(() => {
    if (!running) return
    const id = window.setInterval(() => {
      void refresh()
      void getUpdateLog().then(setLog).catch(() => setLog(null))
    }, POLL_INTERVAL_MS)
    return () => window.clearInterval(id)
  }, [running, refresh])

  const checkNow = async () => {
    setChecking(true)
    try {
      await refresh()
    } finally {
      setChecking(false)
    }
  }

  const startUpdate = async () => {
    setStarting(true)
    try {
      await applyServerUpdate()
      setMessage({ tone: 'success', text: 'Update started. This can take several minutes; keep this page open.' })
      setConfirming(false)
      const next = await refresh()
      if (next?.busy) void getUpdateLog().then(setLog).catch(() => setLog(null))
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
    if (loading || (!status && !message)) return <Badge tone="neutral">Checking…</Badge>
    if (running) return <Badge tone="orange" dot>Updating</Badge>
    if (!status) return <Badge tone="red">Unavailable</Badge>
    if (status.check_error) return <Badge tone="grey">Check failed</Badge>
    if (status.update_available) return <Badge tone="purple" dot>Update available</Badge>
    if (status.deployed_ref && status.deployed_ref !== 'dev') return <Badge tone="green" dot>Up to date</Badge>
    return <Badge tone="neutral">Unknown version</Badge>
  })()

  const job = status?.job
  const lastRun = job && job.status !== 'idle' && job.status !== 'running' ? job : null

  return (
    <Card className="wb-update-card">
      <div className="wb-update-header">
        <div className="wb-update-heading">
          <span className="wb-update-icon" aria-hidden="true"><UpdateIcon /></span>
          <div>
            <h3 className="wb-settings-title">Server updates</h3>
            <p className="wb-settings-section-help">Compare this server with the latest source release.</p>
          </div>
        </div>
        <div className="wb-update-badge">{badge}</div>
      </div>

      {message && (
        <div
          className={message.tone === 'success' ? 'wb-update-message wb-update-message-success' : 'wb-profile-load-error'}
          role={message.tone === 'success' ? 'status' : 'alert'}
        >
          {message.text}
        </div>
      )}

      <div className="wb-update-refs">
        <RefChip label="Running version" value={status?.deployed_ref} />
        <span className="wb-update-ref-arrow" aria-hidden="true">→</span>
        <RefChip label="Latest version" value={status?.latest_ref} />
      </div>

      {status?.check_error && (
        <p className="wb-error-text" role="alert">
          Could not reach GitHub to check for a newer version ({status.check_error}).
        </p>
      )}

      {!status?.can_update && !loading && (
        <p className="wb-update-note">
          Automatic installation is unavailable on this deployment. Install the latest version from the server host, then check again.
        </p>
      )}

      {lastRun && !running && (
        <p className={lastRun.status === 'success' ? 'wb-update-note' : 'wb-error-text'} role={lastRun.status === 'success' ? undefined : 'alert'}>
          Last update {lastRun.status === 'success' ? 'succeeded' : lastRun.status === 'interrupted' ? 'was interrupted' : 'failed'}
          {lastRun.previous_ref && lastRun.new_ref ? ` (${lastRun.previous_ref} → ${lastRun.new_ref})` : ''}
          {lastRun.error ? `: ${lastRun.error}` : '.'}{' '}
          {lastRun.status === 'interrupted' && 'Verify container health, then run the update again.'}
          {lastRun.status === 'failed' && 'See the log below for details.'}
          {lastRun.status === 'success' && 'The API restarted onto the new build.'}
        </p>
      )}

      <div className="wb-update-footer">
        <span className="wb-update-check-time">
          {lastChecked
            ? `Checked ${lastChecked.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}`
            : 'Checking version…'}
        </span>
        <div className="wb-settings-form-actions">
          <Button variant="secondary" size="sm" loading={checking} onClick={() => void checkNow()}>
            Check again
          </Button>
          {status?.can_update && (confirming ? (
            <>
              <Button variant="danger" size="sm" loading={starting} onClick={() => void startUpdate()}>
                Confirm update
              </Button>
              <Button variant="ghost" size="sm" disabled={starting} onClick={() => setConfirming(false)}>
                Cancel
              </Button>
            </>
          ) : (
            <Button
              variant="primary"
              size="sm"
              disabled={running || !status.update_available}
              onClick={() => setConfirming(true)}
              title={status.update_available ? undefined : 'No newer commit detected'}
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
      </div>

      {running && (
        <p className="wb-update-note" role="status">
          Update in progress — source pull and image rebuild are running. This page reconnects automatically.
        </p>
      )}

      {log !== null && <pre className="wb-update-log">{log}</pre>}
    </Card>
  )
}

function UpdateIcon() {
  return (
    <svg width="20" height="20" viewBox="0 0 24 24" fill="none">
      <path d="M12 16V4m0 0L8 8m4-4 4 4M5 15v3a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-3" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}
