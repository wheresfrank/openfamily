import 'api_client.dart';

/// A geofence: the arrive/leave notification rule attached to a place.
class Geofence {
  const Geofence({
    required this.id,
    this.placeId,
    this.userId,
    this.enterNotify = true,
    this.exitNotify = true,
    this.enabled = true,
  });

  final String id;
  final String? placeId;
  final String? userId;
  final bool enterNotify;
  final bool exitNotify;
  final bool enabled;

  factory Geofence.fromJson(Map<String, dynamic> json) => Geofence(
        id: json['id'] as String,
        placeId: json['place_id'] as String?,
        userId: json['user_id'] as String?,
        enterNotify: json['enter_notify'] as bool? ?? true,
        exitNotify: json['exit_notify'] as bool? ?? true,
        enabled: json['enabled'] as bool? ?? true,
      );
}

/// Client for the backend geofence endpoints.
class GeofenceService {
  GeofenceService._();

  /// Fetches all geofences for the current family.
  static Future<List<Geofence>> fetchGeofences() async {
    final dynamic data = await ApiClient.get('/family/geofences');
    if (data is! List) {
      throw const ApiException(0, 'Unexpected geofence response.');
    }
    return data
        .map((dynamic e) => Geofence.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Creates a geofence and returns it (with its server id).
  static Future<Geofence> createGeofence({
    required String placeId,
    String? userId,
    bool enterNotify = true,
    bool exitNotify = true,
  }) async {
    final Map<String, dynamic> body = <String, dynamic>{
      'place_id': placeId,
      'enter_notify': enterNotify,
      'exit_notify': exitNotify,
    };
    if (userId != null) body['user_id'] = userId;
    final dynamic data = await ApiClient.post('/family/geofences', body: body);
    return Geofence.fromJson(data as Map<String, dynamic>);
  }

  /// Deletes a geofence by id.
  static Future<void> deleteGeofence(String id) async {
    await ApiClient.delete('/family/geofences/$id');
  }
}
