// Standalone demo entry — renders MapView with mock data so the live map can be
// judged in isolation. NOT wired into App.tsx (another builder owns the shell).
//
// To run it: temporarily render <StandaloneMapDemo /> from main.tsx / App.tsx,
// e.g. `ReactDOM.createRoot(root).render(<StandaloneMapDemo />)`. The component
// fills the viewport (html/body/#root are already 100% height in styles.css).

import { useMemo, useState } from "react";
import { MapView } from "./MapView";
import type { Group, Member } from "./types";

const NOW = Date.now();
const MIN = 60_000;

/** Mock families (groups). */
const GROUPS: Group[] = [
  { id: "fam-1", name: "The Garcias", member_count: 4 },
  { id: "fam-2", name: "Tanaka Family", member_count: 4 },
  { id: "fam-3", name: "Roommates", member_count: 3 },
];

const COLORS: Record<string, string> = {
  "fam-1": "#6c2bd9",
  "fam-2": "#e91e8c",
  "fam-3": "#0a84ff",
};

const MEMBER_COLORS = [
  "#6c2bd9",
  "#e91e8c",
  "#0a84ff",
  "#34c759",
  "#ff9500",
  "#af52de",
  "#00c7be",
  "#ff2d55",
  "#5ac8fa",
  "#ffd60a",
  "#ff6b35",
  "#8e44ad",
];

/** Deterministic per-member color from the id (stable across renders). */
function memberColorFor(id: string): string {
  let h = 0;
  for (let i = 0; i < id.length; i++) h = (h * 31 + id.charCodeAt(i)) >>> 0;
  return MEMBER_COLORS[h % MEMBER_COLORS.length]!;
}

/** Mock members exercising every status + movement + clustering case. */
function makeMembers(): Member[] {
  const mk = (
    id: string,
    name: string,
    familyId: string,
    familyName: string,
    lat: number,
    lon: number,
    opts: Partial<Member> = {},
  ): Member => ({
    id,
    name,
    familyId,
    familyName,
    avatarColor: COLORS[familyId] ?? "#6c2bd9",
    memberColor: memberColorFor(id),
    position: { lat, lon },
    status: "normal",
    batteryPercent: 80,
    movement: "none",
    speedMph: null,
    lastSeen: NOW - 1 * MIN,
    address: "Stationary",
    avatarVersion: 0,
    ...opts,
  });

  return [
    // --- The Garcias (purple) — a tight cluster of three + a driver ---
    mk("g1", "Maria Garcia", "fam-1", "The Garcias", 37.7749, -122.4194, {
      status: "normal",
      batteryPercent: 92,
      lastSeen: NOW - 30_000,
      address: "Stationary",
    }),
    mk("g2", "Carlos Garcia", "fam-1", "The Garcias", 37.7751, -122.4196, {
      status: "normal",
      batteryPercent: 71,
      lastSeen: NOW - 45_000,
      address: "Stationary",
    }),
    mk("g3", "Sofia Garcia", "fam-1", "The Garcias", 37.7748, -122.4192, {
      status: "warning",
      batteryPercent: 8,
      lastSeen: NOW - 2 * MIN,
      address: "Stationary",
    }),
    mk("g4", "Diego Garcia", "fam-1", "The Garcias", 37.782, -122.418, {
      status: "normal",
      batteryPercent: 60,
      movement: "car",
      speedMph: 42,
      lastSeen: NOW - 20_000,
      address: "Driving",
    }),

    // --- Tanaka Family (pink) — driver (speeding), biker, GPS issue, stale ---
    mk("t1", "Aki Tanaka", "fam-2", "Tanaka Family", 37.79, -122.402, {
      status: "normal",
      movement: "car",
      speedMph: 78,
      batteryPercent: 55,
      lastSeen: NOW - 15_000,
      address: "Driving",
    }),
    mk("t2", "Yuki Tanaka", "fam-2", "Tanaka Family", 37.782, -122.405, {
      status: "normal",
      movement: "bike",
      batteryPercent: 64,
      lastSeen: NOW - 40_000,
      address: "Biking",
    }),
    mk("t3", "Hana Tanaka", "fam-2", "Tanaka Family", 37.768, -122.435, {
      status: "gpsIssue",
      batteryPercent: 40,
      lastSeen: NOW - 3 * MIN,
      address: "Stationary",
    }),
    mk("t4", "Kenji Tanaka", "fam-2", "Tanaka Family", 37.76, -122.45, {
      status: "stopped",
      batteryPercent: 0,
      lastSeen: NOW - 35 * MIN,
      address: "Last seen 35m ago",
    }),

    // --- Roommates (blue) — one fresh, one low battery, one never reported ---
    mk("r1", "Jordan Lee", "fam-3", "Roommates", 37.7549, -122.4374, {
      status: "normal",
      batteryPercent: 88,
      lastSeen: NOW - 10_000,
      address: "Stationary",
    }),
    mk("r2", "Sam Rivera", "fam-3", "Roommates", 37.756, -122.438, {
      status: "warning",
      batteryPercent: 12,
      lastSeen: NOW - 90_000,
      address: "Stationary",
    }),
    mk("r3", "Priya Patel", "fam-3", "Roommates", 0, 0, {
      position: null,
      status: "stopped",
      batteryPercent: 0,
      lastSeen: null,
      address: "No location yet",
    }),
  ];
}

export function StandaloneMapDemo(): JSX.Element {
  const [selectedGroupId, setSelectedGroupId] = useState<string | null>(null);
  const members = useMemo(() => makeMembers(), []);

  return (
    <div style={{ position: "fixed", inset: 0 }}>
      <MapView
        groups={GROUPS}
        members={members}
        selectedGroupId={selectedGroupId}
        onGroupChange={setSelectedGroupId}
      />
    </div>
  );
}

export default StandaloneMapDemo;
