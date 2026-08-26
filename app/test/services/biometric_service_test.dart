import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:local_auth/error_codes.dart' as local_auth_error;
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openfamily/services/biometric_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SharedPreferencesBiometricPreferenceStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('defaults to disabled and persists changes', () async {
      final SharedPreferencesBiometricPreferenceStore store =
          SharedPreferencesBiometricPreferenceStore();

      expect(await store.isEnabled(), isFalse);
      expect(await store.setEnabled(true), isTrue);
      expect(await store.isEnabled(), isTrue);
    });
  });

  group('BiometricService availability', () {
    test('reports biometric hardware as unsupported', () async {
      final _FakeAuthenticator authenticator = _FakeAuthenticator(
        canCheckBiometrics: false,
        deviceSupported: true,
      );
      final BiometricService service = BiometricService(
        authenticator: authenticator,
        preferenceStore: _FakePreferenceStore(),
      );

      final BiometricAvailability result = await service.getAvailability();

      expect(result.status, BiometricAvailabilityStatus.unsupported);
      expect(result.isDeviceSupported, isTrue);
      expect(result.isAvailable, isFalse);
      expect(result.error?.code, BiometricErrorCode.unsupported);
    });

    test('distinguishes supported hardware with no enrollment', () async {
      final BiometricService service = BiometricService(
        authenticator: _FakeAuthenticator(
          enrolledBiometrics: const <BiometricType>[],
        ),
        preferenceStore: _FakePreferenceStore(),
      );

      final BiometricAvailability result = await service.getAvailability();

      expect(result.status, BiometricAvailabilityStatus.notEnrolled);
      expect(result.error?.code, BiometricErrorCode.notEnrolled);
    });

    test('returns the enrolled biometric types', () async {
      final BiometricService service = BiometricService(
        authenticator: _FakeAuthenticator(
          enrolledBiometrics: const <BiometricType>[
            BiometricType.face,
            BiometricType.strong,
          ],
        ),
        preferenceStore: _FakePreferenceStore(),
      );

      final BiometricAvailability result = await service.getAvailability();

      expect(result.status, BiometricAvailabilityStatus.available);
      expect(
        result.enrolledBiometrics,
        <BiometricType>[BiometricType.face, BiometricType.strong],
      );
    });

    test('converts platform failures to user-friendly availability', () async {
      final BiometricService service = BiometricService(
        authenticator: _FakeAuthenticator(
          availabilityError: PlatformException(
            code: local_auth_error.notEnrolled,
          ),
        ),
        preferenceStore: _FakePreferenceStore(),
      );

      final BiometricAvailability result = await service.getAvailability();

      expect(result.status, BiometricAvailabilityStatus.notEnrolled);
      expect(result.message, isNot(contains(local_auth_error.notEnrolled)));
    });
  });

  group('SharedPreferencesLockGraceStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('defaults to immediate locking and persists changes', () async {
      final SharedPreferencesLockGraceStore store =
          SharedPreferencesLockGraceStore();

      expect(await store.readGrace(), Duration.zero);
      expect(await store.writeGrace(const Duration(minutes: 5)), isTrue);
      expect(await store.readGrace(), const Duration(minutes: 5));
    });
  });

  group('BiometricService lock grace period', () {
    test('a failed grace read fails closed to immediate locking', () async {
      final BiometricService service = BiometricService(
        authenticator: _FakeAuthenticator(),
        preferenceStore: _FakePreferenceStore(),
        graceStore: _FakeLockGraceStore(
          readError: StateError('read failed'),
        ),
      );

      expect(await service.lockGrace(), Duration.zero);
    });

    test('out-of-range stored grace values collapse to immediate', () async {
      final BiometricService service = BiometricService(
        authenticator: _FakeAuthenticator(),
        preferenceStore: _FakePreferenceStore(),
        graceStore:
            _FakeLockGraceStore(grace: const Duration(hours: 2)),
      );

      expect(await service.lockGrace(), Duration.zero);
    });

    test('setLockGrace clamps oversize values instead of storing them',
        () async {
      final _FakeLockGraceStore store = _FakeLockGraceStore();
      final BiometricService service = BiometricService(
        authenticator: _FakeAuthenticator(),
        preferenceStore: _FakePreferenceStore(),
        graceStore: store,
      );

      expect(await service.setLockGrace(const Duration(days: 1)), isTrue);
      expect(store.grace, Duration.zero);
      expect(await service.setLockGrace(const Duration(minutes: 5)), isTrue);
      expect(store.grace, const Duration(minutes: 5));
    });
  });

  group('BiometricService authentication', () {
    test('propagates enabled-preference read failures for fail-closed callers',
        () async {
      final BiometricService service = BiometricService(
        authenticator: _FakeAuthenticator(),
        preferenceStore: _FakePreferenceStore(
          readError: StateError('read failed'),
        ),
      );

      expect(service.isEnabled(), throwsStateError);
    });

    test('reports a failed preference write without throwing', () async {
      final BiometricService service = BiometricService(
        authenticator: _FakeAuthenticator(),
        preferenceStore: _FakePreferenceStore(
          writeError: StateError('write failed'),
        ),
      );

      expect(await service.setEnabled(true), isFalse);
    });

    test('does not prompt when the feature is disabled', () async {
      final _FakeAuthenticator authenticator = _FakeAuthenticator();
      final BiometricService service = BiometricService(
        authenticator: authenticator,
        preferenceStore: _FakePreferenceStore(enabled: false),
      );

      final BiometricAuthenticationResult result = await service.authenticate();

      expect(result.authenticated, isFalse);
      expect(result.error?.code, BiometricErrorCode.disabled);
      expect(authenticator.authenticationCalls, 0);
    });

    test('uses biometric-only authentication options', () async {
      final _FakeAuthenticator authenticator = _FakeAuthenticator();
      final BiometricService service = BiometricService(
        authenticator: authenticator,
        preferenceStore: _FakePreferenceStore(enabled: true),
      );

      final BiometricAuthenticationResult result = await service.authenticate(
        localizedReason: 'Unlock the app',
      );

      expect(result.authenticated, isTrue);
      expect(authenticator.authenticationCalls, 1);
      expect(authenticator.lastLocalizedReason, 'Unlock the app');
      expect(authenticator.lastOptions?.biometricOnly, isTrue);
      expect(authenticator.lastOptions?.stickyAuth, isTrue);
      expect(authenticator.lastOptions?.useErrorDialogs, isFalse);
    });

    test('exposes whether a native authentication prompt is active', () async {
      final Completer<bool> prompt = Completer<bool>();
      final _FakeAuthenticator authenticator = _FakeAuthenticator(
        authenticationCompleter: prompt,
      );
      final BiometricService service = BiometricService(
        authenticator: authenticator,
        preferenceStore: _FakePreferenceStore(enabled: true),
      );

      final Future<BiometricAuthenticationResult> authentication =
          service.authenticate();
      await Future<void>.delayed(Duration.zero);

      expect(service.isAuthenticating, isTrue);
      prompt.complete(true);
      expect((await authentication).authenticated, isTrue);
      expect(service.isAuthenticating, isFalse);
    });

    test('can authenticate before persisting opt-in', () async {
      final _FakeAuthenticator authenticator = _FakeAuthenticator();
      final BiometricService service = BiometricService(
        authenticator: authenticator,
        preferenceStore: _FakePreferenceStore(enabled: false),
      );

      final BiometricAuthenticationResult result = await service.authenticate(
        requireEnabled: false,
      );

      expect(result.authenticated, isTrue);
      expect(authenticator.authenticationCalls, 1);
    });

    test('returns an authentication failure when the prompt returns false',
        () async {
      final BiometricService service = BiometricService(
        authenticator: _FakeAuthenticator(authenticated: false),
        preferenceStore: _FakePreferenceStore(enabled: true),
      );

      final BiometricAuthenticationResult result = await service.authenticate();

      expect(result.authenticated, isFalse);
      expect(result.error?.code, BiometricErrorCode.authenticationFailed);
    });

    test('maps lockout errors without exposing platform messages', () async {
      final BiometricService service = BiometricService(
        authenticator: _FakeAuthenticator(
          authenticationError: PlatformException(
            code: local_auth_error.lockedOut,
            message: 'raw platform failure',
          ),
        ),
        preferenceStore: _FakePreferenceStore(enabled: true),
      );

      final BiometricAuthenticationResult result = await service.authenticate();

      expect(result.error?.code, BiometricErrorCode.temporarilyLockedOut);
      expect(result.error?.platformCode, local_auth_error.lockedOut);
      expect(result.error?.message, isNot(contains('raw platform failure')));
    });

    test('returns a storage error when the enabled flag cannot be read',
        () async {
      final BiometricService service = BiometricService(
        authenticator: _FakeAuthenticator(),
        preferenceStore: _FakePreferenceStore(
          readError: StateError('read failed'),
        ),
      );

      final BiometricAuthenticationResult result = await service.authenticate();

      expect(result.error?.code, BiometricErrorCode.storageUnavailable);
    });
  });
}

