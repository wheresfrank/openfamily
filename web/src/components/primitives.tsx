// Shared UI primitives — Button, Card, Badge, Spinner, EmptyState, ErrorState.
// Stateless, accessible, styled entirely with the CSS variables in styles.css.

import React from 'react'
import './primitives.css'

// ---- Button ----

type ButtonVariant = 'primary' | 'secondary' | 'ghost' | 'danger'
type ButtonSize = 'sm' | 'md'

interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: ButtonVariant
  size?: ButtonSize
  loading?: boolean
  icon?: React.ReactNode
}

export function Button({
  variant = 'primary',
  size = 'md',
  loading = false,
  icon,
  children,
  className,
  disabled,
  ...rest
}: ButtonProps) {
  const cls = [
    'wb-btn',
    `wb-btn-${variant}`,
    `wb-btn-${size}`,
    className ?? '',
  ]
    .filter(Boolean)
    .join(' ')
  return (
    <button
      className={cls}
      disabled={disabled || loading}
      aria-busy={loading || undefined}
      {...rest}
    >
      {loading ? <Spinner size={size === 'sm' ? 14 : 16} /> : icon}
      {children && <span className="wb-btn-label">{children}</span>}
    </button>
  )
}

// ---- Card ----

interface CardProps extends React.HTMLAttributes<HTMLDivElement> {
  padded?: boolean
}

export function Card({ padded = true, className, children, ...rest }: CardProps) {
  return (
    <div className={`wb-card ${padded ? 'wb-card-padded' : ''} ${className ?? ''}`} {...rest}>
      {children}
    </div>
  )
}

// ---- Badge ----

type BadgeTone =
  | 'neutral'
  | 'purple'
  | 'pink'
  | 'green'
  | 'orange'
  | 'grey'
  | 'red'

interface BadgeProps {
  tone?: BadgeTone
  dot?: boolean
  children: React.ReactNode
  title?: string
}

export function Badge({ tone = 'neutral', dot = false, children, title }: BadgeProps) {
  return (
    <span className={`wb-badge wb-badge-${tone}`} title={title}>
      {dot && <span className="wb-badge-dot" />}
      {children}
    </span>
  )
}

// ---- Spinner ----

interface SpinnerProps {
  size?: number
  className?: string
}

export function Spinner({ size = 18, className }: SpinnerProps) {
  return (
    <span
      className={`wb-spinner ${className ?? ''}`}
      style={{ width: size, height: size }}
      role="status"
      aria-label="Loading"
    >
      <span className="wb-spinner-ring" style={{ borderWidth: Math.max(2, Math.round(size / 9)) }} />
    </span>
  )
}

// ---- EmptyState ----

interface EmptyStateProps {
  title: string
  description?: string
  icon?: React.ReactNode
  action?: React.ReactNode
}

export function EmptyState({ title, description, icon, action }: EmptyStateProps) {
  return (
    <div className="wb-empty">
      <div className="wb-empty-icon">{icon ?? <EmptyIcon />}</div>
      <h3 className="wb-empty-title">{title}</h3>
      {description && <p className="wb-empty-desc">{description}</p>}
      {action && <div className="wb-empty-action">{action}</div>}
    </div>
  )
}

function EmptyIcon() {
  return (
    <svg width="28" height="28" viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <path
        d="M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18Zm0 5v4m0 3.5h.01"
        stroke="currentColor"
        strokeWidth="1.6"
        strokeLinecap="round"
        strokeLinejoin="round"
      />
    </svg>
  )
}

// ---- ErrorState ----

interface ErrorStateProps {
  title?: string
  description?: string
  onRetry?: () => void
}

