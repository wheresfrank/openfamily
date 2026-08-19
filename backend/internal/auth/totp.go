package auth

import (
	"fmt"
	"time"

	"github.com/pquerna/otp/totp"
)

// GenerateTOTPSecret creates a new TOTP secret for a user and returns the
// base32 secret plus a provisioning URI for the authenticator app.
func GenerateTOTPSecret(issuer, account string) (secret string, uri string, err error) {
	key, err := totp.Generate(totp.GenerateOpts{
		Issuer:      issuer,
		AccountName: account,
	})
	if err != nil {
		return "", "", fmt.Errorf("generate totp: %w", err)
	}
	return key.Secret(), key.URL(), nil
}

// ValidateTOTP checks a user-supplied code against a stored base32 secret.
func ValidateTOTP(secret, code string) bool {
	return totp.Validate(code, secret)
}

// ValidateTOTPWithSkew checks a code allowing a small time-step skew.
func ValidateTOTPWithSkew(secret, code string, skew uint) bool {
	ok, err := totp.ValidateCustom(code, secret, time.Now(), totp.ValidateOpts{Skew: skew})
	if err != nil {
		return false
	}
	return ok
}
