import { useUnitPreference, type UnitPreference } from '../lib/units'
import { t } from '../lib/i18n'

const OPTIONS: { id: UnitPreference; label: string; hint: string }[] = [
  { id: 'auto', label: t("Auto"), hint: t("Match this device") },
  { id: 'metric', label: t("Metric"), hint: 'km/h' },
  { id: 'imperial', label: t("Imperial"), hint: 'mph' },
]

export function UnitsToggle() {
  const [preference, setPreference] = useUnitPreference()

  return (
    <div role="radiogroup" aria-label={t("Units")} className="wb-theme-toggle">
      {OPTIONS.map((option) => {
        const checked = preference === option.id
        return (
          <button
            key={option.id}
            type="button"
            role="radio"
            aria-checked={checked}
            className={`wb-theme-option${checked ? ' is-selected' : ''}`}
            onClick={() => setPreference(option.id)}
          >
            <span className="wb-theme-option-label">{option.label}</span>
            <span className="wb-theme-option-hint">{option.hint}</span>
          </button>
        )
      })}
    </div>
  )
}
