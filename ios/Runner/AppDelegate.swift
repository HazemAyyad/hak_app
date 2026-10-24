import Flutter
import UIKit
import Photos

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
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HaqImageExport") {
      let channel = FlutterMethodChannel(name: "com.haqfoundation.haq_app/image_export", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { call, result in
        guard call.method == "saveImage" else { result(FlutterMethodNotImplemented); return }
        guard let args = call.arguments as? [String: Any], let data = args["bytes"] as? FlutterStandardTypedData,
              data.data.count <= 20_000_000, UIImage(data: data.data) != nil else {
          result(FlutterError(code: "image", message: "Invalid image", details: nil)); return
        }
        let save: (PHAuthorizationStatus) -> Void = { status in
          guard status == .authorized else {
            DispatchQueue.main.async { result(FlutterError(code: "permission", message: "Photo permission denied", details: nil)) }; return
          }
          PHPhotoLibrary.shared().performChanges({
            PHAssetCreationRequest.forAsset().addResource(with: .photo, data: data.data, options: nil)
          }) { success, error in
            DispatchQueue.main.async {
              if success { result(true) }
              else { result(FlutterError(code: "image", message: error?.localizedDescription ?? "Unable to save image", details: nil)) }
            }
          }
        }
        if #available(iOS 14, *) { PHPhotoLibrary.requestAuthorization(for: .addOnly, handler: save) }
        else { PHPhotoLibrary.requestAuthorization(save) }
      }
    }
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
