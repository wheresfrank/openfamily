import { useUnitPreference, type UnitPreference } from '../lib/units'

const OPTIONS: { id: UnitPreference; label: string; hint: string }[] = [
  { id: 'auto', label: 'Auto', hint: 'Match this device' },
  { id: 'metric', label: 'Metric', hint: 'km/h' },
  { id: 'imperial', label: 'Imperial', hint: 'mph' },
]

export function UnitsToggle() {
  const [preference, setPreference] = useUnitPreference()

  return (
    <div role="radiogroup" aria-label="Units" className="wb-theme-toggle">
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
