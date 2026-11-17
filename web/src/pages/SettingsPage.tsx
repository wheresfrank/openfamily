// Settings page — signed-in account (photo, name, password), theme, and a
// short About block for this server. The Twilio SMS server settings are a
// platform-admin surface; everyone else sees their personal settings only,
// matching what the apps expose.

import React from 'react'
import {
  ApiError,
  changePassword,
  deleteProfileAvatar,
  getProfile,
  getProfileAvatar,
  updateProfile,
  uploadProfileAvatar,
} from '../lib/api'
import { useMe } from '../lib/me'
import type { Profile } from '../lib/types'
import { ThemeToggle } from '../components/ThemeToggle'
import { LanguageToggle } from '../components/LanguageToggle'
import { UnitsToggle } from '../components/UnitsToggle'
import { LanguageSettingsCard } from './LanguageSettingsCard'
import { Button, Card, CopyButton, Mono, Spinner } from '../components/primitives'
import { ServerUpdateCard } from './ServerUpdateCard'
import { TwilioSettingsCard } from './TwilioSettingsCard'
import { DomainSettingsCard } from './DomainSettingsCard'
import './pages.css'
import './SettingsPage.css'
import { t } from '../lib/i18n'

const MAX_AVATAR_BYTES = 5 * 1024 * 1024
const ACCEPTED_AVATAR_TYPES = new Set(['image/jpeg', 'image/png'])
const MAX_NAME_LENGTH = 120
const MIN_PASSWORD_LENGTH = 8
const APP_VERSION = '0.1.0'

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
      return t("Administrator")
    case 'member':
      return t("Member")
    case 'child':
      return t("Child")
    default:
      return '—'
  }
}

function avatarUpdatedLabel(profile: Profile | null): string {
  if (!profile?.has_avatar) return t("No profile picture uploaded.")
  if (!profile.avatar_updated_at) return t("Profile picture uploaded.")

  const updated = new Date(profile.avatar_updated_at)
  if (Number.isNaN(updated.getTime())) return t("Profile picture uploaded.")
  return t("Updated {time}.", { time: updated.toLocaleString() })
}

function messageFromError(error: unknown, fallback: string): string {
  if (error instanceof ApiError) return error.message || fallback
  if (error instanceof Error) return error.message || fallback
  return fallback
}

/**
 * Client-side password form checks. Confirm-match can only happen here; length
 * and "must differ from current" are also enforced by the API.
 */
function passwordFormIssue(
  currentPassword: string,
  newPassword: string,
  confirmPassword: string,
): string | null {
  if (!currentPassword || !newPassword || !confirmPassword) {
    return t("Enter your current password and a new password twice.")
  }
  if (newPassword.length < MIN_PASSWORD_LENGTH) {
    return t("New password must be at least {min} characters.", { min: MIN_PASSWORD_LENGTH })
  }
  if (newPassword !== confirmPassword) {
    return t("New password and confirmation do not match.")
  }
  if (currentPassword === newPassword) {
    return t("Choose a password that is different from your current one.")
  }
  return null
}

