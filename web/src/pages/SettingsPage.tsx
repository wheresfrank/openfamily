// Settings page — signed-in account details, profile picture, and server info.

import React from 'react'
import {
  ApiError,
  deleteProfileAvatar,
  getProfile,
  getProfileAvatar,
  uploadProfileAvatar,
} from '../lib/api'
import { getAccessToken } from '../lib/auth'
import type { Profile } from '../lib/types'
import { Button, Card, CopyButton, Mono, Spinner } from '../components/primitives'
import './pages.css'
import './SettingsPage.css'

const MAX_AVATAR_BYTES = 5 * 1024 * 1024
const ACCEPTED_AVATAR_TYPES = new Set(['image/jpeg', 'image/png'])

type AvatarMutation = 'uploading' | 'removing' | null
type ProfileMessage = { tone: 'success' | 'error'; text: string } | null

interface LoadedProfile {
  profile: Profile
  avatarUrl: string | null
}

interface SettingsPageProps {
  email: string | null
  onLogout: () => void
}

async function loadProfileWithAvatar(): Promise<LoadedProfile> {
  const profile = await getProfile()
  if (!profile.has_avatar) return { profile, avatarUrl: null }

  try {
    const avatar = await getProfileAvatar()
    return { profile, avatarUrl: URL.createObjectURL(avatar) }
  } catch (error) {
    // A recently removed avatar can race the profile response. Treat a missing
    // image as no avatar, while keeping other failures visible to the user.
    if (error instanceof ApiError && error.status === 404) {
      return {
        profile: { ...profile, has_avatar: false, avatar_updated_at: null },
        avatarUrl: null,
      }
    }
    throw error
  }
}

function profileInitials(name: string): string {
  const words = name.trim().split(/\s+/).filter(Boolean)
  if (words.length === 0) return '?'
  if (words.length === 1) return words[0].slice(0, 2).toUpperCase()
  return `${words[0][0]}${words[words.length - 1][0]}`.toUpperCase()
}

function displayRole(role: Profile['role'] | undefined): string {
  switch (role) {
    case 'admin':
      return 'Administrator'
    case 'member':
      return 'Member'
    case 'child':
      return 'Child'
    default:
      return '—'
  }
}

function avatarUpdatedLabel(profile: Profile | null): string {
  if (!profile?.has_avatar) return 'No profile picture uploaded.'
  if (!profile.avatar_updated_at) return 'Profile picture uploaded.'

  const updated = new Date(profile.avatar_updated_at)
  if (Number.isNaN(updated.getTime())) return 'Profile picture uploaded.'
  return `Updated ${updated.toLocaleString()}.`
}

function messageFromError(error: unknown, fallback: string): string {
  if (error instanceof ApiError) return error.message || fallback
  if (error instanceof Error) return error.message || fallback
  return fallback
}

