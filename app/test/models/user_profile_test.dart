import 'package:flutter_test/flutter_test.dart';
import 'package:openfamily/models/user_profile.dart';

void main() {
  test('parses an optional phone number', () {
    final UserProfile profile = UserProfile.fromJson(<String, dynamic>{
      'id': 'u1',
      'name': 'Frank',
      'email': 'frank@example.com',
      'role': 'admin',
      'phone': '+15551234567',
      'has_avatar': false,
    });
    expect(profile.phone, '+15551234567');
  });
}
