import React from 'react'
import ReactDOM from 'react-dom/client'
import { initI18n } from './lib/i18n'
import { initTheme } from './lib/theme'
import './styles.css'
import 'leaflet/dist/leaflet.css'

initTheme()

// The language is resolved first, and the app is imported afterwards, so
// strings evaluated at module load already use the right language.
void initI18n().then(async () => {
  const { default: App } = await import('./App')
  ReactDOM.createRoot(document.getElementById('root')!).render(
    <React.StrictMode>
      <App />
    </React.StrictMode>,
  )
})
