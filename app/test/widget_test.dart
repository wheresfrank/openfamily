import 'package:flutter_test/flutter_test.dart';
import 'package:whereabouts/services/family_management_service.dart';

void main() {
  test('managed family member decodes the server contract', () {
    final ManagedFamilyMember member = ManagedFamilyMember.fromJson(<String, dynamic>{
      'id': 'user-1',
      'name': 'Frank',
      'email': 'frank@example.com',
      'role': 'admin',
    });

    expect(member.id, 'user-1');
    expect(member.name, 'Frank');
    expect(member.email, 'frank@example.com');
    expect(member.role, 'admin');
  });
}
