// APK page — fetches the latest GitHub Release APK and serves it. CI publishes
// the file; this page just downloads it. There is no on-server build.

import React from 'react'
import { downloadApk, ApiError } from '../lib/api'
import { Button, Card } from '../components/primitives'
import './pages.css'
import './BuildsPage.css'

export function BuildsPage() {
  const [downloadState, setDownloadState] = React.useState<'idle' | 'downloading' | 'done' | 'error'>('idle')
  const [actionError, setActionError] = React.useState<string | null>(null)

  const download = async () => {
    setActionError(null)
    setDownloadState('downloading')
    try {
      const blob = await downloadApk()
      const url = URL.createObjectURL(blob)
      const a = document.createElement('a')
      a.href = url
      a.download = 'openfamily.apk'
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
          <h1 className="wb-page-title">APK</h1>
          <p className="wb-page-subtitle">Install the Android app on a phone.</p>
        </div>
      </div>

      <div className="wb-builds-grid">
        <Card>
          <div className="wb-build-status">
            <div className="wb-build-status-head">
              <h3 className="wb-build-status-title">Android app</h3>
            </div>

            <p className="wb-build-info-text">
              Latest Android build. The first click after a new GitHub Actions
              run may take a moment.
            </p>

            <div className="wb-build-actions">
              <Button
                onClick={download}
                disabled={downloadState === 'downloading'}
                loading={downloadState === 'downloading'}
                icon={<DownloadIcon />}
              >
                {downloadState === 'downloading' ? 'Downloading…' : 'Download APK'}
              </Button>
            </div>

            {downloadState === 'done' && (
              <p className="wb-build-info-foot" style={{ marginTop: 12 }}>
                Download started.
              </p>
            )}
            {actionError && <p className="wb-error-text" style={{ marginTop: 12 }}>{actionError}</p>}
          </div>
        </Card>

        <Card>
          <h3 className="wb-build-info-title">How the APK is published</h3>
          <p className="wb-build-info-text">
            GitHub Actions publishes the file. Set
            <code className="wb-build-info-code">APK_GITHUB_TOKEN</code>
            in the server env for this private repo.
          </p>
        </Card>
      </div>
    </div>
  )
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
