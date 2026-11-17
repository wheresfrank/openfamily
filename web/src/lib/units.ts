// Distance/speed unit preference. "auto" follows the browser region (imperial
// in the US, Liberia and Myanmar, metric elsewhere). Stored per browser.

import React from 'react'

export type UnitPreference = 'auto' | 'metric' | 'imperial'

export const UNITS_STORAGE_KEY = 'wb-units'

const IMPERIAL_REGIONS = new Set(['US', 'LR', 'MM'])
const MPS_TO_MPH = 2.23694
const MPS_TO_KMH = 3.6

const listeners = new Set<() => void>()

export function parseUnitPreference(raw: string | null): UnitPreference {
  return raw === 'metric' || raw === 'imperial' || raw === 'auto' ? raw : 'auto'
}

export function readUnitPreference(): UnitPreference {
  try {
    return parseUnitPreference(window.localStorage.getItem(UNITS_STORAGE_KEY))
  } catch {
    return 'auto'
  }
}

function browserRegion(): string | undefined {
  try {
    const locale = new Intl.Locale(navigator.language)
    return locale.region?.toUpperCase()
  } catch {
    return undefined
  }
}

export function resolveMetric(preference: UnitPreference, region?: string): boolean {
  if (preference === 'metric') return true
  if (preference === 'imperial') return false
  return !IMPERIAL_REGIONS.has((region ?? '').toUpperCase())
}

/** Whether speeds should currently be shown in km/h (reads the stored choice). */
export function isMetricNow(): boolean {
  return resolveMetric(readUnitPreference(), browserRegion())
}

export function speedValue(speedMps: number, metric: boolean): number {
  return Math.round(speedMps * (metric ? MPS_TO_KMH : MPS_TO_MPH))
}

export function speedUnit(metric: boolean): string {
  return metric ? 'km/h' : 'mph'
}

/** A speed with its unit, e.g. "42 mph" or "68 km/h". */
export function formatSpeed(speedMps: number, metric: boolean = isMetricNow()): string {
  return `${speedValue(speedMps, metric)} ${speedUnit(metric)}`
}

export function setUnitPreference(preference: UnitPreference): void {
  try {
    window.localStorage.setItem(UNITS_STORAGE_KEY, preference)
  } catch {
    // Blocked storage: the choice lasts for this page only.
  }
  for (const listener of listeners) listener()
}

export function useUnitPreference(): [UnitPreference, (next: UnitPreference) => void] {
  const [preference, setPreference] = React.useState<UnitPreference>(() =>
    typeof window === 'undefined' ? 'auto' : readUnitPreference(),
  )
  React.useEffect(() => {
    const sync = () => setPreference(readUnitPreference())
    listeners.add(sync)
    return () => {
      listeners.delete(sync)
    }
  }, [])
  return [preference, setUnitPreference]
}
