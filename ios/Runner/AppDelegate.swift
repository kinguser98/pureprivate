import Flutter
import UIKit
import AVFoundation

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers, .allowAirPlay])
      try AVAudioSession.sharedInstance().setActive(true)
    } catch {
      print("Failed to set AVAudioSession category for PiP: \(error)")
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // ── Device Auth Channel ─────────────────────────────────────────────────
    let deviceIdChannel = FlutterMethodChannel(
      name: "com.goxio.mobile/device_id",
      binaryMessenger: engineBridge.binaryMessenger
    )
    deviceIdChannel.setMethodCallHandler { (call, result) in
      switch call.method {
      case "getDeviceId":
        let idfv = UIDevice.current.identifierForVendor?.uuidString ?? ""
        result(idfv)
      case "getDeviceInfo":
        let deviceModel = UIDevice.current.model
        let systemVersion = UIDevice.current.systemVersion
        let name = UIDevice.current.name
        result([
          "device_name"  : name,
          "device_model" : deviceModel,
          "android_ver"  : "iOS \(systemVersion)",
        ])
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}
