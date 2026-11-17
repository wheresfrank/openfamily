// Platform-admin card: the language apps and the admin panel use when a
// person has not chosen one. Saved on the server (GET/PUT
// /api/admin/settings/language).

import React from 'react'
import { getLanguageSettings, putLanguageSettings } from '../lib/api'
import { getLang, rememberServerDefaultLang, t } from '../lib/i18n'
import { Card } from '../components/primitives'

const OPTIONS: { value: string; label: string }[] = [
  { value: '', label: t("Each device’s language") },
  { value: 'en', label: 'English' },
  { value: 'es', label: 'Español' },
]

export function LanguageSettingsCard() {
  const [value, setValue] = React.useState<string | null>(null)
  const [saving, setSaving] = React.useState(false)
  const [message, setMessage] = React.useState<string | null>(null)
  const [error, setError] = React.useState<string | null>(null)

  React.useEffect(() => {
    let cancelled = false
    getLanguageSettings()
      .then((s) => {
        if (!cancelled) setValue(s.default_language)
      })
      .catch((e) => {
        if (!cancelled) setError(e instanceof Error ? e.message : t('Could not load the language setting'))
      })
    return () => {
      cancelled = true
    }
  }, [])

  const save = async (next: string) => {
    setSaving(true)
    setError(null)
    setMessage(null)
    try {
      const saved = await putLanguageSettings(next)
      setValue(saved.default_language)
      rememberServerDefaultLang(saved.default_language || null)
      setMessage(t('Saved. New sessions use this language by default.'))
      // The panel itself follows the server default only when the person has
      // not picked a language; reload so that change shows immediately.
      const effective = saved.default_language || null
      if (effective && effective !== getLang() && localStorage.getItem('wb-lang') == null) {
        window.location.reload()
      }
    } catch (e) {
      setError(e instanceof Error ? e.message : t('Could not save the language setting'))
    } finally {
      setSaving(false)
    }
  }

  return (
    <Card>
      <h3 className="wb-settings-title">{t('Default language')}</h3>
      <p className="wb-settings-section-help">
        {t('Used by the apps and this panel until a person picks their own language.')}
      </p>
      <label className="wb-field" htmlFor="default-language">
        <span className="wb-label">{t('Server default')}</span>
        <select
          id="default-language"
          className="wb-select"
          value={value ?? ''}
          disabled={value == null || saving}
          onChange={(e) => void save(e.target.value)}
        >
          {OPTIONS.map((o) => (
            <option key={o.value} value={o.value}>
              {t(o.label)}
            </option>
          ))}
        </select>
      </label>
      {message ? <p className="wb-settings-section-help">{message}</p> : null}
      {error ? <p className="wb-settings-section-help">{error}</p> : null}
    </Card>
  )
}
