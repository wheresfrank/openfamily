import 'package:flutter_test/flutter_test.dart';
import 'package:whereabouts/services/member_mapper.dart';

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
}
