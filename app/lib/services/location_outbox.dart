import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';

/// Sends one drained batch to the backend via the foreground API client
/// (Bearer token + 401→refresh path). The default [OutboxSend] for
/// foreground callers; the background isolate uses its own ingest-key sender
/// instead. Returns true only on 2xx — a session-expired redirect or any
/// failure keeps the queue untouched for the next drain.
Future<bool> sendOutboxBatchViaApi(List<Map<String, dynamic>> batch) async {
  try {
    await ApiClient.post(
      '/locations/batch',
      body: LocationOutbox.batchBody(batch),
    );
    return true;
  } catch (_) {
    return false;
  }
}

/// Sends one drained batch to the backend. MUST resolve `true` only when the
/// server accepted the batch (2xx); `false` on any failure (transport error,
/// 4xx, 5xx). Drained points are removed from the queue only on `true`, so a
/// crash between send and removal re-sends duplicates — the batch endpoint
/// dedupes by (device_id, ts), making retries idempotent.
typedef OutboxSend = Future<bool> Function(List<Map<String, dynamic>> points);

/// Prunes an outbox list to the queue limits: drops records older than
/// [maxAge], then evicts oldest-first while over [maxPoints]. Pure function,
/// exported for tests.
List<Map<String, dynamic>> locationOutboxPruneList(
  List<Map<String, dynamic>> points, {
  required DateTime now,
  int maxPoints = 720,
  Duration maxAge = const Duration(hours: 48),
}) {
  final List<Map<String, dynamic>> kept = <Map<String, dynamic>>[];
  for (final Map<String, dynamic> p in points) {
    final DateTime? ts = _parseTs(p['ts']);
    if (ts == null || now.difference(ts) > maxAge) {
      continue; // Missing or expired timestamp: drop permanently.
    }
    kept.add(p);
  }
  while (kept.length > maxPoints) {
    kept.removeAt(_oldestIndex(kept));
  }
  return kept;
}

/// Selects the next drain batch, newest first, so the freshest position is
/// delivered before history and the live map converges quickly. Pure
/// function, exported for tests.
List<Map<String, dynamic>> locationOutboxSelectBatch(
  List<Map<String, dynamic>> points,
  int maxPerCall,
) {
  final List<Map<String, dynamic>> sorted =
      List<Map<String, dynamic>>.of(points)..sort(_compareTsDesc);
  if (sorted.length <= maxPerCall) return sorted;
  return sorted.sublist(0, maxPerCall);
}

int _compareTsDesc(Map<String, dynamic> a, Map<String, dynamic> b) {
  final DateTime? ta = _parseTs(a['ts']);
  final DateTime? tb = _parseTs(b['ts']);
  if (ta == null && tb == null) return 0;
  if (ta == null) return 1; // Unparseable entries drain last.
  if (tb == null) return -1;
  return tb.compareTo(ta); // Descending.
}

int _oldestIndex(List<Map<String, dynamic>> points) {
  int worst = 0;
  for (int i = 1; i < points.length; i++) {
    if (_compareTsDesc(points[worst], points[i]) < 0) {
      worst = i; // points[i] is older than the current worst.
    }
  }
  return worst;
}

DateTime? _parseTs(Object? raw) {
  if (raw is! String || raw.isEmpty) return null;
  return DateTime.tryParse(raw)?.toUtc();
}

/// A bounded store-and-forward queue for location reports that could not be
/// delivered while the device was offline (hikes, tunnels, road trips).
///
/// Failed reports are kept on-device and replayed via `POST /locations/batch`
/// once connectivity returns, so the family's history shows the actual track
/// through the dead zone instead of a hole.
///
/// Participation model:
/// - the background isolate (`background_location_service.dart`) enqueues any
///   fix whose POST fails and drains whenever a report succeeds;
/// - the foreground reporter (`location_reporter.dart`) does the same for its
///   own stream, using the same storage;
/// - the map screen drains opportunistically when the OS reports the network
///   back.
///
/// Storage is one JSON list under a `shared_preferences` key: small enough
/// for the cap (≤720 records ≈ low hundreds of KB), readable from both
/// isolates with no extra plugins, and last-write-wins. The failure mode of a
/// same-instant cross-isolate race is a lost or duplicated point — never a
/// wrong or replayed-with-forgery point, and the backend dedupes duplicates.
/// Cross-isolate staleness of the per-isolate prefs cache is mitigated by
/// reloading before every read; the residual race window is milliseconds
/// wide and self-healing.
///
/// Every method is deliberately non-throwing: reporting paths must never
/// crash because the repair queue misbehaved.
class LocationOutbox {
  LocationOutbox._();

