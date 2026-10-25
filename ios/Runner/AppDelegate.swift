import Flutter
import UIKit
import Photos
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var haqReminders: HaqReminderCenter?
  private var haqPendingResponse: UNNotificationResponse?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HaqReminders") {
      haqReminders = HaqReminderCenter(messenger: registrar.messenger())
      if let response = haqPendingResponse { haqReminders?.receive(response); haqPendingResponse = nil }
      UNUserNotificationCenter.current().delegate = self
    }
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

  override func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
      withCompletionHandler completionHandler: @escaping () -> Void) {
    if response.notification.request.identifier.hasPrefix("haq-reminder:") {
      if let reminders = haqReminders { reminders.receive(response) }
      else { haqPendingResponse = response }
      completionHandler()
    } else { super.userNotificationCenter(center, didReceive: response, withCompletionHandler: completionHandler) }
  }

  override func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
      withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    if notification.request.identifier.hasPrefix("haq-reminder:") {
      if #available(iOS 14.0, *) { completionHandler([.banner, .list, .sound]) }
      else { completionHandler([.alert, .sound]) }
    } else { super.userNotificationCenter(center, willPresent: notification, withCompletionHandler: completionHandler) }
  }
}

/// Native calendar notifications work without a Dart background isolate.
/// iOS supplies notification-center presentation, never Android-style overlays.
private final class HaqReminderCenter {
  private let center = UNUserNotificationCenter.current()
  private let channel: FlutterMethodChannel
  private let defaults = UserDefaults.standard
  private let prefix = "haq-reminder:"
  private var plan: [String: Any]
  private var generation = 0
  private var pendingRoute: String?
  private var dartReady = false
  private var failure: Error?
  init(messenger: FlutterBinaryMessenger) {
    plan = UserDefaults.standard.dictionary(forKey: "haq.reminders.v1") ?? [:]
    channel = FlutterMethodChannel(name: "com.haqfoundation.haq_app/reminders", binaryMessenger: messenger)
    let snooze = UNNotificationAction(identifier: "haq-snooze", title: "تأجيل", options: [])
    center.getNotificationCategories { categories in
      var next = categories
      next.update(with: UNNotificationCategory(identifier: "haq-reminder", actions: [snooze], intentIdentifiers: [], options: []))
      self.center.setNotificationCategories(next)
    }
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "scope":
        let scope = call.arguments as? String ?? "guest"
        if self.plan["scope"] as? String != scope {
          self.generation += 1; self.plan = ["scope": scope, "jobs": []]
          self.pendingRoute = nil
          self.defaults.set(self.plan, forKey: "haq.reminders.v1")
          self.clearPrivate { result(nil) }
        } else { result(nil) }
      case "replace":
        guard let data = call.arguments as? [String: Any], let jobs = data["jobs"] as? [[String: Any]], jobs.count <= 200 else {
          result(FlutterError(code: "reminders", message: "Invalid reminder plan", details: nil)); return
        }
        let unchanged = self.plan["signature"] as? String == data["signature"] as? String
        self.plan = data; self.defaults.set(data, forKey: "haq.reminders.v1")
        self.replace(result, keepSnoozes: unchanged)
      case "status":
        self.center.getNotificationSettings { state in
          self.center.getPendingNotificationRequests { requests in
            DispatchQueue.main.async {
              result(["platform": "ios", "allowed": state.authorizationStatus == .authorized || state.authorizationStatus == .provisional,
                      "overlay": false, "overlayRunning": false, "speech": false,
                      "pending": requests.filter { $0.identifier.hasPrefix(self.prefix) }.count,
                      "failed": self.failure != nil])
            }
          }
        }
      case "pendingOpen": result(self.pendingRoute); self.pendingRoute = nil; self.dartReady = true
      case "requestPermission":
        self.center.requestAuthorization(options: [.alert, .sound, .badge]) { _, error in
          DispatchQueue.main.async {
            if let error = error { result(FlutterError(code: "permission", message: error.localizedDescription, details: nil)) }
            else { result(nil) }
          }
        }
      case "notificationSettings", "batterySettings":
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        result(nil)
      case "preview":
        let content = self.content(["title": "معاينة تذكيرات حق", "body": "هذه معاينة لمظهر التذكير", "route": "settings"])
        self.center.add(UNNotificationRequest(identifier: self.prefix + "preview", content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))) { error in
          DispatchQueue.main.async { result(error.map { FlutterError(code: "reminders", message: $0.localizedDescription, details: nil) }) }
        }
      default: result(FlutterMethodNotImplemented)
      }
    }
  }
  private func clearPrivate(keepSnoozes: Bool = false, _ completion: @escaping () -> Void) {
    center.getPendingNotificationRequests { requests in
      self.center.removePendingNotificationRequests(withIdentifiers: requests.filter {
        $0.identifier.hasPrefix(self.prefix) && (!keepSnoozes || !$0.identifier.hasSuffix(":snooze"))
      }.map { $0.identifier })
      self.center.getDeliveredNotifications { delivered in
        if !keepSnoozes {
          self.center.removeDeliveredNotifications(withIdentifiers: delivered.filter { $0.request.identifier.hasPrefix(self.prefix) }.map { $0.request.identifier })
        }
        DispatchQueue.main.async { completion() }
      }
    }
  }
  private func content(_ job: [String: Any]) -> UNMutableNotificationContent {
    let c = UNMutableNotificationContent()
    c.title = job["title"] as? String ?? "حق"; c.body = job["body"] as? String ?? ""
    c.sound = plan["sound"] as? Bool == false ? nil : .default
    c.categoryIdentifier = "haq-reminder"
    c.userInfo = ["scope": plan["scope"] as? String ?? "guest", "route": job["route"] as? String ?? "adhkar"]
    return c
  }
  private func replace(_ result: @escaping FlutterResult, keepSnoozes: Bool = false) {
    generation += 1
    let revision = generation, snapshot = plan
    failure = nil
    clearPrivate(keepSnoozes: keepSnoozes) {
      guard revision == self.generation else { result(nil); return }
      let jobs = snapshot["jobs"] as? [[String: Any]] ?? []
      let calendar = Calendar.current
      var requests: [UNNotificationRequest] = []
      var dated: [(Date, UNNotificationRequest)] = []
      let now = Date()
      for job in jobs {
        guard let id = job["id"] as? String, let minute = job["minute"] as? Int else { continue }
        let c = self.content(job)
        if let interval = job["interval"] as? Int {
          // A single repeating iOS request uses the selected first text. It is
          // refreshed on opening the app; iOS cannot run arbitrary overlay/TTS.
          guard let text = (snapshot["smartItems"] as? [String])?.first else { continue }
          c.body = text
          requests.append(UNNotificationRequest(identifier: self.prefix + id, content: c,
              trigger: UNTimeIntervalNotificationTrigger(timeInterval: Double(max(1, interval) * 60), repeats: true)))
        } else if let start = job["start"] as? String, let end = job["end"] as? String {
          // Bounded khatma plans must never become infinite daily triggers.
          for offset in 0..<60 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: now),
                  let date = calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day), date > now else { continue }
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            let key = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
            if key < start || key > end { continue }
            let trigger = UNCalendarNotificationTrigger(dateMatching: calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date), repeats: false)
            dated.append((date, UNNotificationRequest(identifier: self.prefix + id + ":" + key, content: c, trigger: trigger)))
          }
        } else {
          var parts = DateComponents(); parts.hour = minute / 60; parts.minute = minute % 60
          if let weekday = job["weekday"] as? Int { parts.weekday = weekday % 7 + 1 }
          requests.append(UNNotificationRequest(identifier: self.prefix + id, content: c,
              trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: true)))
        }
      }
      self.center.getPendingNotificationRequests { existing in
        DispatchQueue.main.async {
          guard revision == self.generation else { result(nil); return }
          let capacity = max(0, 60 - existing.filter { !$0.identifier.hasPrefix(self.prefix) || $0.identifier.hasSuffix(":snooze") }.count)
          let remaining = max(0, capacity - requests.count)
          requests += dated.sorted { $0.0 < $1.0 }.prefix(remaining).map { $0.1 }
          let group = DispatchGroup()
          for request in requests.prefix(capacity) {
            group.enter()
            self.center.add(request) { error in
              DispatchQueue.main.async { if let error = error { self.failure = error }; group.leave() }
            }
          }
          group.notify(queue: .main) {
            if let error = self.failure { result(FlutterError(code: "reminders", message: error.localizedDescription, details: nil)) }
            else { result(nil) }
          }
        }
      }
    }
  }
  func receive(_ response: UNNotificationResponse) {
    let info = response.notification.request.content.userInfo
    guard info["scope"] as? String == plan["scope"] as? String else { return }
    if response.actionIdentifier == "haq-snooze" {
      let request = response.notification.request
      let seconds = (plan["snooze"] as? Int ?? 10) * 60
      center.add(UNNotificationRequest(identifier: request.identifier + ":snooze", content: request.content,
          trigger: UNTimeIntervalNotificationTrigger(timeInterval: Double(seconds), repeats: false)))
    } else {
      let route = info["route"] as? String ?? "adhkar"
      if dartReady { channel.invokeMethod("open", arguments: route) }
      else { pendingRoute = route }
    }
  }
}