class _FakeAuthenticator implements BiometricAuthenticator {
  _FakeAuthenticator({
    bool canCheckBiometrics = true,
    this.deviceSupported = true,
    this.enrolledBiometrics = const <BiometricType>[BiometricType.fingerprint],
    this.authenticated = true,
    this.availabilityError,
    this.authenticationError,
    this.authenticationCompleter,
  }) : canCheckBiometricsValue = canCheckBiometrics;

  final bool canCheckBiometricsValue;
  final bool deviceSupported;
  final List<BiometricType> enrolledBiometrics;
  final bool authenticated;
  final Object? availabilityError;
  final Object? authenticationError;
  final Completer<bool>? authenticationCompleter;

  int authenticationCalls = 0;
  String? lastLocalizedReason;
  AuthenticationOptions? lastOptions;

  @override
  Future<bool> get canCheckBiometrics async {
    _throwIfPresent(availabilityError);
    return canCheckBiometricsValue;
  }

  @override
  Future<bool> isDeviceSupported() async {
    _throwIfPresent(availabilityError);
    return deviceSupported;
  }

  @override
  Future<List<BiometricType>> getAvailableBiometrics() async {
    _throwIfPresent(availabilityError);
    return enrolledBiometrics;
  }

  @override
  Future<bool> authenticate({
    required String localizedReason,
    required AuthenticationOptions options,
  }) async {
    authenticationCalls++;
    lastLocalizedReason = localizedReason;
    lastOptions = options;
    _throwIfPresent(authenticationError);
    if (authenticationCompleter != null) {
      return authenticationCompleter!.future;
    }
    return authenticated;
  }

  @override
  Future<bool> stopAuthentication() async => true;

  static void _throwIfPresent(Object? error) {
    if (error != null) {
      throw error;
    }
  }
}

class _FakeLockGraceStore implements LockGraceStore {
  _FakeLockGraceStore({
    this.grace = Duration.zero,
    this.readError,
  });

  Duration grace;
  final Object? readError;

  @override
  Future<Duration> readGrace() async {
    if (readError != null) {
      throw readError!;
    }
    return grace;
  }

  @override
  Future<bool> writeGrace(Duration grace) async {
    this.grace = grace;
    return true;
  }
}

class _FakePreferenceStore implements BiometricPreferenceStore {
  _FakePreferenceStore({
    this.enabled = false,
    this.readError,
    this.writeError,
  });

  bool enabled;
  final Object? readError;
  final Object? writeError;

  @override
  Future<bool> isEnabled() async {
    if (readError != null) {
      throw readError!;
    }
    return enabled;
  }

  @override
  Future<bool> setEnabled(bool enabled) async {
    if (writeError != null) {
      throw writeError!;
    }
    this.enabled = enabled;
    return true;
  }
}
