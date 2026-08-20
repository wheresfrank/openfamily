import 'package:whereabouts/services/api_client.dart';

class ManagedFamilyMember {
  const ManagedFamilyMember({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
  });

  final String id;
  final String name;
  final String email;
  final String role;

  factory ManagedFamilyMember.fromJson(Map<String, dynamic> json) {
    return ManagedFamilyMember(
      id: json['id'] as String,
      name: json['name'] as String? ?? 'Member',
      email: json['email'] as String? ?? '',
      role: json['role'] as String? ?? 'member',
    );
  }
}

/// Family-management API used by the mobile Settings flow.
class FamilyManagementService {
  FamilyManagementService._();

  static Future<Map<String, dynamic>> createFamily(String name) async {
    final dynamic data = await ApiClient.post(
      '/families',
      body: <String, dynamic>{'name': name},
    );
    return data as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> fetchFamily() async {
    final dynamic data = await ApiClient.get('/family');
    return data as Map<String, dynamic>;
  }

  static Future<List<ManagedFamilyMember>> fetchMembers() async {
    final dynamic data = await ApiClient.get('/family/members');
    return (data as List<dynamic>)
        .map((dynamic item) => ManagedFamilyMember.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  static Future<Map<String, dynamic>> renameFamily(String name) async {
    final dynamic data = await ApiClient.patch(
      '/family',
      body: <String, dynamic>{'name': name},
    );
    return data as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> updateRole(String userId, String role) async {
    final dynamic data = await ApiClient.patch(
      '/family/members/$userId/role',
      body: <String, dynamic>{'role': role},
    );
    return data as Map<String, dynamic>;
  }

  static Future<void> removeMember(String userId) async {
    await ApiClient.delete('/family/members/$userId');
  }
}
