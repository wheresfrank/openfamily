// Live-traffic overlay. Tiles are requested from the OpenFamily server
// (GET /traffic/tiles/z/x/y) with the panel's signed-in API client, so the
// traffic provider's key never reaches the browser.

import L from "leaflet";
import { getTrafficTile } from "../lib/api";

/** Wraps a tile column into the valid range for the zoom, or null when the row is off the map. */
export function normalizeTile(z: number, x: number, y: number): { z: number; x: number; y: number } | null {
  if (z < 0) return null;
  const n = 2 ** z;
  if (y < 0 || y >= n) return null;
  return { z, x: ((x % n) + n) % n, y };
}

export class TrafficTileLayer extends L.GridLayer {
  constructor(options?: L.GridLayerOptions) {
    // 512 px tiles one zoom level up cover the same area as 256 px tiles with a
    // quarter of the requests. Leaflet keeps the old zoom's tiles until the new
    // ones load, so fewer, larger tiles clear faster; updating only once the
    // zoom animation ends avoids requesting levels the user is zooming past.
    super({ tileSize: 512, updateWhenZooming: false, updateInterval: 200, keepBuffer: 1, ...options });
  }

  createTile(coords: L.Coords, done: L.DoneCallback): HTMLElement {
    const tile = document.createElement("img");
    tile.alt = "";
    tile.setAttribute("role", "presentation");
    const target = normalizeTile(coords.z - 1, coords.x, coords.y);
    if (!target) {
      window.setTimeout(() => done(undefined, tile), 0);
      return tile;
    }
    getTrafficTile(target.z, target.x, target.y)
      .then((blob) => {
        const url = URL.createObjectURL(blob);
        tile.onload = () => {
          URL.revokeObjectURL(url);
          done(undefined, tile);
        };
        tile.onerror = () => {
          URL.revokeObjectURL(url);
          done(new Error("traffic tile failed to decode"), tile);
        };
        tile.src = url;
      })
      .catch((error: unknown) => done(error instanceof Error ? error : new Error("traffic tile failed"), tile));
    return tile;
  }
}
