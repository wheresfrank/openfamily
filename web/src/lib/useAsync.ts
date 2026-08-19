// Tiny async-data hook used by pages. Handles loading/error/data states and
// supports manual refetch. Errors are normalized to { status, message }.

import React from 'react'
import { ApiError, result as wrapResult } from './api'
import type { ApiResult } from './types'

export interface AsyncState<T> {
  loading: boolean
  data: T | null
  error: { status: number; message: string } | null
}

export function useAsync<T>(
  fn: () => Promise<T>,
  deps: React.DependencyList,
): AsyncState<T> & {
  refetch: () => void
} {
  const [state, setState] = React.useState<AsyncState<T>>({
    loading: true,
    data: null,
    error: null,
  })
  const fnRef = React.useRef(fn)
  fnRef.current = fn
  const [nonce, setNonce] = React.useState(0)

  React.useEffect(() => {
    let cancelled = false
    setState((s) => ({ ...s, loading: true }))
    fnRef
      .current()
      .then((value) => {
        if (cancelled) return
        setState({ loading: false, data: value, error: null })
      })
      .catch((e) => {
        if (cancelled) return
        const err =
          e instanceof ApiError
            ? { status: e.status, message: e.message }
            : { status: 0, message: e instanceof Error ? e.message : 'Network error' }
        setState({ loading: false, data: null, error: err })
      })
    return () => {
      cancelled = true
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [...deps, nonce])

  return {
    ...state,
    refetch: () => setNonce((n) => n + 1),
  }
}

/** Convenience: classify an error as a 403 access-denied case. */
export function isAccessDenied(err: { status: number } | null): boolean {
  return err?.status === 403
}

/** Run an async side-effect and get a structured ApiResult (never throws). */
export async function safeRun<T>(p: Promise<T>): Promise<ApiResult<T>> {
  return wrapResult(p)
}