export function ErrorState({ title = 'Something went wrong', description, onRetry }: ErrorStateProps) {
  return (
    <div className="wb-error">
      <div className="wb-error-icon">
        <svg width="26" height="26" viewBox="0 0 24 24" fill="none" aria-hidden="true">
          <path
            d="M12 8v5m0 3.5h.01M10.3 3.9 2.7 17a2 2 0 0 0 1.7 3h15.2a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0Z"
            stroke="currentColor"
            strokeWidth="1.6"
            strokeLinecap="round"
            strokeLinejoin="round"
          />
        </svg>
      </div>
      <h3 className="wb-error-title">{title}</h3>
      {description && <p className="wb-error-desc">{description}</p>}
      {onRetry && (
        <Button variant="secondary" size="sm" onClick={onRetry}>
          Try again
        </Button>
      )}
    </div>
  )
}

// ---- AccessDenied (403) ----

export function AccessDenied({ message }: { message?: string }) {
  return (
    <ErrorState
      title="You don't have admin access"
      description={
        message ??
        'Your account is not permitted to view this admin panel. Contact an administrator if you believe this is a mistake.'
      }
    />
  )
}

// ---- Kbd (keyboard hint, e.g. ⌘K) ----

export function Kbd({ children }: { children: React.ReactNode }) {
  return <kbd className="wb-kbd">{children}</kbd>
}

// ---- Mono (inline monospaced text for IDs / numbers / timestamps) ----

interface MonoProps extends React.HTMLAttributes<HTMLSpanElement> {
  /** Truncate strategy for long values. */
  truncate?: 'none' | 'middle' | 'end'
  /** For middle/end truncation, the max visible characters before truncating. */
  max?: number
}

export function Mono({ truncate = 'none', max = 28, className, children, title, ...rest }: MonoProps) {
  const raw = typeof children === 'string' ? children : ''
  const cls = ['wb-mono', `wb-mono-truncate-${truncate}`, className ?? '']
    .filter(Boolean)
    .join(' ')

  let display = raw
  if (truncate === 'middle' && raw.length > max) {
    const head = Math.ceil((max - 1) * 0.6)
    const tail = Math.max(0, max - 1 - head)
    display = `${raw.slice(0, head)}…${raw.slice(raw.length - tail)}`
  } else if (truncate === 'end' && raw.length > max) {
    display = `${raw.slice(0, max - 1)}…`
  }

  const resolvedTitle = title ?? (truncate !== 'none' && raw ? raw : undefined)

  return (
    <span className={cls} title={resolvedTitle} {...rest}>
      {display}
    </span>
  )
}

// ---- CopyButton ----

interface CopyButtonProps {
  /** The text to copy to the clipboard. */
  value: string
  /** Accessible label announced to screen readers. */
  label?: string
  size?: ButtonSize
}

export function CopyButton({ value, label, size = 'sm' }: CopyButtonProps) {
  const [copied, setCopied] = React.useState(false)
  const timerRef = React.useRef<number | null>(null)

  React.useEffect(() => () => {
    if (timerRef.current) window.clearTimeout(timerRef.current)
  }, [])

  const onClick = async () => {
    try {
      await navigator.clipboard.writeText(value)
    } catch {
      // Fallback for non-secure contexts / older browsers.
      const ta = document.createElement('textarea')
      ta.value = value
      ta.style.position = 'fixed'
      ta.style.opacity = '0'
      document.body.appendChild(ta)
      ta.select()
      try {
        document.execCommand('copy')
      } catch {
        // give up silently
      }
      ta.remove()
    }
    setCopied(true)
    if (timerRef.current) window.clearTimeout(timerRef.current)
    timerRef.current = window.setTimeout(() => setCopied(false), 1400)
  }

  return (
    <button
      type="button"
      className={`wb-copy-btn wb-copy-btn-${size}`}
      onClick={onClick}
      aria-label={label ?? 'Copy to clipboard'}
      title={label ?? 'Copy to clipboard'}
    >
      {copied ? <CheckIcon /> : <CopyIcon />}
    </button>
  )
}

function CopyIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <rect x="9" y="9" width="11" height="11" rx="2" stroke="currentColor" strokeWidth="1.7" />
      <path d="M5 15V6a2 2 0 0 1 2-2h9" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" />
    </svg>
  )
}

function CheckIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" aria-hidden="true">
      <path d="m5 12.5 4.5 4.5L19 7" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}