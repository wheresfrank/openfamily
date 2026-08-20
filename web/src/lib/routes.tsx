// Route definitions shared by Sidebar, TopBar, and App.

import React from 'react'

export type RouteKey = 'dashboard' | 'families' | 'builds' | 'settings'

export interface RouteDef {
  key: RouteKey
  label: string
  /** Inline SVG icon, 20x20, inherits currentColor. */
  icon: React.ReactNode
  /** Hash fragment used for navigation. */
  hash: string
}

const icon = (path: React.ReactNode): React.ReactNode => (
  <svg width="20" height="20" viewBox="0 0 24 24" fill="none" aria-hidden="true">
    {path}
  </svg>
)

export const ROUTES: RouteDef[] = [
  {
    key: 'dashboard',
    label: 'Dashboard',
    hash: '#/dashboard',
    icon: icon(
      <path
        d="M4 13.5 12 5l8 8.5M6 12v7h12v-7"
        stroke="currentColor"
        strokeWidth="1.7"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    ),
  },
  {
    key: 'families',
    label: 'Families',
    hash: '#/families',
    icon: icon(
      <path
        d="M16 11a3 3 0 1 0-2.6-4.5M8 11a3 3 0 1 1 2.6-4.5M3 20c0-2.8 2-5 4.5-5h9C19 15 21 17.2 21 20M8 15a2.5 2.5 0 1 1 5 0"
        stroke="currentColor"
        strokeWidth="1.6"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    ),
  },
  {
    key: 'builds',
    label: 'Builds',
    hash: '#/builds',
    icon: icon(
      <path
        d="M12 3v9m0 0 3-3m-3 3L9 9M5 17v2a1 1 0 0 0 1 1h12a1 1 0 0 0 1-1v-2"
        stroke="currentColor"
        strokeWidth="1.6"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    ),
  },
  {
    key: 'settings',
    label: 'Settings',
    hash: '#/settings',
    icon: icon(
      <path
        d="M12 8.5a3.5 3.5 0 1 0 0 7 3.5 3.5 0 0 0 0-7Zm7 3.5a7 7 0 0 0-.1-1.1l1.7-1.3-1.7-3-2 .8a7 7 0 0 0-1.9-1.1L14.6 4h-3.4l-.4 2.3a7 7 0 0 0-1.9 1.1l-2-.8-1.7 3 1.7 1.3A7 7 0 0 0 6.6 12a7 7 0 0 0 .1 1.1l-1.7 1.3 1.7 3 2-.8a7 7 0 0 0 1.9 1.1l.4 2.3h3.4l.4-2.3a7 7 0 0 0 1.9-1.1l2 .8 1.7-3-1.7-1.3c.06-.36.1-.73.1-1.1Z"
        stroke="currentColor"
        strokeWidth="1.5"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    ),
  },
]

export const DEFAULT_ROUTE: RouteKey = 'dashboard'

export function routeFromHash(hash: string): RouteKey {
  const match = ROUTES.find((r) => hash === r.hash || hash.startsWith(r.hash))
  return match ? match.key : DEFAULT_ROUTE
}