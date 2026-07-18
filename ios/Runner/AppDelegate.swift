import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Register auto-generated Flutter plugins
    GeneratedPluginRegistrant.register(with: self)

    // Register our manual camera controls bridge (ISO, SS, WB via AVFoundation)
    if let registrar = registrar(forPlugin: "ManualCameraPlugin") {
      ManualCameraPlugin.register(with: registrar)
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
