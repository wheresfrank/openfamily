// Package sms sends optional Twilio SMS and validates E.164 numbers.
package sms

import (
	"errors"
	"regexp"
	"strings"
	"unicode"
)

var e164 = regexp.MustCompile(`^\+[1-9]\d{1,14}$`)

// ErrInvalidPhone is returned when a number is not E.164.
var ErrInvalidPhone = errors.New("phone must be E.164 (e.g. +15551234567)")

// NormalizeE164 trims formatting characters and requires a leading '+'.
// Empty input clears the number (returns "", nil).
func NormalizeE164(raw string) (string, error) {
	var b strings.Builder
	b.Grow(len(raw))
	for _, r := range strings.TrimSpace(raw) {
		if unicode.IsSpace(r) || r == '-' || r == '(' || r == ')' || r == '.' {
			continue
		}
		b.WriteRune(r)
	}
	s := b.String()
	if s == "" {
		return "", nil
	}
	if !e164.MatchString(s) {
		return "", ErrInvalidPhone
	}
	return s, nil
}
