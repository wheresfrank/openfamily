package auth

import (
	"testing"
	"time"
)

func TestIssueAndParseTokenVersion(t *testing.T) {
	tm := NewTokenManager("test-secret-at-least-32-bytes-long!", time.Minute, time.Hour)
	access, err := tm.IssueAccess("user-1", "fam-1", 3)
	if err != nil {
		t.Fatal(err)
	}
	claims, err := tm.Parse(access, AccessToken)
	if err != nil {
		t.Fatal(err)
	}
	if claims.UserID != "user-1" || claims.FamilyID != "fam-1" || claims.TokenVersion != 3 {
		t.Fatalf("claims=%+v", claims)
	}

	refresh, err := tm.IssueRefresh("user-1", "fam-1", 3)
	if err != nil {
		t.Fatal(err)
	}
	refreshClaims, err := tm.Parse(refresh, RefreshToken)
	if err != nil {
		t.Fatal(err)
	}
	if refreshClaims.TokenVersion != 3 {
		t.Fatalf("refresh ver=%d", refreshClaims.TokenVersion)
	}
}
