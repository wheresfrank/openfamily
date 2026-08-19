// Left navigation sidebar.

import React from 'react'
import { ROUTES, type RouteKey } from '../lib/routes'
import './nav.css'

interface SidebarProps {
  active: RouteKey
  onNavigate: (key: RouteKey) => void
  /** Optional small footer label, e.g. version. */
  footer?: React.ReactNode
}

export function Sidebar({ active, onNavigate, footer }: SidebarProps) {
  return (
    <aside className="wb-sidebar" aria-label="Main navigation">
      <div className="wb-brand">
        <span className="wb-brand-mark" aria-hidden="true">
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none">
            <path
              d="M12 2.5c4.4 0 8 3.5 8 7.8 0 5.6-8 11.2-8 11.2s-8-5.6-8-11.2c0-4.3 3.6-7.8 8-7.8Z"
              fill="url(#wb-grad)"
            />
            <circle cx="12" cy="10.3" r="2.7" fill="#fff" />
            <defs>
              <linearGradient id="wb-grad" x1="4" y1="2.5" x2="20" y2="21.5" gradientUnits="userSpaceOnUse">
                <stop stopColor="#6c2bd9" />
                <stop offset="1" stopColor="#e91e8c" />
              </linearGradient>
            </defs>
          </svg>
        </span>
        <span className="wb-brand-name">Whereabouts</span>
        <span className="wb-brand-sub">Admin</span>
      </div>

      <nav className="wb-nav">
        {ROUTES.map((r) => {
          const isActive = r.key === active
          return (
            <a
              key={r.key}
              href={r.hash}
              className={`wb-nav-item ${isActive ? 'is-active' : ''}`}
              aria-current={isActive ? 'page' : undefined}
              onClick={(e) => {
                e.preventDefault()
                onNavigate(r.key)
              }}
            >
              <span className="wb-nav-icon">{r.icon}</span>
              <span className="wb-nav-label">{r.label}</span>
              {isActive && <span className="wb-nav-active-bar" aria-hidden="true" />}
            </a>
          )
        })}
      </nav>

      {footer && <div className="wb-sidebar-footer">{footer}</div>}
    </aside>
  )
}