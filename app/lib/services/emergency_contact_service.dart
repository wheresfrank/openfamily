import '../models/emergency_contact.dart';
import 'api_client.dart';

/// Client for `GET/POST/DELETE /me/contacts`.
class EmergencyContactService {
  /// Fetches the caller's emergency contacts.
  Future<List<EmergencyContact>> list() async {
    final dynamic data = await ApiClient.get('/me/contacts');
    if (data is! List) {
      throw const ApiException(0, 'Unexpected contacts response.');
    }
    return data
        .map(
            (dynamic e) => EmergencyContact.fromJson(e as Map<String, dynamic>))
        .where((EmergencyContact c) => c.id.isNotEmpty)
        .toList();
  }

  /// Creates an emergency contact and returns the server copy (with id).
  Future<EmergencyContact> add({
    required String name,
    required String phone,
    String relation = '',
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{
      'name': name,
      'phone': phone,
    };
    if (relation.isNotEmpty) {
      body['relation'] = relation;
    }
    final dynamic data = await ApiClient.post('/me/contacts', body: body);
    if (data is! Map<String, dynamic>) {
      throw const ApiException(0, 'Unexpected contact response.');
    }
    return EmergencyContact.fromJson(data);
  }

  /// Removes an emergency contact by id.
  Future<void> delete(String id) async {
    await ApiClient.delete('/me/contacts/${Uri.encodeComponent(id)}');
  }
}
