// Builds / APK page — shows build status, lets the admin trigger a build,
// and download the finished APK. Polls status while building.

import React from 'react'
import { downloadApk, getApkStatus, triggerApkBuild, ApiError } from '../lib/api'
import { isAccessDenied, useAsync } from '../lib/useAsync'
import { AccessDenied, Badge, Button, Card, CopyButton, Spinner } from '../components/primitives'
import { formatDate, formatRelativeTime } from '../lib/format'
import type { ApkStatusKind } from '../lib/types'
import './pages.css'
import './BuildsPage.css'

export function BuildsPage() {
  const status = useAsync(getApkStatus, [])
  const [building, setBuilding] = React.useState(false)
  const [actionError, setActionError] = React.useState<string | null>(null)
  const [downloadState, setDownloadState] = React.useState<'idle' | 'downloading' | 'done' | 'error'>('idle')
  const pollRef = React.useRef<number | null>(null)

  // Poll while status is 'building'.
  React.useEffect(() => {
    const current = status.data?.status
    if (current !== 'building' && !building) {
      if (pollRef.current) {
        window.clearInterval(pollRef.current)
        pollRef.current = null
      }
      return
    }
    if (!pollRef.current) {
      pollRef.current = window.setInterval(() => {
        status.refetch()
      }, 3000)
    }
    return () => {
      if (pollRef.current) {
        window.clearInterval(pollRef.current)
        pollRef.current = null
      }
    }
  }, [status.data?.status, building, status])

  if (status.loading) return <BuildsSkeleton />
  if (isAccessDenied(status.error)) {
    return (
      <div className="wb-page">
        <AccessDenied />
      </div>
    )
  }
  if (status.error) {
    return (
      <div className="wb-page">
        <div className="wb-page-header">
          <div>
            <h1 className="wb-page-title">Builds</h1>
            <p className="wb-page-subtitle">Generate and download the Android APK.</p>
          </div>
        </div>
        <Card>
          <p className="wb-error-text">{status.error.message}</p>
          <div style={{ marginTop: 12 }}>
            <Button variant="secondary" size="sm" onClick={status.refetch}>
              Try again
            </Button>
          </div>
        </Card>
      </div>
    )
  }

  const current = status.data
  const isBuilding = current?.status === 'building' || building

  const triggerBuild = async () => {
    setActionError(null)
    setBuilding(true)
    try {
      await triggerApkBuild()
      status.refetch()
    } catch (e) {
      setActionError(e instanceof ApiError ? e.message : 'Build failed to start')
    } finally {
      setBuilding(false)
    }
  }

  const download = async () => {
    setActionError(null)
    setDownloadState('downloading')
    try {
      const blob = await downloadApk()
      const url = URL.createObjectURL(blob)
      const a = document.createElement('a')
      a.href = url
      a.download = 'whereabouts.apk'
      document.body.appendChild(a)
      a.click()
      a.remove()
      URL.revokeObjectURL(url)
      setDownloadState('done')
    } catch (e) {
      setActionError(e instanceof ApiError ? e.message : 'Download failed')
      setDownloadState('error')
    }
  }

  return (
    <div className="wb-page">
      <div className="wb-page-header">
        <div>
          <h1 className="wb-page-title">Builds</h1>
          <p className="wb-page-subtitle">Generate and download the Android APK.</p>
        </div>
      </div>

      <div className="wb-builds-grid">
        <Card>
          <div className="wb-build-status">
            <div className="wb-build-status-head">
              <h3 className="wb-build-status-title">Current build</h3>
              <StatusBadge status={current?.status ?? 'idle'} />
            </div>

            <dl className="wb-build-meta">
              <div>
                <dt>Status</dt>
                <dd>{statusLabel(current?.status ?? 'idle')}</dd>
              </div>
              <div>
                <dt>Last finished</dt>
                <dd>{current?.finished_at ? formatRelativeTime(current.finished_at) : '—'}</dd>
              </div>
              {current?.error && (
                <div className="wb-build-error-row">
                  <dt>Error</dt>
                  <dd>{current.error}</dd>
                </div>
              )}
            </dl>

            {isBuilding && (
              <div className="wb-build-progress">
                <Spinner size={14} />
                <span>Building… this can take a few minutes.</span>
              </div>
            )}

            <div className="wb-build-actions">
              <Button onClick={triggerBuild} disabled={isBuilding} loading={building}>
                {isBuilding ? 'Building…' : 'Trigger build'}
              </Button>
              <Button
                variant="secondary"
                onClick={download}
                disabled={current?.status !== 'success' || downloadState === 'downloading'}
                loading={downloadState === 'downloading'}
                icon={<DownloadIcon />}
              >
                {downloadState === 'downloading' ? 'Downloading…' : 'Download APK'}
              </Button>
            </div>

            {actionError && <p className="wb-error-text" style={{ marginTop: 12 }}>{actionError}</p>}
          </div>
        </Card>

        <Card>
          <h3 className="wb-build-info-title">About APK builds</h3>
          <p className="wb-build-info-text">
            Triggering a build compiles the Flutter app into a release APK on the
            server. Builds run in the background — keep this page open and the
            status will refresh automatically.
          </p>
          <ul className="wb-build-info-list">
            <li>
              <span className="wb-build-info-k">Endpoint</span>
              <code className="wb-build-info-code">POST /api/admin/apk/build</code>
              <CopyButton value="POST /api/admin/apk/build" label="Copy build endpoint" />
            </li>
            <li>
              <span className="wb-build-info-k">Status</span>
              <code className="wb-build-info-code">GET /api/admin/apk/status</code>
              <CopyButton value="GET /api/admin/apk/status" label="Copy status endpoint" />
            </li>
            <li>
              <span className="wb-build-info-k">Download</span>
              <code className="wb-build-info-code">GET /api/admin/apk</code>
              <CopyButton value="GET /api/admin/apk" label="Copy download endpoint" />
            </li>
          </ul>
          {current?.finished_at && (
            <p className="wb-build-info-foot">
              Last build completed {formatDate(current.finished_at)}.
            </p>
          )}
        </Card>
      </div>
    </div>
  )
}

function StatusBadge({ status }: { status: ApkStatusKind }) {
  switch (status) {
    case 'success':
      return (
        <Badge tone="green" dot>
          Success
        </Badge>
      )
    case 'building':
      return (
        <Badge tone="purple" dot>
          Building
        </Badge>
      )
    case 'failed':
      return (
        <Badge tone="red" dot>
          Failed
        </Badge>
      )
    default:
      return (
        <Badge tone="grey" dot>
          Idle
        </Badge>
      )
  }
}

function statusLabel(status: ApkStatusKind): string {
  switch (status) {
    case 'success':
      return 'Build ready'
    case 'building':
      return 'Build in progress'
    case 'failed':
      return 'Build failed'
    default:
      return 'No active build'
  }
}

function DownloadIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <path
        d="M12 3v12m0 0 4-4m-4 4-4-4M5 21h14"
        stroke="currentColor"
        strokeWidth="1.7"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  )
}

function BuildsSkeleton() {
  return (
    <div className="wb-page">
      <div className="wb-page-header">
        <div>
          <h1 className="wb-page-title">Builds</h1>
          <p className="wb-page-subtitle">Generate and download the Android APK.</p>
        </div>
      </div>
      <div className="wb-builds-grid">
        <div className="wb-skeleton wb-skeleton-stat" />
        <div className="wb-skeleton wb-skeleton-stat" />
      </div>
    </div>
  )
}