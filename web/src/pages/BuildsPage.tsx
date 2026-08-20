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
              The release APK is built by CI and committed to the repository at
              <code className="wb-build-info-code">apk/whereabouts-release.apk</code>.
              Servers pull master, which brings the APK down with the code, and the
              button serves it from the server's <code className="wb-build-info-code">APK_DIR</code>.
              No manual copy is needed.
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
            The APK is built by a GitHub Actions workflow on every merge to master
            (<code className="wb-build-info-code">push</code>) and committed straight
            back into the repository at
            <code className="wb-build-info-code">apk/whereabouts-release.apk</code>.
            A server that pulls master receives the APK automatically; the download
            button serves the newest <code className="wb-build-info-code">.apk</code>
            from its <code className="wb-build-info-code">APK_DIR</code>.
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
