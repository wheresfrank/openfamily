// On-screen proximity clustering — a TypeScript port of the Flutter app's
// app/lib/utils/member_clustering.dart.
//
// Members are clustered by *screen-space* (pixel) distance at the current zoom,
// so the same set of members clusters when zoomed out and separates as the
// user zooms in — exactly the app's "cluster and separate as people move and
// the user zooms" behavior.

import type { LatLng, Member } from "./types";

/** Screen-space point (container pixels). */
export interface Pt {
  x: number;
  y: number;
}

/** A group of members whose bubbles visually overlap at the current zoom. */
export interface MemberCluster {
  /** Stable id (sorted member ids joined by '|') for tracking expanded clusters. */
  id: string;
  /** Geographic centroid (average of member positions). */
  centroid: LatLng;
  members: Member[];
}

/** A single bubble to render: a lone member, a fanned-out member, or a cluster count bubble. */
export interface BubblePlacement {
  position: LatLng;
  /** The member this bubble represents; undefined for cluster-count bubbles. */
  member?: Member;
  /** Number of members represented (>1 only for cluster-count bubbles). */
  clusterCount: number;
  /** The cluster this count bubble represents (undefined for member bubbles). */
  clusterId?: string;
  /** The members inside a cluster-count bubble (for the identity preview). */
  clusterMembers: Member[];
  readonly isCluster: boolean;
}

/** On-screen distance (px) within which two bubbles visually overlap → cluster. */
export const CLUSTER_RADIUS_PX = 48;

/** On-screen radius (px) of the fan-out ring for expanded clusters. */
export const FAN_OUT_RADIUS_PX = 60;

function distancePx(a: Pt, b: Pt): number {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

function clusterId(members: Member[]): string {
  return members
    .map((m) => m.id)
    .sort()
    .join("|");
}

function centroid(members: Member[]): LatLng {
  let lat = 0;
  let lon = 0;
  for (const m of members) {
    lat += m.position!.lat;
    lon += m.position!.lon;
  }
  return { lat: lat / members.length, lon: lon / members.length };
}

/**
 * Groups members into clusters by on-screen proximity. Each member's position
 * is projected to a screen point via `toScreenPoint` (reflecting the map's
 * current center/zoom); members within `clusterRadiusPx` of a group member are
 * merged. Members without a position are skipped (no bubble).
 *
 * Ports `clusterMembers` (transitive single-link growth, same as the app).
 */
export function clusterMembers(
  members: Member[],
  toScreenPoint: (m: Member) => Pt,
  clusterRadiusPx: number = CLUSTER_RADIUS_PX,
): MemberCluster[] {
  const positioned = members.filter((m) => m.position != null);
  const points = new Map<string, Pt>();
  for (const m of positioned) points.set(m.id, toScreenPoint(m));

  const clusters: MemberCluster[] = [];
  const remaining = [...positioned];

  while (remaining.length > 0) {
    const seed = remaining.shift()!;
    const group: Member[] = [seed];
    let changed = true;
    while (changed) {
      changed = false;
      for (let i = remaining.length - 1; i >= 0; i--) {
        const m = remaining[i]!;
        const near = group.some(
          (g) => distancePx(points.get(g.id)!, points.get(m.id)!) <= clusterRadiusPx,
        );
        if (near) {
          group.push(m);
          remaining.splice(i, 1);
          changed = true;
        }
      }
    }
    clusters.push({ id: clusterId(group), centroid: centroid(group), members: group });
  }

  return clusters;
}

/**
 * Produces a flat list of BubblePlacements:
 *  - a lone member stays at its own position;
 *  - a cluster (2+) collapses into a single cluster-count bubble at its centroid;
 *  - a cluster whose id is in `expandedClusterIds` fans out around its screen
 *    centroid (converted back to geographic positions) so each member can be
 *    tapped individually without overlapping.
 *
 * `toScreenPoint` projects a member to container pixels; `toLatLng` converts a
 * container-pixel offset back to a geographic position (for fan-out). Ports
 * `placeBubbles`.
 */
export function placeBubbles(
  members: Member[],
  toScreenPoint: (m: Member) => Pt,
  toLatLng: (p: Pt) => LatLng,
  opts: {
    clusterRadiusPx?: number;
    fanOutRadiusPx?: number;
    expandedClusterIds?: Set<string>;
  } = {},
): BubblePlacement[] {
  const clusterRadiusPx = opts.clusterRadiusPx ?? CLUSTER_RADIUS_PX;
  const fanOutRadiusPx = opts.fanOutRadiusPx ?? FAN_OUT_RADIUS_PX;
  const expanded = opts.expandedClusterIds ?? new Set<string>();

  const clusters = clusterMembers(members, toScreenPoint, clusterRadiusPx);
  const placements: BubblePlacement[] = [];

  for (const cluster of clusters) {
    if (cluster.members.length === 1) {
      const m = cluster.members[0]!;
      placements.push({
        position: m.position!,
        member: m,
        clusterCount: 1,
        clusterMembers: [],
        isCluster: false,
      });
    } else if (expanded.has(cluster.id)) {
      // Fan out around the screen-space centroid.
      let cx = 0;
      let cy = 0;
      for (const m of cluster.members) {
        const p = toScreenPoint(m);
        cx += p.x;
        cy += p.y;
      }
      cx /= cluster.members.length;
      cy /= cluster.members.length;
      for (let i = 0; i < cluster.members.length; i++) {
        const angle = (2 * Math.PI * i) / cluster.members.length;
        const p = { x: cx + Math.cos(angle) * fanOutRadiusPx, y: cy + Math.sin(angle) * fanOutRadiusPx };
        placements.push({
          position: toLatLng(p),
          member: cluster.members[i],
          clusterCount: 1,
          clusterMembers: [],
          isCluster: false,
        });
      }
    } else {
      placements.push({
        position: cluster.centroid,
        clusterCount: cluster.members.length,
        clusterId: cluster.id,
        clusterMembers: cluster.members,
        isCluster: true,
      });
    }
  }

  return placements;
}