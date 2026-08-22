package sms

import (
	"sync"
	"time"
)

// Limiter is a small in-memory sliding-window limiter for alert fan-out
// (e.g. 1 SOS per 2 minutes per user). It is not shared across API replicas.
type Limiter struct {
	mu   sync.Mutex
	hits map[string][]time.Time
}

// NewLimiter builds an empty limiter.
func NewLimiter() *Limiter {
	return &Limiter{hits: map[string][]time.Time{}}
}

// Allow records a hit when fewer than max events occurred in window.
func (l *Limiter) Allow(key string, max int, window time.Duration) bool {
	if l == nil || max <= 0 {
		return false
	}
	now := time.Now()
	cutoff := now.Add(-window)
	l.mu.Lock()
	defer l.mu.Unlock()
	prev := l.hits[key]
	kept := prev[:0]
	for _, ts := range prev {
		if ts.After(cutoff) {
			kept = append(kept, ts)
		}
	}
	if len(kept) >= max {
		l.hits[key] = kept
		return false
	}
	l.hits[key] = append(kept, now)
	return true
}
