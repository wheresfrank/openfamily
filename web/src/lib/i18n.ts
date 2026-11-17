// Translations for the admin panel. English source text is the key; a missing
// entry falls back to English. The language is resolved once before the app
// renders (user choice, then the server's default language, then the browser)
// and changing it reloads the page, so strings can be used anywhere without
// hooks or providers.

import { es } from './locales/es'

export type Lang = 'en' | 'es'
export type LangPreference = 'auto' | Lang

export const LANG_STORAGE_KEY = 'wb-lang'
export const SERVER_LANG_STORAGE_KEY = 'wb-server-lang'

const SUPPORTED: readonly Lang[] = ['en', 'es']
const DICTIONARIES: Record<Lang, Record<string, string>> = { en: {}, es }

let current: Lang = 'en'

function isLang(value: unknown): value is Lang {
  return typeof value === 'string' && (SUPPORTED as readonly string[]).includes(value)
}

function readStorage(key: string): string | null {
  try {
    return window.localStorage.getItem(key)
  } catch {
    return null
  }
}

function writeStorage(key: string, value: string | null): void {
  try {
    if (value == null) window.localStorage.removeItem(key)
    else window.localStorage.setItem(key, value)
  } catch {
    // Blocked storage: the choice lasts until the next reload.
  }
}

export function parseLangPreference(raw: string | null): LangPreference {
  return isLang(raw) ? raw : 'auto'
}

export function readLangPreference(): LangPreference {
  return parseLangPreference(readStorage(LANG_STORAGE_KEY))
}

/** The server's default language, remembered from the last /config response. */
export function readServerDefaultLang(): Lang | null {
  const raw = readStorage(SERVER_LANG_STORAGE_KEY)
  return isLang(raw) ? raw : null
}

/** Resolves the language: explicit choice, then server default, then browser. */
export function resolveLang(
  preference: LangPreference,
  serverDefault: Lang | null,
  browserLanguage: string,
): Lang {
  if (preference !== 'auto') return preference
  if (serverDefault) return serverDefault
  return browserLanguage.toLowerCase().startsWith('es') ? 'es' : 'en'
}

export function getLang(): Lang {
  return current
}

/** Translates English source text; `{name}` placeholders take values from vars. */
export function t(text: string, vars?: Record<string, string | number>): string {
  const translated = DICTIONARIES[current][text] ?? text
  if (!vars) return translated
  return translated.replace(/\{(\w+)\}/g, (match, name: string) =>
    name in vars ? String(vars[name]) : match,
  )
}

/** Remembers the server default language from a /config or settings response. */
export function rememberServerDefaultLang(value: unknown): void {
  writeStorage(SERVER_LANG_STORAGE_KEY, isLang(value) ? value : null)
}

/** Resolves the language before the app renders. Never throws. */
export async function initI18n(): Promise<void> {
  try {
    const controller = new AbortController()
    const timer = window.setTimeout(() => controller.abort(), 1500)
    try {
      const res = await fetch('/config', { signal: controller.signal })
      if (res.ok) {
        const body = (await res.json()) as { default_language?: unknown }
        rememberServerDefaultLang(body.default_language)
      }
    } finally {
      window.clearTimeout(timer)
    }
  } catch {
    // Offline or an older server: use the last remembered default.
  }
  current = resolveLang(
    readLangPreference(),
    readServerDefaultLang(),
    typeof navigator === 'undefined' ? 'en' : navigator.language,
  )
  document.documentElement.lang = current
}

/** Saves the user's language choice and reloads so every string updates. */
export function setLangPreference(preference: LangPreference): void {
  writeStorage(LANG_STORAGE_KEY, preference === 'auto' ? null : preference)
  window.location.reload()
}
