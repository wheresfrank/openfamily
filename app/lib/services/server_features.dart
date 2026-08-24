/// Runtime capability flags from the operator's `GET /config`.
///
/// Emergency contacts only receive SOS by SMS, so the Safety UI is hidden
/// unless [smsConfigured] is true.
class ServerFeatures {
  ServerFeatures._();

  static final ServerFeatures instance = ServerFeatures._();

  bool smsConfigured = false;

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
  }

  void reset() {
    smsConfigured = false;
  }
}
