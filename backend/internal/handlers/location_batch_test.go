package handlers

import (
	"testing"
	"time"
)

// batchPoint helper: ts minutesRelative before `now` (negative = future).
func mkBatchPoint(now time.Time, minutesBefore int, lat float64) batchPoint {
	ts := now.Add(time.Duration(-minutesBefore) * time.Minute)
	return batchPoint{
		DeviceID: "dev-1",
		TS:       &ts,
		Lat:      lat,
		Lon:      11.0,
		Source:   "background",
	}
}

func TestFilterBatchPoints(t *testing.T) {
	now := time.Date(2026, 8, 25, 12, 0, 0, 0, time.UTC)

	points := []batchPoint{
		mkBatchPoint(now, 10, 47.0),        // fresh: kept
		mkBatchPoint(now, 60, 47.0),        // 1h old: kept (live feed would reject)
		mkBatchPoint(now, 24*60, 47.0),     // 24h old: kept (< batchMaxAge)
		mkBatchPoint(now, 8*24*60, 47.0),   // 8d old: rejected (> batchMaxAge)
		mkBatchPoint(now, -90, 47.0),       // 90m in the future: rejected (> maxTSSkew)
		{DeviceID: "dev-1", TS: nil, Lat: 47.0, Lon: 11.0}, // no ts: resolved to now
		{DeviceID: "dev-1", TS: mkBatchPoint(now, 0, 0).TS, Lat: 200.0, Lon: 11.0}, // bad lat
	}

	kept, rejected := filterBatchPoints(points, now)
	if len(kept) != 4 {
		t.Fatalf("expected 4 kept, got %d", len(kept))
	}
	if rejected != 3 {
		t.Fatalf("expected 3 rejected, got %d", rejected)
	}

	// A missing ts must have been resolved to a concrete timestamp (the
	// no-ts input lands at kept[3] after the three rejects before it —
	// fresh, 1h, 24h, ..., input order is preserved).
	if kept[3].TS == nil {
		t.Fatal("missing ts should be resolved, not nil")
	}

	// The kept points must be safe to dereference even after filtering.
	for _, p := range kept {
		if p.TS == nil {
			t.Fatal("kept point lost its timestamp")
		}
	}
}

func TestFilterBatchPointsEmpty(t *testing.T) {
	now := time.Date(2026, 8, 25, 12, 0, 0, 0, time.UTC)
	kept, rejected := filterBatchPoints(nil, now)
	if len(kept) != 0 || rejected != 0 {
		t.Fatalf("empty input: kept=%d rejected=%d", len(kept), rejected)
	}
}

func TestBatchKeptDeduplicates(t *testing.T) {
	now := time.Date(2026, 8, 25, 12, 0, 0, 0, time.UTC)

	p1 := mkBatchPoint(now, 30, 47.0)
	p2 := mkBatchPoint(now, 20, 47.0)
	p3 := mkBatchPoint(now, 20, 47.0) // Same ts as p2: duplicate within batch.
	p4 := mkBatchPoint(now, 40, 47.0) // Already stored server-side.

	// p4's exact ts is present in the existing set.
	existing := map[string]struct{}{
		p4.TS.UTC().Format(time.RFC3339Nano): {},
	}

	kept, skipped := batchKept([]batchPoint{p1, p2, p3, p4}, existing)
	if len(kept) != 2 {
		t.Fatalf("expected 2 kept, got %d", len(kept))
	}
	if !kept[0].TS.Equal(p1.TS.UTC()) {
		t.Fatal("p1 (new) should be kept")
	}
	if kept, _ := batchKept([]batchPoint{p1, p2, p3, p4}, existing); len(kept) != 2 {
		t.Fatalf("idempotent repeat changed result: %d", len(kept))
	}
	if skipped != 2 {
		t.Fatalf("expected 2 skipped (one in-batch dup, one already stored), got %d", skipped)
	}
}

func TestBatchKeptAllAlreadyStored(t *testing.T) {
	now := time.Date(2026, 8, 25, 12, 0, 0, 0, time.UTC)
	p := mkBatchPoint(now, 5, 47.0)
	existing := map[string]struct{}{
		p.TS.UTC().Format(time.RFC3339Nano): {},
	}
	kept, skipped := batchKept([]batchPoint{p}, existing)
	if len(kept) != 0 || skipped != 1 {
		t.Fatalf("expected all skipped, kept=%d skipped=%d", len(kept), skipped)
	}
}

func TestBatchTSKeysNilSafeInput(t *testing.T) {
	now := time.Date(2026, 8, 25, 12, 0, 0, 0, time.UTC)
	p := mkBatchPoint(now, 0, 47.0)
	if len(batchTSKeys([]batchPoint{p})) != 1 {
		t.Fatal("expected one key")
	}
}