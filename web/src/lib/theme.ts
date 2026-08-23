// Appearance preference: system follows the device; light is Ice; dark is Night.
// The document always gets a resolved data-theme so CSS never has to branch on "system".

import React from 'react'

export type ThemePreference = 'system' | 'light' | 'dark'
export type ResolvedTheme = 'light' | 'dark'

export const THEME_STORAGE_KEY = 'wb-theme'

const ICE_PAPER = '#EEF2F6'
const NIGHT_PAPER = '#1C1E22'

const listeners = new Set<() => void>()

function notify(): void {
  for (const listener of listeners) listener()
}

export function parseThemePreference(raw: string | null): ThemePreference {
  if (raw === 'light' || raw === 'dark' || raw === 'system') return raw
  return 'system'
}

export function readThemePreference(): ThemePreference {
  try {
    return parseThemePreference(window.localStorage.getItem(THEME_STORAGE_KEY))
  } catch {
    return 'system'
  }
}

export function systemPrefersDark(): boolean {
  return window.matchMedia('(prefers-color-scheme: dark)').matches
}

export function resolveTheme(preference: ThemePreference): ResolvedTheme {
  if (preference === 'light') return 'light'
  if (preference === 'dark') return 'dark'
  return systemPrefersDark() ? 'dark' : 'light'
}

function syncThemeColor(resolved: ResolvedTheme): void {
  let meta = document.querySelector('meta[name="theme-color"][data-wb]')
  if (!meta) {
    meta = document.createElement('meta')
    meta.setAttribute('name', 'theme-color')
    meta.setAttribute('data-wb', 'true')
    document.head.appendChild(meta)
  }
  meta.setAttribute('content', resolved === 'dark' ? NIGHT_PAPER : ICE_PAPER)
}

export function applyResolvedTheme(resolved: ResolvedTheme): void {
  document.documentElement.dataset.theme = resolved
  document.documentElement.style.colorScheme = resolved
  syncThemeColor(resolved)
}

export function applyThemePreference(preference: ThemePreference): ResolvedTheme {
  const resolved = resolveTheme(preference)
  applyResolvedTheme(resolved)
  return resolved
}

export function setThemePreference(preference: ThemePreference): void {
  try {
    window.localStorage.setItem(THEME_STORAGE_KEY, preference)
  } catch {
    // Private mode or blocked storage: the choice lasts for this page only.
  }
  applyThemePreference(preference)
  notify()
}

export function subscribeTheme(listener: () => void): () => void {
  listeners.add(listener)
  return () => {
    listeners.delete(listener)
  }
}

export function useThemePreference(): [ThemePreference, (next: ThemePreference) => void] {
  const [preference, setPreference] = React.useState<ThemePreference>(() =>
    typeof window === 'undefined' ? 'system' : readThemePreference(),
  )

  React.useEffect(() => {
    return subscribeTheme(() => setPreference(readThemePreference()))
  }, [])

  return [preference, setThemePreference]
}

export function initTheme(): void {
  applyThemePreference(readThemePreference())

  const media = window.matchMedia('(prefers-color-scheme: dark)')
  const onSystemChange = () => {
    if (readThemePreference() === 'system') {
      applyThemePreference('system')
      notify()
    }
  }
  media.addEventListener('change', onSystemChange)
  window.addEventListener('storage', (event) => {
    if (event.key === THEME_STORAGE_KEY) {
      applyThemePreference(readThemePreference())
      notify()
    }
  })
}
