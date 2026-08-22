import 'dart:async';

import 'package:battery_plus/battery_plus.dart';
import 'package:geolocator/geolocator.dart';

import 'api_client.dart';
import 'device_service.dart';

/// Periodically reports the device's foreground GPS position to the backend
/// (`POST /locations`) so the family can see where the user is.
///
/// Foreground-only: it runs while the [MapScreen] is alive. When the app is
/// backgrounded, geolocator's stream naturally pauses on most platforms and
/// resumes on return. Background reporting is a separate, deferred piece.
///
/// The reporter is deliberately non-throwing and idempotent:
/// - [start] is a no-op when already running.
/// - A failed device registration or a stream that errors out is retried on a
///   backoff cycle rather than surfacing an exception to the caller.
/// - Per-report failures (stale `ts`, non-monotonic ordering, clock skew) are
///   expected and skipped silently.
///
/// Concurrency safety: a monotonically increasing [_generation] counter
/// prevents re-entrancy races. Each [start] bumps the generation (it is
/// **never** reset — not even by [stop]); every async checkpoint in
/// [_startStream] verifies the generation is still current, so a [stop] or a
/// rapid stop→start cycle cleanly aborts stale in-flight invocations and
/// never leaks a second GPS subscription. A separate [_active] flag tracks
/// the running/stopped state.
class LocationReporter {
  /// Whether the reporter is currently running (set by [start], cleared by
  /// [stop]).
  bool _active = false;

  /// Monotonically increasing generation counter. Bumped on each [start];
  /// **never** reset. This ensures a stale in-flight [_startStream] from a
  /// previous generation can always be distinguished from the current one.
  int _generation = 0;

  /// The active position stream subscription, if any.
  StreamSubscription<Position>? _subscription;

  /// Pending restart timer after a stream error/close or failed registration.
  Timer? _restartTimer;

  /// The registered device id, resolved lazily and retried on restart.
  String? _deviceId;

  final Battery _battery = Battery();

  // Serialization / throttling / dedup state.
  /// True while a POST is in flight; newer updates are skipped meanwhile.
  bool _posting = false;

  /// Timestamp of the last position we sent (or the backend rejected), used to
  /// dedup equal/out-of-order timestamps against the backend's monotonic rule.
  DateTime? _lastSentTs;

  /// When the last POST was attempted, used to rate-limit against flooding.
  DateTime? _lastPostTime;

  /// The latest position seen while a POST was in flight, processed (backfilled)
  /// once the current POST completes so a slow POST doesn't lose a fix.
  Position? _pendingPosition;

  /// How long to wait before retrying the stream after it errors or closes.
  static const Duration _restartDelay = Duration(seconds: 15);

  /// Minimum interval between POST attempts (safety net against flooding).
  /// Shortened while an SOS is active so family sees fresher points.
  static Duration minPostInterval = const Duration(seconds: 5);

  static Timer? _sosBurstTimer;

  /// Reports more often for a few minutes after SOS. No-op if already bursting.
  static void startSosBurst({Duration last = const Duration(minutes: 5)}) {
    minPostInterval = const Duration(seconds: 2);
    _sosBurstTimer?.cancel();
    _sosBurstTimer = Timer(last, stopSosBurst);
  }

  static void stopSosBurst() {
    _sosBurstTimer?.cancel();
    _sosBurstTimer = null;
    minPostInterval = const Duration(seconds: 5);
  }

  /// Ensures the device is registered, then starts the position stream.
  ///
  /// Fire-and-forget from the caller's perspective: never throws, and does not
  /// block the UI. Calling it again while running is a no-op.
  Future<void> start() async {
    if (_active) return;
    _active = true;
    _generation++;
    await _startStream(_generation);
  }

  /// Registers the device (if needed) and opens the position stream.
  ///
  /// [gen] is the generation this invocation belongs to; every async checkpoint
  /// re-checks it so a [stop] or a new [start] cleanly aborts stale work.
  ///
  /// Registration is re-attempted on each restart cycle while [_deviceId] is
  /// null, so a transient registration failure at launch is recovered rather
  /// than silently dropped for the whole session.
  Future<void> _startStream(int gen) async {
    if (!_active || _generation != gen) return;

    if (_deviceId == null) {
      try {
        _deviceId = await DeviceService.ensureRegistered();
      } on SessionExpiredException {
        // The app root has already redirected to login; nothing to report.
        stop();
        return;
      } catch (_) {
        // Registration failed (e.g. network). Retry on the next cycle.
        _scheduleRestart(gen);
        return;
      }
      // A stop() or start() may have landed while registration was in flight.
      if (!_active || _generation != gen) return;
    }

    // Stop looping if permission is permanently denied; otherwise proceed (a
    // `denied` state may still be granted later, and `getPositionStream` will
    // surface any remaining problem).
    try {
      final LocationPermission permission =
          await Geolocator.checkPermission();
      if (permission == LocationPermission.deniedForever) {
        stop();
        return;
      }
    } catch (_) {
      // checkPermission can throw on some platforms (e.g. web); fall through
      // and let getPositionStream surface the error instead.
    }
    if (!_active || _generation != gen) return;

    Stream<Position> stream;
    try {
      stream = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      );
    } catch (_) {
      // Permission denied / services off / platform error. Retry later so a
      // subsequent permission grant starts producing updates.
      _scheduleRestart(gen);
      return;
    }