  static const String _key = 'location_outbox_v1';

  /// Hard cap on queued records (~12h of 60s background fixes). Keeps prefs
  /// writes small; a multi-day trip backfills its most recent day only with
  /// the default sampling cadence.
  static const int maxPoints = 720;

  /// Hard age limit: records older than this are dropped on enqueue and on
  /// drain. Beyond ~2 days the battery/bandwidth value of a coarse 60s track
  /// fades fast, and the server accepts up to 7 days.
  static const Duration maxAge = Duration(hours: 48);

  static const int defaultMaxPerCall = 100;

  /// Queues one failed report body (the exact `POST /locations` JSON body).
  /// Dedupes by `ts` so a flapping connection cannot grow the queue with
  /// retries of the same fix.
  static Future<void> enqueue(Map<String, dynamic> point) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final List<Map<String, dynamic>> points = _decode(prefs.getString(_key));
      final Object? ts = point['ts'];
      points.removeWhere((Map<String, dynamic> p) => p['ts'] == ts);
      points.add(point);
      await prefs.setString(
        _key,
        jsonEncode(
          locationOutboxPruneList(points, now: DateTime.now().toUtc()),
        ),
      );
    } catch (_) {
      // Storage failure must never break the reporting path.
    }
  }

  /// Drains up to [maxPerCall] records through [send], newest first. Returns
  /// the number of records removed. Removal happens only after [send]
  /// resolves `true`; a later crash re-sends a duplicate that the backend
  /// drops idempotently.
  static Future<int> drain({
    required OutboxSend send,
    int maxPerCall = defaultMaxPerCall,
  }) async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final List<Map<String, dynamic>> points = _decode(prefs.getString(_key));
      if (points.isEmpty) return 0;
      final List<Map<String, dynamic>> batch =
          locationOutboxSelectBatch(points, maxPerCall);
      final bool ok = await send(batch);
      if (!ok) return 0;
      final Set<Object?> sentTs = batch
          .map((Map<String, dynamic> p) => p['ts'])
          .toSet();
      final List<Map<String, dynamic>> remaining = points
          .where((Map<String, dynamic> p) => !sentTs.contains(p['ts']))
          .toList();
      if (remaining.isEmpty) {
        // Remove the storage entry entirely rather than leaving a tombstone
        // JSON list: a fully-delivered queue occupies no space at all.
        await prefs.remove(_key);
      } else {
        await prefs.setString(_key, jsonEncode(remaining));
      }
      return batch.length;
    } catch (_) {
      return 0; // Network/backend failures keep the queue untouched.
    }
  }

  /// Current queue depth (for UI affordances and debugging). Best-effort: a
  /// storage failure reports 0.
  static Future<int> size() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      return _decode(prefs.getString(_key)).length;
    } catch (_) {
      return 0;
    }
  }

  /// Empties the queue and removes the storage entry entirely.
  ///
  /// Called on full session teardown (logout / force-expired session): queued
  /// points are bound to the device identity they were reported under, and
  /// replaying them after a logout or device re-registration would pin the
  /// queue — mixed-device batches are rejected, and dead-device points age
  /// out only after the server's freshness window. Wiping the queue here
  /// keeps the cache lifecycle tied to the session it was created in.
  static Future<void> clear() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (_) {
      // Storage failure must never break the teardown path.
    }
  }

  /// Builds the batch endpoint request body.
  static Map<String, dynamic> batchBody(List<Map<String, dynamic>> points) =>
      <String, dynamic>{'points': points};

  static List<Map<String, dynamic>> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded
          .whereType<Map>()
          .map((Map e) => e.cast<String, dynamic>())
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }
}