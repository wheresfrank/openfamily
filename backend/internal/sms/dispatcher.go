package sms

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// Dispatcher sends SMS. Tests and deploys without Twilio use Noop.
type Dispatcher interface {
	Enabled() bool
	Send(ctx context.Context, to, body string) error
}

// Config is the Twilio REST credentials. Empty SID/token/from disables SMS.
type Config struct {
	AccountSID string
	AuthToken  string
	From       string
}

// New returns a Twilio dispatcher, or Noop when credentials are missing.
func New(cfg Config) Dispatcher {
	if strings.TrimSpace(cfg.AccountSID) == "" || strings.TrimSpace(cfg.AuthToken) == "" || strings.TrimSpace(cfg.From) == "" {
		return Noop{}
	}
	return &twilio{
		accountSID: strings.TrimSpace(cfg.AccountSID),
		authToken:  cfg.AuthToken,
		from:       strings.TrimSpace(cfg.From),
		client:     &http.Client{Timeout: 10 * time.Second},
	}
}

// Noop is a dispatcher that never sends. Enabled reports false.
type Noop struct{}

func (Noop) Enabled() bool { return false }

func (Noop) Send(context.Context, string, string) error { return nil }

type twilio struct {
	accountSID string
	authToken  string
	from       string
	client     *http.Client
}

func (t *twilio) Enabled() bool { return true }

func (t *twilio) Send(ctx context.Context, to, body string) error {
	to, err := NormalizeE164(to)
	if err != nil {
		return err
	}
	if to == "" {
		return ErrInvalidPhone
	}
	endpoint := fmt.Sprintf("https://api.twilio.com/2010-04-01/Accounts/%s/Messages.json", t.accountSID)
	form := url.Values{
		"To":   {to},
		"From": {t.from},
		"Body": {body},
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, strings.NewReader(form.Encode()))
	if err != nil {
		return err
	}
	req.SetBasicAuth(t.accountSID, t.authToken)
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	resp, err := t.client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 300 {
		b, _ := io.ReadAll(io.LimitReader(resp.Body, 512))
		return fmt.Errorf("sms: twilio returned %d: %s", resp.StatusCode, strings.TrimSpace(string(b)))
	}
	return nil
}
