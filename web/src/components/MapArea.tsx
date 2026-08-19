// Renders the live map (src/map/MapView) in self-managed mode: the map fetches
// its own families + members and streams live updates, so the shell only needs
// to hand it the access token.

import MapView from '../map/MapView'
import { getAccessToken } from '../lib/auth'
import './MapArea.css'

export function MapArea() {
  const token = getAccessToken()

  if (!token) {
    return (
      <div className="wb-maparea wb-maparea-loading">
        <span className="wb-maparea-loading-text">Sign in to view the live map.</span>
      </div>
    )
  }

  return (
    <div className="wb-maparea">
      <MapView token={token} />
    </div>
  )
}
