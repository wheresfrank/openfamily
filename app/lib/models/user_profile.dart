/// The authenticated user's private profile data from `GET /api/profile`.
///
/// An avatar is represented only by [hasAvatar] and fetched as authenticated
/// bytes from `/api/profile/avatar`; this model intentionally contains no avatar
/// URL so it cannot leak into member/map responses.
class UserProfile {
  const UserProfile({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.hasAvatar,
    this.avatarUpdatedAt,
  });

  final String id;
  final String name;
  final String email;
  final String role;
  final bool hasAvatar;
  final DateTime? avatarUpdatedAt;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final dynamic updatedAt = json['avatar_updated_at'];
    return UserProfile(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Your profile',
      email: json['email'] as String? ?? '',
      role: json['role'] as String? ?? 'member',
      hasAvatar: json['has_avatar'] == true,
      avatarUpdatedAt:
          updatedAt is String ? DateTime.tryParse(updatedAt)?.toUtc() : null,
    );
  }

  UserProfile copyWith({
    String? id,
    String? name,
    String? email,
    String? role,
    bool? hasAvatar,
    DateTime? avatarUpdatedAt,
    bool clearAvatarUpdatedAt = false,
  }) {
    return UserProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      hasAvatar: hasAvatar ?? this.hasAvatar,
      avatarUpdatedAt:
          clearAvatarUpdatedAt ? null : avatarUpdatedAt ?? this.avatarUpdatedAt,
    );
  }
}
