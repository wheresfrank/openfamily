import { useThemePreference, type ThemePreference } from '../lib/theme'

const OPTIONS: { id: ThemePreference; label: string; hint: string }[] = [
  { id: 'system', label: 'System', hint: 'Match this device' },
  { id: 'light', label: 'Light', hint: 'Ice' },
  { id: 'dark', label: 'Dark', hint: 'Night' },
]

export function ThemeToggle() {
  const [preference, setPreference] = useThemePreference()

  return (
    <div role="radiogroup" aria-label="Theme" className="wb-theme-toggle">
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
