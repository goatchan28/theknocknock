import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if let controller = window?.rootViewController as? FlutterViewController {
      let badgeChannel = FlutterMethodChannel(
        name: "knocknock/app_badge",
        binaryMessenger: controller.binaryMessenger
      )
      badgeChannel.setMethodCallHandler { call, result in
        switch call.method {
        case "setBadgeCount":
          if let count = call.arguments as? Int {
            application.applicationIconBadgeNumber = max(0, count)
            result(nil)
          } else {
            result(
              FlutterError(
                code: "BADGE_ARG_ERROR",
                message: "Expected integer badge count",
                details: nil
              )
            )
          }
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