export function SettingsPage({ email, onLogout }: SettingsPageProps) {
  const { isPlatformAdmin } = useMe()
  const fileInputRef = React.useRef<HTMLInputElement>(null)
  const avatarObjectUrlRef = React.useRef<string | null>(null)
  const requestVersionRef = React.useRef(0)
  const [profile, setProfile] = React.useState<Profile | null>(null)
  const [avatarUrl, setAvatarUrl] = React.useState<string | null>(null)
  const [profileLoading, setProfileLoading] = React.useState(true)
  const [profileError, setProfileError] = React.useState<string | null>(null)
  const [mutation, setMutation] = React.useState<AvatarMutation>(null)
  const [avatarMessage, setAvatarMessage] = React.useState<ProfileMessage>(null)
  const [nameDraft, setNameDraft] = React.useState('')
  const nameReadyRef = React.useRef(false)
  const [nameSaving, setNameSaving] = React.useState(false)
  const [nameMessage, setNameMessage] = React.useState<ProfileMessage>(null)
  const [currentPassword, setCurrentPassword] = React.useState('')
  const [newPassword, setNewPassword] = React.useState('')
  const [confirmPassword, setConfirmPassword] = React.useState('')
  const [passwordSaving, setPasswordSaving] = React.useState(false)
  const [passwordMessage, setPasswordMessage] = React.useState<ProfileMessage>(null)

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
      setNameDraft((current) => (nameReadyRef.current ? current : loaded.profile.name))
      nameReadyRef.current = true
      replaceAvatarUrl(loaded.avatarUrl)
      return true
    } catch (error) {
      if (requestVersion === requestVersionRef.current) {
        setProfileError(messageFromError(error, t("Could not load your account.")))
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
      setAvatarMessage({ tone: 'error', text: t("Choose a JPEG or PNG image.") })
      return
    }
    if (file.size > MAX_AVATAR_BYTES) {
      setAvatarMessage({ tone: 'error', text: t("Choose an image smaller than 5 MB.") })
      return
    }

    setAvatarMessage(null)
    setMutation('uploading')
    try {
      await uploadProfileAvatar(file)
      const refreshed = await refreshProfile()
      setAvatarMessage(
        refreshed
          ? { tone: 'success', text: t("Profile picture updated.") }
          : {
              tone: 'error',
              text: t("Your picture was uploaded, but the updated profile could not be loaded. Refresh to confirm it."),
            },
      )
    } catch (error) {
      setAvatarMessage({ tone: 'error', text: messageFromError(error, t("Could not upload your profile picture.")) })
    } finally {
      setMutation(null)
    }
  }

  const removeAvatar = async () => {
    if (!profile?.has_avatar || mutation) return

    setAvatarMessage(null)
    setMutation('removing')
    try {
      await deleteProfileAvatar()
      const refreshed = await refreshProfile()
      setAvatarMessage(
        refreshed
          ? { tone: 'success', text: t("Profile picture removed.") }
          : {
              tone: 'error',
              text: t("Your picture was removed, but the updated profile could not be loaded. Refresh to confirm it."),
            },
      )
    } catch (error) {
      setAvatarMessage({ tone: 'error', text: messageFromError(error, t("Could not remove your profile picture.")) })
    } finally {
      setMutation(null)
    }
  }

  const saveName = async (event: React.FormEvent) => {
    event.preventDefault()
    if (!profile || nameSaving) return

    const name = nameDraft.trim()
    if (!name) {
      setNameMessage({ tone: 'error', text: t("Name is required.") })
      return
    }
    if ([...name].length > MAX_NAME_LENGTH) {
      setNameMessage({ tone: 'error', text: t("Name must be {max} characters or fewer.", { max: MAX_NAME_LENGTH }) })
      return
    }
    if (name === profile.name) return

    setNameMessage(null)
    setNameSaving(true)
    try {
      const updated = await updateProfile(name)
      setProfile((current) => (current ? { ...current, name: updated.name } : current))
      setNameDraft(updated.name)
      setNameMessage({ tone: 'success', text: t("Name updated.") })
    } catch (error) {
      setNameMessage({ tone: 'error', text: messageFromError(error, t("Could not update your name.")) })
    } finally {
      setNameSaving(false)
    }
  }

  const savePassword = async (event: React.FormEvent) => {
    event.preventDefault()
    if (passwordSaving) return

    const issue = passwordFormIssue(currentPassword, newPassword, confirmPassword)
    if (issue) {
      setPasswordMessage({ tone: 'error', text: issue })
      return
    }

    setPasswordMessage(null)
    setPasswordSaving(true)
    try {
      await changePassword(currentPassword, newPassword)
      setCurrentPassword('')
      setNewPassword('')
      setConfirmPassword('')
      setPasswordMessage({ tone: 'success', text: t("Password updated. You are still signed in here.") })
    } catch (error) {
      setPasswordMessage({ tone: 'error', text: messageFromError(error, t("Could not update your password.")) })
    } finally {
      setPasswordSaving(false)
    }
  }

  const displayName = profile?.name.trim() || profile?.email || email || t("Your account")
  const displayEmail = profile?.email || email || '—'
  const hasAvatar = Boolean(profile?.has_avatar && avatarUrl)
  const avatarControlsDisabled = !profile || mutation !== null
  const nameUnchanged = Boolean(profile && nameDraft.trim() === profile.name)
  const serverUrl = typeof window !== 'undefined' ? window.location.origin : '—'

  return (
    <div className="wb-page">
      <div className="wb-page-header">
        <div>
          <h1 className="wb-page-title">{t("Settings")}</h1>
          <p className="wb-page-subtitle">
            {isPlatformAdmin ? t("Appearance, account, SMS, and this server.") : t("Appearance, account, and this server.")}
          </p>
        </div>
      </div>

      <div className="wb-settings-grid">
        <div className="wb-settings-col">
          <Card>
            <h3 className="wb-settings-title">{t("Appearance")}</h3>
            <p className="wb-settings-section-help">
              {t("System follows this device. Light is Ice. Dark is Night.")}
            </p>
            <ThemeToggle />
          </Card>

          <Card>
            <h3 className="wb-settings-title">{t("Language")}</h3>
            <p className="wb-settings-section-help">
              {t("Auto uses the server's default language, or this device's.")}
            </p>
            <LanguageToggle />
          </Card>

          {isPlatformAdmin && <LanguageSettingsCard />}

          <Card>
            <h3 className="wb-settings-title">{t("Units")}</h3>
            <p className="wb-settings-section-help">
              {t("Speeds in km/h or mph. Auto follows this device's region.")}
            </p>
            <UnitsToggle />
          </Card>

          {/* Domain status is a read-only mirror of the deployment's
              SITE_ADDRESS plus live DNS/TLS checks. Always shown for platform
              admins — including before a domain exists, with the setup guide. */}
          {isPlatformAdmin && <DomainSettingsCard />}

          {/* Twilio SMS is a server-wide setting: platform admins only. The
              apps never expose it to regular users either. */}
          {isPlatformAdmin && <TwilioSettingsCard />}

          {/* Self-update lives here too: it restarts the server the panel is
              served from, so only platform admins see the card. */}
          {isPlatformAdmin && <ServerUpdateCard />}
        </div>

        <Card>
          <h3 className="wb-settings-title">{t("Account")}</h3>

          <section className="wb-profile-avatar-section" aria-labelledby="wb-profile-picture-title">
            <div className="wb-profile-avatar">
              {avatarUrl ? (
                <img src={avatarUrl} alt={t("{name}'s profile picture", { name: displayName })} />
              ) : profileLoading && !profile ? (
                <Spinner size={24} />
              ) : (
                <span role="img" aria-label={t("No profile picture for {name}", { name: displayName })}>
                  {profileInitials(displayName)}
                </span>
              )}
            </div>

            <div className="wb-profile-avatar-content">
              <h4 id="wb-profile-picture-title" className="wb-profile-avatar-title">{t("Profile picture")}</h4>
              <p id="wb-profile-picture-help" className="wb-profile-avatar-help">
                JPEG or PNG, up to 5 MB. {avatarUpdatedLabel(profile)}
              </p>
              <input
                ref={fileInputRef}
                id="wb-profile-picture-input"
                className="wb-profile-visually-hidden"
                type="file"
                accept="image/jpeg,image/png,.jpg,.jpeg,.png"
                aria-label={t("Choose a profile picture")}
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
                  {hasAvatar ? t("Change picture") : t("Upload picture")}
                </Button>
                {profile?.has_avatar && (
                  <Button
                    type="button"
                    variant="danger"
                    loading={mutation === 'removing'}
                    disabled={avatarControlsDisabled}
                    onClick={() => void removeAvatar()}
                  >
                    {t("Remove")}
                  </Button>
                )}
              </div>
              {avatarMessage && (
                <p
                  className={`wb-profile-message wb-profile-message-${avatarMessage.tone}`}
                  role={avatarMessage.tone === 'error' ? 'alert' : 'status'}
                  aria-live={avatarMessage.tone === 'error' ? 'assertive' : 'polite'}
                >
                  {avatarMessage.text}
                </p>
              )}
            </div>
          </section>

          {profileError && (
            <div className="wb-profile-load-error" role="alert">
              <span>{profileError}</span>
              <Button type="button" variant="secondary" size="sm" onClick={() => void refreshProfile()}>
                {t("Try again")}
              </Button>
            </div>
          )}

          <form className="wb-settings-section" onSubmit={(event) => void saveName(event)}>
            <h4 className="wb-settings-section-title">{t("Profile")}</h4>
            <label className="wb-field" htmlFor="wb-settings-name">
              <span className="wb-label">{t("Name")}</span>
              <input
                id="wb-settings-name"
                className="wb-input"
                value={nameDraft}
                onChange={(event) => setNameDraft(event.target.value)}
                maxLength={MAX_NAME_LENGTH}
                autoComplete="name"
                disabled={!profile || nameSaving}
                required
              />
            </label>
            <label className="wb-field" htmlFor="wb-settings-email">
              <span className="wb-label">{t("Email")}</span>
              <input
                id="wb-settings-email"
                className="wb-input"
                value={profileLoading && !profile ? t("Loading…") : displayEmail}
                readOnly
                autoComplete="username"
              />
            </label>
            <div className="wb-field">
              <span className="wb-label">{t("Role")}</span>
              <p className="wb-settings-readonly">
                {profileLoading && !profile ? t("Loading…") : displayRole(profile?.role)}
              </p>
            </div>
            <div className="wb-settings-form-actions">
              <Button type="submit" loading={nameSaving} disabled={!profile || nameSaving || nameUnchanged}>
                {t("Save name")}
              </Button>
            </div>
            {nameMessage && (
              <p
                className={`wb-profile-message wb-profile-message-${nameMessage.tone}`}
                role={nameMessage.tone === 'error' ? 'alert' : 'status'}
                aria-live={nameMessage.tone === 'error' ? 'assertive' : 'polite'}
              >
                {nameMessage.text}
              </p>
            )}
          </form>

          <form className="wb-settings-section" onSubmit={(event) => void savePassword(event)}>
            <h4 className="wb-settings-section-title">{t("Password")}</h4>
            <p className="wb-settings-section-help">
              At least {MIN_PASSWORD_LENGTH} characters. You stay signed in on this browser.
            </p>
            <label className="wb-field" htmlFor="wb-settings-current-password">
              <span className="wb-label">{t("Current password")}</span>
              <input
                id="wb-settings-current-password"
                className="wb-input"
                type="password"
                value={currentPassword}
                onChange={(event) => setCurrentPassword(event.target.value)}
                autoComplete="current-password"
                disabled={passwordSaving}
                required
              />
            </label>
            <label className="wb-field" htmlFor="wb-settings-new-password">
              <span className="wb-label">{t("New password")}</span>
              <input
                id="wb-settings-new-password"
                className="wb-input"
                type="password"
                value={newPassword}
                onChange={(event) => setNewPassword(event.target.value)}
                autoComplete="new-password"
                minLength={MIN_PASSWORD_LENGTH}
                disabled={passwordSaving}
                required
              />
            </label>
            <label className="wb-field" htmlFor="wb-settings-confirm-password">
              <span className="wb-label">{t("Confirm new password")}</span>
              <input
                id="wb-settings-confirm-password"
                className="wb-input"
                type="password"
                value={confirmPassword}
                onChange={(event) => setConfirmPassword(event.target.value)}
                autoComplete="new-password"
                minLength={MIN_PASSWORD_LENGTH}
                disabled={passwordSaving}
                required
              />
            </label>
            <div className="wb-settings-form-actions">
              <Button type="submit" loading={passwordSaving} disabled={passwordSaving}>
                {t("Change password")}
              </Button>
            </div>
            {passwordMessage && (
              <p
                className={`wb-profile-message wb-profile-message-${passwordMessage.tone}`}
                role={passwordMessage.tone === 'error' ? 'alert' : 'status'}
                aria-live={passwordMessage.tone === 'error' ? 'assertive' : 'polite'}
              >
                {passwordMessage.text}
              </p>
            )}
          </form>

          <div className="wb-settings-actions">
            <Button variant="danger" onClick={onLogout}>
              {t("Sign out")}
            </Button>
          </div>
        </Card>

        <Card className="wb-settings-wide">
          <h3 className="wb-settings-title">{t("About")}</h3>
          <dl className="wb-settings-list wb-settings-list-row">
            <div>
              <dt>{t("App")}</dt>
              <dd>OpenFamily</dd>
            </div>
            <div>
              <dt>{t("Version")}</dt>
              <dd>{APP_VERSION}</dd>
            </div>
            <div>
              <dt>{t("Server")}</dt>
              <dd className="wb-settings-mono">
                <Mono>{serverUrl}</Mono>
                <CopyButton value={serverUrl} label={t("Copy server URL")} />
              </dd>
            </div>
          </dl>
        </Card>
      </div>
    </div>
  )
}
