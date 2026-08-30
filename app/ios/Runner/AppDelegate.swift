import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, UNUserNotificationCenterDelegate {
  private var apnsChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let ok = super.application(application, didFinishLaunchingWithOptions: launchOptions)

    if let registrar = self.registrar(forPlugin: "OpenFamilyApns") {
      let channel = FlutterMethodChannel(
        name: "app.openfamily/apns",
        binaryMessenger: registrar.messenger()
      )
      apnsChannel = channel
      channel.setMethodCallHandler { call, result in
        if call.method == "register" {
          UIApplication.shared.registerForRemoteNotifications()
          result(nil)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }

    // Foreground banners match the Android behavior: Android surfaces a local
    // notification for alert messages while the app is open
    // (PushService.showForeground); default iOS presentation hides them in
    // the foreground unless we opt in via the notification-center delegate.
    UNUserNotificationCenter.current().delegate = self

    return ok
  }

  override func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    let token = deviceToken.map { String(format: "%02x", $0) }.joined()
    apnsChannel?.invokeMethod("onToken", arguments: token)
  }

  override func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    apnsChannel?.invokeMethod("onTokenError", arguments: error.localizedDescription)
  }

  // Silent APNs commands (machine-to-machine, e.g. a family member requested a
  // location refresh). The backend sends these with aps.content-available only
  // and the raw command JSON under "of". Forward the command to Dart, which
  // handles it exactly like the Android UnifiedPush message path. iOS launches
  // the app in the background for content-available pushes (the
  // remote-notification background mode is declared in Info.plist).
  // Alert payloads fall through to the system (iOS shows the banner itself).
  override func application(
    _ application: UIApplication,
    didReceiveRemoteNotification userInfo: [AnyHashable: Any],
    fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
  ) -> Bool {
    if let command = userInfo["of"] as? String {
      apnsChannel?.invokeMethod("onCommand", arguments: command)
      completionHandler(.newData)
    } else {
      completionHandler(.noData)
    }
    return true
  }

  // Foreground presentation for alert payloads. Silent commands are never
  // surfaced as banners (the command is executed silently by Dart).
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if notification.request.content.userInfo["of"] != nil {
      completionHandler([])
      return
    }
    completionHandler([.banner, .list, .sound])
  }
}