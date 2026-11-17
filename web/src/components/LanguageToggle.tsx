import { readLangPreference, setLangPreference, t, type LangPreference } from '../lib/i18n'

const OPTIONS: { id: LangPreference; label: string; hint: string }[] = [
  { id: 'auto', label: t("Auto"), hint: t("Match this device") },
  { id: 'en', label: 'English', hint: '' },
  { id: 'es', label: 'Español', hint: '' },
]

export function LanguageToggle() {
  const preference = readLangPreference()

  return (
    <div role="radiogroup" aria-label={t('Language')} className="wb-theme-toggle">
      {OPTIONS.map((option) => {
        const checked = preference === option.id
        return (
          <button
            key={option.id}
            type="button"
            role="radio"
            aria-checked={checked}
            className={`wb-theme-option${checked ? ' is-selected' : ''}`}
            onClick={() => {
              if (!checked) setLangPreference(option.id)
            }}
          >
            <span className="wb-theme-option-label">{t(option.label)}</span>
            {option.hint ? <span className="wb-theme-option-hint">{t(option.hint)}</span> : null}
          </button>
        )
      })}
    </div>
  )
}
