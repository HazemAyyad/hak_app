import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "QuranStorage") {
      let channel = FlutterMethodChannel(name: "com.haqfoundation.haq_app/storage", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        guard call.method == "diskSpace" else { result(FlutterMethodNotImplemented); return }
        do {
          let attributes = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
          result(["total": attributes[.systemSize] as? NSNumber ?? 0,
                  "free": attributes[.systemFreeSize] as? NSNumber ?? 0])
        } catch { result(FlutterError(code: "storage", message: "Unable to read storage space", details: nil)) }
      }
    }
  }
}
