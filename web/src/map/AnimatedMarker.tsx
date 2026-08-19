// AnimatedMarker — a Leaflet marker that tweens between positions on live
// location updates, but does NOT animate during pan/zoom (Leaflet repositions
// markers on zoom; a CSS transform transition would make them "swim"). We track
// the previous lat/lng per marker and only tween when the position actually
// changed, giving the "alive" glide without the zoom jank.

import L from "leaflet";
import { useEffect, useRef } from "react";
import { useMap } from "react-leaflet";

interface AnimatedMarkerProps {
  position: [number, number];
  icon: L.DivIcon;
  zIndexOffset?: number;
  onClick?: () => void;
}

const TWEEN_MS = 500;

export function AnimatedMarker({
  position,
  icon,
  zIndexOffset,
  onClick,
}: AnimatedMarkerProps): null {
  const map = useMap();
  const markerRef = useRef<L.Marker | null>(null);
  const prevRef = useRef<[number, number] | null>(null);
  const rafRef = useRef<number | null>(null);
  const onClickRef = useRef(onClick);
  onClickRef.current = onClick;

  // Create the marker once on mount.
  useEffect(() => {
    const marker = L.marker(position, { icon, zIndexOffset });
    marker.addTo(map);
    marker.on("click", () => onClickRef.current?.());
    markerRef.current = marker;
    prevRef.current = position;
    return () => {
      if (rafRef.current != null) cancelAnimationFrame(rafRef.current);
      marker.remove();
      markerRef.current = null;
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Tween to the new position when it changes (live update), else snap.
  useEffect(() => {
    const marker = markerRef.current;
    if (!marker) return;
    const prev = prevRef.current;
    if (prev && (prev[0] !== position[0] || prev[1] !== position[1])) {
      if (rafRef.current != null) cancelAnimationFrame(rafRef.current);
      const start = performance.now();
      const step = (now: number) => {
        const t = Math.min(1, (now - start) / TWEEN_MS);
        const eased = 1 - Math.pow(1 - t, 3); // ease-out cubic
        marker.setLatLng([
          prev[0] + (position[0] - prev[0]) * eased,
          prev[1] + (position[1] - prev[1]) * eased,
        ]);
        if (t < 1) rafRef.current = requestAnimationFrame(step);
        else rafRef.current = null;
      };
      rafRef.current = requestAnimationFrame(step);
    } else {
      marker.setLatLng(position);
    }
    prevRef.current = position;
  }, [position]);

  // Keep the icon + z-index in sync (icon changes on status/battery/nowMs ticks).
  useEffect(() => {
    markerRef.current?.setIcon(icon);
  }, [icon]);

  useEffect(() => {
    markerRef.current?.setZIndexOffset(zIndexOffset ?? 0);
  }, [zIndexOffset]);

  return null;
}