    // Clean up any stale subscription from a previous cycle before opening a
    // new one, so we never run two concurrent GPS streams / duplicate POSTs.
    await _subscription?.cancel();
    if (!_active || _generation != gen) return;

    _subscription = stream.listen(
      _onPosition,
      onError: (Object _) {
        _subscription?.cancel();
        _subscription = null;
        _scheduleRestart(gen);
      },
      onDone: () {
        _subscription = null;
        _scheduleRestart(gen);
      },
    );
  }

  /// Schedules a single restart attempt after the stream errors/closes or a
  /// registration attempt fails. [gen] ties the timer to the originating
  /// generation so a stale timer never fires for a newer cycle.
  void _scheduleRestart(int gen) {
    if (!_active || _generation != gen) return;
    _restartTimer?.cancel();
    _restartTimer = Timer(_restartDelay, () {
      _restartTimer = null;
      if (_active && _generation == gen) _startStream(gen);
    });
  }

  /// Builds and POSTs a location report for a single [Position].
  ///
  /// Updates are serialized (one POST at a time), throttled (min interval), and
  /// deduped (monotonic timestamps) before being sent. A position that arrives
  /// while a POST is in flight is remembered and backfilled once the POST
  /// completes, so a slow POST doesn't lose a fix. The backfill bypasses the
  /// rate limiter so the user's final position is always reported.
  Future<void> _onPosition(Position position, {bool bypassRateLimit = false}) async {
    // Serialize: if a POST is in flight, remember this position as the latest
    // pending one and return; it is processed when the current POST completes.
    if (_posting) {
      _pendingPosition = position;
      return;
    }

    // Dedup: skip equal/out-of-order timestamps (backend requires monotonic).
    final DateTime ts = position.timestamp.toUtc();
    if (_lastSentTs != null && !ts.isAfter(_lastSentTs!)) return;

    // Rate limit: skip if too soon since the last POST attempt (unless this is
    // a backfill, which should always go through).
    if (!bypassRateLimit) {
      final DateTime now = DateTime.now().toUtc();
      if (_lastPostTime != null &&
          now.difference(_lastPostTime!) < minPostInterval) {
        return;
      }
    }

    _posting = true;
    _lastPostTime = DateTime.now().toUtc();
    try {
      int? batteryPct;
      try {
        batteryPct = await _battery.batteryLevel;
      } catch (_) {
        // battery_plus is unsupported on web; report without battery_pct rather
        // than letting a battery read failure drop the location report.
        batteryPct = null;
      }

      final Map<String, dynamic> body = <String, dynamic>{
        'device_id': _deviceId,
        'ts': ts.toIso8601String(),
        'lat': position.latitude,
        'lon': position.longitude,
        'motion_state': '',
        'source': 'foreground',
      };
      if (batteryPct != null) body['battery_pct'] = batteryPct;
      if (position.accuracy > 0) body['accuracy_meters'] = position.accuracy;
      // Altitude is valid below sea level (negative), so send any finite value.
      if (position.altitude.isFinite) {
        body['altitude_meters'] = position.altitude;
      }
      if (position.speed > 0) body['speed_mps'] = position.speed;
      // Note: geolocator reports heading as 0.0 when unknown on some
      // platforms, so a 0 heading may mean "unknown" — acceptable since the
      // backend treats heading as optional.
      if (position.heading >= 0) body['heading_deg'] = position.heading;

      await ApiClient.post('/locations', body: body);
      _lastSentTs = ts;
    } on SessionExpiredException {
      // The app root handles the redirect; stop reporting for this session.
      stop();
    } on ApiException catch (e) {
      // A non-zero status is a genuine backend rejection (e.g. 400 for stale
      // ts or non-monotonic ordering): record it as sent so we don't retry the
      // same timestamp. A zero status is a network/timeout failure where the
      // point never reached the server, so leave _lastSentTs untouched so the
      // point can be retried on the next update.
      if (e.status != 0) {
        _lastSentTs = ts;
      }
    } catch (_) {
      // Unexpected error (e.g. malformed body). Intentionally swallowed so the
      // reporter never crashes the app; the next update will retry.
    } finally {
      _posting = false;
    }

    // If the reporter was stopped during the POST (session expired or app
    // backgrounded), don't backfill.
    if (!_active) return;

    // Backfill the latest position captured while we were posting. The
    // backfill bypasses the rate limiter so the final position is always sent.
    final Position? pending = _pendingPosition;
    _pendingPosition = null;
    if (pending != null) {
      final DateTime pendingTs = pending.timestamp.toUtc();
      if (_lastSentTs == null || pendingTs.isAfter(_lastSentTs!)) {
        await _onPosition(pending, bypassRateLimit: true);
      }
    }
  }

  /// Cancels the position stream and any pending restart, and clears state.
  void stop() {
    _active = false;
    _restartTimer?.cancel();
    _restartTimer = null;
    _subscription?.cancel();
    _subscription = null;
    _pendingPosition = null;
  }
}