import 'package:flutter_test/flutter_test.dart';
import 'package:openfamily/models/member.dart';
import 'package:openfamily/services/member_mapper.dart';

void main() {
  group('member avatar metadata', () {
    test('keeps a newer avatar when a stale WebSocket frame arrives', () {
      final member = memberFromJson(<String, dynamic>{
        'id': 'member-1',
        'name': 'Sam Rivera',
        'has_avatar': true,
        'avatar_updated_at': '2026-08-22T12:00:00Z',
        'avatar_version': 7,
      });

      expect(member.hasAvatar, isTrue);
      expect(member.avatarVersion, 7);

      final stale = memberFromAvatarUpdate(member, <String, dynamic>{
        'has_avatar': false,
        'avatar_version': 6,
      });

      expect(identical(stale, member), isTrue);
      expect(stale.hasAvatar, isTrue);

      final removal = memberFromAvatarUpdate(member, <String, dynamic>{
        'has_avatar': false,
        'avatar_version': 8,
      });

      expect(removal.hasAvatar, isFalse);
      expect(removal.avatarVersion, 8);
      expect(removal.avatarUpdatedAt, isNull);
    });

    test('does not apply an unversioned avatar frame', () {
      final member = memberFromJson(<String, dynamic>{
        'id': 'member-1',
        'name': 'Sam Rivera',
        'has_avatar': true,
        'avatar_version': 1,
      });

      final unchanged = memberFromAvatarUpdate(member, <String, dynamic>{
        'has_avatar': false,
      });

      expect(identical(unchanged, member), isTrue);
    });
  });

  group('last seen / presence', () {
    final freshTs =
        DateTime.now().toUtc().subtract(const Duration(minutes: 1));

    test('uses last_seen_at when it is newer than the location ts', () {
      final member = memberFromJson(<String, dynamic>{
        'id': 'member-1',
        'name': 'Sam Rivera',
        'lat': 37.0,
        'lon': -122.0,
        // Location is 30 minutes old — would be stale on its own.
        'ts': DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 30))
            .toIso8601String(),
        // Device heartbeat is fresh.
        'last_seen_at': freshTs.toIso8601String(),
      });

      expect(member.lastSeen, freshTs);
      expect(member.status, MemberStatus.normal);
    });

    test('keeps the location ts when it is the newer of the two', () {
      final ts = DateTime.now().toUtc();
      final member = memberFromJson(<String, dynamic>{
        'id': 'member-1',
        'name': 'Sam Rivera',
        'lat': 37.0,
        'lon': -122.0,
        'ts': ts.toIso8601String(),
        'last_seen_at':
            ts.subtract(const Duration(minutes: 5)).toIso8601String(),
      });

      expect(member.lastSeen, ts);
    });

    test('a stale stationary member goes back to normal on a presence frame',
        () {
      final member = memberFromJson(<String, dynamic>{
        'id': 'member-1',
        'name': 'Sam Rivera',
        'lat': 37.0,
        'lon': -122.0,
        'ts': DateTime.now()
            .toUtc()
            .subtract(const Duration(minutes: 30))
            .toIso8601String(),
      });
      expect(member.status, MemberStatus.stopped);

      final refreshed = memberFromPresenceUpdate(member, <String, dynamic>{
        'user_id': 'member-1',
        'ts': freshTs.toIso8601String(),
        'battery_pct': 88,
      });

      expect(refreshed.status, MemberStatus.normal);
      expect(refreshed.lastSeen, freshTs);
      // Liveness only: pin and battery update, nothing else moves.
      expect(refreshed.position, member.position);
      expect(refreshed.batteryPercent, 88);
      expect(refreshed.speedMph, member.speedMph);
    });

    test('ignores equal-or-older presence frames and malformed frames', () {
      final member = memberFromJson(<String, dynamic>{
        'id': 'member-1',
        'name': 'Sam Rivera',
        'lat': 37.0,
        'lon': -122.0,
        'ts': freshTs.toIso8601String(),
      });

      final older = memberFromPresenceUpdate(member, <String, dynamic>{
        'user_id': 'member-1',
        'ts': freshTs
            .subtract(const Duration(seconds: 1))
            .toIso8601String(),
      });
      final malformed = memberFromPresenceUpdate(member, <String, dynamic>{
        'user_id': 'member-1',
        'ts': 'not-a-timestamp',
      });
      final noUser = memberFromPresenceUpdate(member, <String, dynamic>{
        'ts': DateTime.now().toUtc().add(const Duration(minutes: 1)).toIso8601String(),
      });

      expect(identical(older, member), isTrue);
      expect(identical(malformed, member), isTrue);
      expect(identical(noUser, member), isTrue);
    });
  });
}
