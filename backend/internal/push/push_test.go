package push

import (
	"net"
	"testing"
)

// TestIsDisallowedIP covers the standard non-public ranges plus the CGNAT and
// benchmark ranges that net.IP.IsPrivate does not report.
func TestIsDisallowedIP(t *testing.T) {
	cases := []struct {
		ip         string
		disallowed bool
	}{
		// Standard non-public ranges (already covered before the fix).
		{"127.0.0.1", true},
		{"10.1.2.3", true},
		{"172.16.0.9", true},
		{"192.168.1.1", true},
		{"169.254.169.254", true}, // link-local (metadata service)
		{"0.0.0.0", true},
		{"224.0.0.1", true}, // multicast
		{"fc00::1", true},   // IPv6 ULA
		{"fe80::1", true},   // IPv6 link-local
		{"::1", true},

		// CGNAT / shared address space (RFC 6598) — the WB-001 gap.
		{"100.64.0.1", true},
		{"100.100.100.100", true}, // TailscaleMagicDNS range inside 100.64/10
		{"100.127.255.254", true},
		// Just outside the CGNAT range: must stay allowed.
		{"100.63.255.255", false},
		{"100.128.0.1", false},

		// Benchmark space (RFC 2544).
		{"198.18.0.1", true},
		{"198.19.255.255", true},
		{"198.20.0.1", false},

		// Public addresses must remain allowed.
		{"8.8.8.8", false},
		{"1.1.1.1", false},
		{"2606:4700:4700::1111", false},

		// IPv4-mapped IPv6 forms of disallowed ranges.
		{"::ffff:100.64.0.1", true},
		{"::ffff:10.0.0.5", true},
		{"::ffff:8.8.8.8", false},
	}
	for _, tc := range cases {
		got := isDisallowedIP(net.ParseIP(tc.ip))
		if got != tc.disallowed {
			t.Errorf("isDisallowedIP(%s) = %v, want %v", tc.ip, got, tc.disallowed)
		}
	}
}

// TestIsDisallowedIPNil ensures unparseable input fails closed.
func TestIsDisallowedIPNil(t *testing.T) {
	if !isDisallowedIP(nil) {
		t.Error("isDisallowedIP(nil) = false, want true")
	}
}
