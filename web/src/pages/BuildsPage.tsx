// APK page — serves the pre-built Android APK. The APK is built in CI (see
// .github/workflows/apk.yml) and placed in the server's APK_DIR; this page just
// downloads it. There is no on-server build.

import React from 'react'
import { downloadApk, ApiError } from '../lib/api'
import { Button, Card, CopyButton } from '../components/primitives'
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
          <h1 className="wb-page-title">APK</h1>
          <p className="wb-page-subtitle">Download the Android app.</p>
        </div>
      </div>

      <div className="wb-builds-grid">
        <Card>
          <div className="wb-build-status">
            <div className="wb-build-status-head">
              <h3 className="wb-build-status-title">Android app</h3>
            </div>

            <p className="wb-build-info-text">
              The release APK is built automatically by CI and served from the
              server's <code className="wb-build-info-code">APK_DIR</code>. Download
              it and install it on an Android device.
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
          <h3 className="wb-build-info-title">How the APK is built</h3>
          <p className="wb-build-info-text">
            The APK is built by a GitHub Actions workflow on every release tag
            (<code className="wb-build-info-code">v*</code>) and attached to the
            GitHub release. To make it available here, copy the built APK into the
            server's <code className="wb-build-info-code">APK_DIR</code> directory.
          </p>
          <ul className="wb-build-info-list">
            <li>
              <span className="wb-build-info-k">Download</span>
              <code className="wb-build-info-code">GET /api/admin/apk</code>
              <CopyButton value="GET /api/admin/apk" label="Copy download endpoint" />
            </li>
          </ul>
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
