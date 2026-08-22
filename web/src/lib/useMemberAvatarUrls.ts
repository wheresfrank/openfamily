import { useEffect, useMemo, useRef, useState } from 'react'

/** Minimal avatar metadata carried by a member response. */
export interface MemberAvatarSource {
  id: string
  hasAvatar: boolean | undefined
  avatarUpdatedAt: string | null | undefined
  /** Durable server-side revision; this, not a timestamp, keys image bytes. */
  avatarVersion: number | undefined
}

export type MemberAvatarLoader = (memberId: string) => Promise<Blob>

interface AvatarRecord {
  sourceKey: string
  url: string
}

export interface UseMemberAvatarUrlsOptions {
  /** Prevent requests and release any existing object URLs while disabled. */
  enabled?: boolean
  /** Changes when the authenticated session or API origin changes. */
  cacheKey?: string
}

function sourceKey(source: MemberAvatarSource, cacheKey: string): string {
  return JSON.stringify([cacheKey, source.id, source.hasAvatar === true, source.avatarVersion ?? 0])
}

function toUrlMap(records: Map<string, AvatarRecord>): Record<string, string> {
  return Object.fromEntries([...records].map(([memberId, record]) => [memberId, record.url]))
}

function revokeRecords(records: Map<string, AvatarRecord>): void {
  for (const { url } of records.values()) URL.revokeObjectURL(url)
  records.clear()
}

/**
 * Loads private member avatars into short-lived object URLs. A source's update
 * revision invalidates only that avatar; removed members and unmounting revoke
 * their URLs so browser memory is not retained by the map or family list.
 */
export function useMemberAvatarUrls(
  sources: readonly MemberAvatarSource[],
  loadAvatar: MemberAvatarLoader,
  { enabled = true, cacheKey = '' }: UseMemberAvatarUrlsOptions = {},
): Record<string, string> {
  const recordsRef = useRef(new Map<string, AvatarRecord>())
  const sourcesRef = useRef(sources)
  sourcesRef.current = sources
  const [urls, setUrls] = useState<Record<string, string>>({})

  // The source array can be recreated for live location updates. Restrict the
  // effect to the fields that can actually change an avatar.
  const sourceSignature = useMemo(
    () =>
      JSON.stringify(
        sources
          .filter((source) => source.id !== '')
          .map((source) => [source.id, source.hasAvatar === true, source.avatarVersion ?? 0])
          .sort(([a], [b]) => String(a).localeCompare(String(b))),
      ),
    [sources],
  )

  useEffect(() => {
    let active = true
    const wanted = new Map<string, string>()

    if (enabled) {
      for (const source of sourcesRef.current) {
        if (source.id !== '' && source.hasAvatar === true) {
          wanted.set(source.id, sourceKey(source, cacheKey))
        }
      }
    }

    const records = recordsRef.current
    for (const [memberId, record] of records) {
      if (wanted.get(memberId) !== record.sourceKey) {
        URL.revokeObjectURL(record.url)
        records.delete(memberId)
      }
    }
    setUrls(toUrlMap(records))

    for (const [memberId, recordSourceKey] of wanted) {
      if (records.has(memberId)) continue
      void loadAvatar(memberId)
        .then((blob) => {
          if (!active || blob.size === 0) return
          const url = URL.createObjectURL(blob)
          if (!active || wanted.get(memberId) !== recordSourceKey) {
            URL.revokeObjectURL(url)
            return
          }
          const current = recordsRef.current.get(memberId)
          if (current) URL.revokeObjectURL(current.url)
          recordsRef.current.set(memberId, { sourceKey: recordSourceKey, url })
          setUrls(toUrlMap(recordsRef.current))
        })
        .catch(() => {
          // A deleted avatar can briefly race its metadata update. Keep the
          // initials fallback rather than surfacing an image fetch error here.
        })
    }

    return () => {
      active = false
    }
  }, [cacheKey, enabled, loadAvatar, sourceSignature])

  useEffect(
    () => () => {
      revokeRecords(recordsRef.current)
    },
    [],
  )

  return urls
}