export function SettingsPage({ email, onLogout }: SettingsPageProps) {
  const token = getAccessToken()
  const fileInputRef = React.useRef<HTMLInputElement>(null)
  const avatarObjectUrlRef = React.useRef<string | null>(null)
  const requestVersionRef = React.useRef(0)
  const [profile, setProfile] = React.useState<Profile | null>(null)
  const [avatarUrl, setAvatarUrl] = React.useState<string | null>(null)
  const [profileLoading, setProfileLoading] = React.useState(true)
  const [profileError, setProfileError] = React.useState<string | null>(null)
  const [mutation, setMutation] = React.useState<AvatarMutation>(null)
  const [message, setMessage] = React.useState<ProfileMessage>(null)

  const replaceAvatarUrl = React.useCallback((nextUrl: string | null) => {
    const previousUrl = avatarObjectUrlRef.current
    if (previousUrl && previousUrl !== nextUrl) URL.revokeObjectURL(previousUrl)
    avatarObjectUrlRef.current = nextUrl
    setAvatarUrl(nextUrl)
  }, [])

  React.useEffect(() => () => {
    if (avatarObjectUrlRef.current) URL.revokeObjectURL(avatarObjectUrlRef.current)
  }, [])

  const refreshProfile = React.useCallback(async (): Promise<boolean> => {
    const requestVersion = ++requestVersionRef.current
    setProfileLoading(true)
    setProfileError(null)

    try {
      const loaded = await loadProfileWithAvatar()
      if (requestVersion !== requestVersionRef.current) {
        if (loaded.avatarUrl) URL.revokeObjectURL(loaded.avatarUrl)
        return false
      }
      setProfile(loaded.profile)
      replaceAvatarUrl(loaded.avatarUrl)
      return true
    } catch (error) {
      if (requestVersion === requestVersionRef.current) {
        setProfileError(messageFromError(error, 'Could not load your account.'))
      }
      return false
    } finally {
      if (requestVersion === requestVersionRef.current) setProfileLoading(false)
    }
  }, [replaceAvatarUrl])

  React.useEffect(() => {
    void refreshProfile()
    return () => {
      // Ignore an in-flight response after unmount or Strict Mode cleanup.
      requestVersionRef.current += 1
    }
  }, [refreshProfile])

  const onFileChange = async (event: React.ChangeEvent<HTMLInputElement>) => {
    const file = event.currentTarget.files?.[0]
    // Allow selecting the same image again after a validation or upload error.
    event.currentTarget.value = ''
    if (!file || mutation) return

    if (!ACCEPTED_AVATAR_TYPES.has(file.type)) {
      setMessage({ tone: 'error', text: 'Choose a JPEG or PNG image.' })
      return
    }
    if (file.size > MAX_AVATAR_BYTES) {
      setMessage({ tone: 'error', text: 'Choose an image smaller than 5 MB.' })
      return
    }

    setMessage(null)
    setMutation('uploading')
    try {
      await uploadProfileAvatar(file)
      const refreshed = await refreshProfile()
      setMessage(
        refreshed
          ? { tone: 'success', text: 'Profile picture updated.' }
          : {
              tone: 'error',
              text: 'Your picture was uploaded, but the updated profile could not be loaded. Refresh to confirm it.',
            },
      )
    } catch (error) {
      setMessage({ tone: 'error', text: messageFromError(error, 'Could not upload your profile picture.') })
    } finally {
      setMutation(null)
    }
  }

  const removeAvatar = async () => {
    if (!profile?.has_avatar || mutation) return

    setMessage(null)
    setMutation('removing')
    try {
      await deleteProfileAvatar()
      const refreshed = await refreshProfile()
      setMessage(
        refreshed
          ? { tone: 'success', text: 'Profile picture removed.' }
          : {
              tone: 'error',
              text: 'Your picture was removed, but the updated profile could not be loaded. Refresh to confirm it.',
            },
      )
    } catch (error) {
      setMessage({ tone: 'error', text: messageFromError(error, 'Could not remove your profile picture.') })
    } finally {
      setMutation(null)
    }
  }

  const displayName = profile?.name.trim() || profile?.email || email || 'Your account'
  const displayEmail = profile?.email || email || '—'
  const hasAvatar = Boolean(profile?.has_avatar && avatarUrl)
  const avatarControlsDisabled = !profile || profileLoading || mutation !== null

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

          <section className="wb-profile-avatar-section" aria-labelledby="wb-profile-picture-title">
            <div className="wb-profile-avatar">
              {avatarUrl ? (
                <img src={avatarUrl} alt={`${displayName}'s profile picture`} />
              ) : profileLoading ? (
                <Spinner size={24} />
              ) : (
                <span role="img" aria-label={`No profile picture for ${displayName}`}>
                  {profileInitials(displayName)}
                </span>
              )}
            </div>

            <div className="wb-profile-avatar-content">
              <h4 id="wb-profile-picture-title" className="wb-profile-avatar-title">Profile picture</h4>
              <p id="wb-profile-picture-help" className="wb-profile-avatar-help">
                JPEG or PNG, up to 5 MB. {avatarUpdatedLabel(profile)}
              </p>
              <input
                ref={fileInputRef}
                id="wb-profile-picture-input"
                className="wb-profile-visually-hidden"
                type="file"
                accept="image/jpeg,image/png,.jpg,.jpeg,.png"
                aria-label="Choose a profile picture"
                aria-describedby="wb-profile-picture-help"
                disabled={avatarControlsDisabled}
                onChange={onFileChange}
              />
              <div className="wb-profile-avatar-actions">
                <Button
                  type="button"
                  variant="secondary"
                  loading={mutation === 'uploading'}
                  disabled={avatarControlsDisabled}
                  onClick={() => fileInputRef.current?.click()}
                >
                  {hasAvatar ? 'Change picture' : 'Upload picture'}
                </Button>
                {profile?.has_avatar && (
                  <Button
                    type="button"
                    variant="danger"
                    loading={mutation === 'removing'}
                    disabled={avatarControlsDisabled}
                    onClick={() => void removeAvatar()}
                  >
                    Remove
                  </Button>
                )}
              </div>
              {message && (
                <p
                  className={`wb-profile-message wb-profile-message-${message.tone}`}
                  role={message.tone === 'error' ? 'alert' : 'status'}
                  aria-live={message.tone === 'error' ? 'assertive' : 'polite'}
                >
                  {message.text}
                </p>
              )}
            </div>
          </section>

          {profileError && (
            <div className="wb-profile-load-error" role="alert">
              <span>{profileError}</span>
              <Button type="button" variant="secondary" size="sm" onClick={() => void refreshProfile()}>
                Try again
              </Button>
            </div>
          )}

          <dl className="wb-settings-list">
            <div>
              <dt>Name</dt>
              <dd>{profileLoading && !profile ? 'Loading…' : displayName}</dd>
            </div>
            <div>
              <dt>Email</dt>
              <dd>{profileLoading && !profile ? 'Loading…' : displayEmail}</dd>
            </div>
            <div>
              <dt>Role</dt>
              <dd>{profileLoading && !profile ? 'Loading…' : displayRole(profile?.role)}</dd>
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
