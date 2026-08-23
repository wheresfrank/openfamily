/// An emergency contact who receives SOS even without the app.
///
/// Contacts are stored on the server (`/me/contacts`), not on the phone, so
/// they survive reinstalls and can be used when the API fans out an SOS.
class EmergencyContact {
  const EmergencyContact({
    required this.id,
    required this.name,
    required this.phone,
    this.relation = '',
  });

  final String id;
  final String name;
  final String phone;
  final String relation;

  factory EmergencyContact.fromJson(Map<String, dynamic> json) {
    return EmergencyContact(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      relation: json['relation'] as String? ?? '',
    );
  }

  /// True when [phone] has enough digits to be worth sending to the API.
  static bool looksLikePhone(String phone) {
    final String digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.length >= 7 && digits.length <= 15;
  }
}
