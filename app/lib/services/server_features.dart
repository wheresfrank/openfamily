/// Runtime capability flags from the operator's `GET /config`.
///
/// Emergency contacts only receive SOS by SMS, so the Safety UI is hidden
/// unless [smsConfigured] is true.
class ServerFeatures {
  ServerFeatures._();

  static final ServerFeatures instance = ServerFeatures._();

  bool smsConfigured = false;

  /// Whether the operator enabled the optional live-traffic layer
  /// (`traffic_enabled`). Servers that predate it, or have no key, report false.
  bool trafficEnabled = false;

  /// Applies `sms_configured` from a `/config` body.
  ///
  /// Older servers omit the field; assume SMS may be on so existing
  /// deployments keep showing contacts until the backend is updated.
  void apply(Map<String, dynamic> cfg) {
    if (cfg.containsKey('sms_configured')) {
      smsConfigured = cfg['sms_configured'] == true;
    } else {
      smsConfigured = true;
    }
    trafficEnabled = cfg['traffic_enabled'] == true;
  }

  void reset() {
    smsConfigured = false;
    trafficEnabled = false;
  }
}
