package handlers

import (
	"strings"
	"testing"

	"github.com/whereabouts/whereabouts/backend/internal/models"
)

func TestNormalizeAdminFamilyName(t *testing.T) {
	got, err := normalizeAdminFamilyName("  The Smiths  ")
	if err != nil {
		t.Fatalf("normalizeAdminFamilyName returned error: %v", err)
	}
	if got != "The Smiths" {
		t.Fatalf("got %q, want %q", got, "The Smiths")
	}
}

func TestNormalizeAdminFamilyNameRejectsBlankAndOversizedNames(t *testing.T) {
	cases := []string{"", "   ", strings.Repeat("x", 121)}
	for _, input := range cases {
		if _, err := normalizeAdminFamilyName(input); err == nil {
			t.Errorf("normalizeAdminFamilyName(%q) accepted invalid name", input)
		}
	}
}

func TestValidateAdminUserInput(t *testing.T) {
	valid, err := validateAdminUserInput(" frank@example.com ", "strong-password", " Frank ", models.RoleMember)
	if err != nil {
		t.Fatalf("valid input rejected: %v", err)
	}
	if valid.Email != "frank@example.com" || valid.Name != "Frank" {
		t.Fatalf("input was not normalized: %+v", valid)
	}

	cases := []struct {
		name     string
		email    string
		password string
		username string
		role     models.Role
	}{
		{"blank email", " ", "strong-password", "Frank", models.RoleMember},
		{"invalid email", "not-an-email", "strong-password", "Frank", models.RoleMember},
		{"short password", "frank@example.com", "short", "Frank", models.RoleMember},
		{"blank name", "frank@example.com", "strong-password", " ", models.RoleMember},
		{"invalid role", "frank@example.com", "strong-password", "Frank", models.Role("owner")},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if _, err := validateAdminUserInput(tc.email, tc.password, tc.username, tc.role); err == nil {
				t.Fatalf("accepted invalid input")
			}
		})
	}
}
