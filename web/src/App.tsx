// App root — auth gate + hash routing + the authenticated shell.
//
// When unauthenticated: render the login screen.
// When authenticated: render the sidebar + top bar shell with the active page.

import React from 'react'
import { Sidebar } from './components/Sidebar'
import { TopBar } from './components/TopBar'
import { LoginPage } from './pages/LoginPage'
import { DashboardPage } from './pages/DashboardPage'
import { GroupsPage } from './pages/GroupsPage'
import { BuildsPage } from './pages/BuildsPage'
import { SettingsPage } from './pages/SettingsPage'
import { DEFAULT_ROUTE, routeFromHash, type RouteKey } from './lib/routes'
import { clearTokens, getEmail, isAuthenticated, subscribeAuth } from './lib/auth'
import './shell.css'

export default function App() {
  // Re-render when auth changes (login, logout, cross-tab, failed refresh).
  const [, force] = React.useReducer((n: number) => n + 1, 0)
  React.useEffect(() => subscribeAuth(force), [force])

  // Hash-based routing.
  const [route, setRoute] = React.useState<RouteKey>(() =>
    routeFromHash(typeof window !== 'undefined' ? window.location.hash : ''),
  )
  React.useEffect(() => {
    const onHash = () => setRoute(routeFromHash(window.location.hash))
    window.addEventListener('hashchange', onHash)
    // Ensure a sensible default hash on first load.
    if (!window.location.hash) window.location.hash = `#/${DEFAULT_ROUTE}`
    return () => window.removeEventListener('hashchange', onHash)
  }, [])

  const navigate = React.useCallback((key: RouteKey) => {
    const hash = `#/${key}`
    if (window.location.hash !== hash) window.location.hash = hash
    setRoute(key)
  }, [])

  const logout = React.useCallback(() => {
    clearTokens()
  }, [])

  if (!isAuthenticated()) {
    return <LoginPage onLoggedIn={() => {}} />
  }

  const email = getEmail()

  return (
    <div className="wb-shell">
      <div className="wb-shell-sidebar">
        <Sidebar active={route} onNavigate={navigate} footer={<span>v0.1</span>} />
      </div>
      <div className="wb-shell-topbar">
        <TopBar active={route} onLogout={logout} email={email} onNavigate={navigate} />
      </div>
      <main className="wb-shell-content" id="wb-content">
        {renderPage(route, email, logout)}
      </main>
    </div>
  )
}

function renderPage(route: RouteKey, email: string | null, logout: () => void): React.ReactNode {
  switch (route) {
    case 'dashboard':
      return <DashboardPage />
    case 'groups':
      return <GroupsPage />
    case 'builds':
      return <BuildsPage />
    case 'settings':
      return <SettingsPage email={email} onLogout={logout} />
    default:
      return <DashboardPage />
  }
}