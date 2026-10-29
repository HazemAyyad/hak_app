import Flutter
import UIKit
import Photos
import UserNotifications
import CoreLocation
import AVFoundation
import FirebaseCore

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var haqReminders: HaqReminderCenter?
  private var haqPrayer: HaqPrayerDevice?
  private var haqPendingResponse: UNNotificationResponse?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    if FirebaseApp.app() == nil && Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
      FirebaseApp.configure()
    }
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HaqPrayer") {
      haqPrayer = HaqPrayerDevice(messenger: registrar.messenger())
    }
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
        guard let data = call.arguments as? [String: Any], let jobs = data["jobs"] as? [[String: Any]], jobs.count <= 512 else {
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
      case "adhanStatus":
        let recordings = ((try? FileManager.default.contentsOfDirectory(atPath: NSHomeDirectory() + "/Library/Sounds")) ?? []).compactMap { name -> String? in
          guard name.hasPrefix("haq-adhan-"), name.hasSuffix(".caf") else { return nil }
          let id = String(name.dropFirst(10).dropLast(4))
          return id.range(of: "^reminder-[0-9a-f]{16}-(fajr|dhuhr|asr|maghrib|isha)$", options: .regularExpression) != nil ? id : nil
        }
        result(["platform": "ios", "exact": false, "fullScreen": false, "reminderRecordings": recordings])
      case "prepareAdhan", "preparePrayerReminder":
        guard let args = call.arguments as? [String: Any], let id = args["id"] as? String,
              (id.range(of: "^(alafasy|nafees|mustafa|zahrani|archive-[0-9a-f]{16}|reminder-[0-9a-f]{16}-(fajr|dhuhr|asr|maghrib|isha))$", options: .regularExpression) != nil), let path = args["path"] as? String else {
          result(FlutterError(code: "audio", message: "Invalid voice", details: nil)); return
        }
        let source = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath()
        guard source.path.hasPrefix(NSHomeDirectory() + "/") else {
          result(FlutterError(code: "audio", message: "Invalid audio path", details: nil)); return
        }
        DispatchQueue.global(qos: .userInitiated).async {
          do {
            let file = try AVAudioFile(forReading: source)
            if call.method == "preparePrayerReminder" && Double(file.length) / file.processingFormat.sampleRate > 30 { throw NSError(domain: "HaqAudio", code: 5) }
            let format = file.processingFormat
            guard format.channelCount <= 2, format.sampleRate > 0, format.sampleRate <= 96000 else { throw NSError(domain: "HaqAudio", code: 1) }
            let frames = AVAudioFrameCount(min(file.length, AVAudioFramePosition(format.sampleRate * 25)))
            guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { throw NSError(domain: "HaqAudio", code: 2) }
            try file.read(into: buffer, frameCount: frames)
            let folder = URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Sounds", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let target = folder.appendingPathComponent("haq-adhan-\(id).caf")
            let temporary = folder.appendingPathComponent("haq-adhan-\(id)-pending.caf")
            do {
              let output = try AVAudioFile(forWriting: temporary, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: format.sampleRate,
                AVNumberOfChannelsKey: format.channelCount, AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false
              ], commonFormat: format.commonFormat, interleaved: format.isInterleaved)
              try output.write(from: buffer)
            }
            if FileManager.default.fileExists(atPath: target.path) { _ = try FileManager.default.replaceItemAt(target, withItemAt: temporary) }
            else { try FileManager.default.moveItem(at: temporary, to: target) }
            DispatchQueue.main.async { result(true) }
          } catch { DispatchQueue.main.async { result(FlutterError(code: "audio", message: "Unable to prepare notification audio", details: nil)) } }
        }
      case "communityMessage":
        guard let args = call.arguments as? [String: Any], let scope = args["scope"] as? String,
              scope == self.plan["scope"] as? String, let id = args["id"] as? Int, id > 0 else { result(false); return }
        let capturedGeneration = self.generation
        self.center.getNotificationSettings { settings in
          guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { DispatchQueue.main.async { result(false) }; return }
          DispatchQueue.main.async {
          guard self.generation == capturedGeneration, scope == self.plan["scope"] as? String else { result(false); return }
          let content = UNMutableNotificationContent()
          content.title = "رسائل حق"; content.body = "وصل محتوى جديد إلى رسائل حق"
          if args["sound"] as? Bool == true { content.sound = .default }
          content.userInfo = ["route": "messages", "scope": scope]
          let request = UNNotificationRequest(identifier: "haq-reminder:community", content: content, trigger: nil)
          self.center.add(request) { error in DispatchQueue.main.async { result(error == nil) } }
          }
        }
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
    c.sound = job["alertMode"] != nil || plan["sound"] as? Bool != false ? .default : nil
    if let mode = job["alertMode"] as? String {
      if mode == "silent" || mode == "vibration" { c.sound = nil }
      else if (mode == "adhan" || mode == "reminderVoice"),
              let voice = job["voice"] as? String, voice.range(of: "^(alafasy|nafees|mustafa|zahrani|archive-[0-9a-f]{16}|reminder-[0-9a-f]{16}-(fajr|dhuhr|asr|maghrib|isha))$", options: .regularExpression) != nil {
        let name = "haq-adhan-\(voice).caf"
        if FileManager.default.fileExists(atPath: NSHomeDirectory() + "/Library/Sounds/" + name) {
          c.sound = UNNotificationSound(named: UNNotificationSoundName(rawValue: name))
        }
      }
    }
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
        if let at = job["at"] as? NSNumber {
          let date = Date(timeIntervalSince1970: at.doubleValue / 1000)
          guard date > now else { continue }
          let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
          dated.append((date, UNNotificationRequest(identifier: self.prefix + id, content: c, trigger: trigger)))
        } else if let interval = job["interval"] as? Int {
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

/// Foreground CoreLocation only. iOS trueHeading is used when available;
/// magnetic-only readings are labelled and never presented as verified north.
private final class HaqPrayerDevice: NSObject, CLLocationManagerDelegate, FlutterStreamHandler {
  private let manager = CLLocationManager()
  private let channel: FlutterMethodChannel
  private let events: FlutterEventChannel
  private var sink: FlutterEventSink?
  private var pending: FlutterResult?
  private var timeout: DispatchWorkItem?
  private var requested = false
  private let geocoder = CLGeocoder()
  private var backgroundObserver: NSObjectProtocol?
  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "com.haqfoundation.haq_app/prayer", binaryMessenger: messenger)
    events = FlutterEventChannel(name: "com.haqfoundation.haq_app/heading", binaryMessenger: messenger)
    super.init()
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    manager.headingFilter = 1
    events.setStreamHandler(self)
    backgroundObserver = NotificationCenter.default.addObserver(forName: UIApplication.willResignActiveNotification,
        object: nil, queue: .main) { [weak self] _ in self?.stopHeading() }
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      switch call.method {
      case "status":
        let status = CLLocationManager.authorizationStatus()
        result(["permission": status == .authorizedWhenInUse || status == .authorizedAlways,
                "enabled": CLLocationManager.locationServicesEnabled(), "zone": TimeZone.current.identifier,
                "heading": CLLocationManager.headingAvailable()])
      case "requestLocation":
        guard self.pending == nil else { result(FlutterError(code: "busy", message: "Location request pending", details: nil)); return }
        self.pending = result; self.requested = false
        let work = DispatchWorkItem { [weak self] in self?.fail("timeout", "No recent location available") }
        self.timeout = work; DispatchQueue.main.asyncAfter(deadline: .now() + 30, execute: work)
        if !CLLocationManager.locationServicesEnabled() { self.fail("disabled", "Location services disabled") }
        else if CLLocationManager.authorizationStatus() == .notDetermined { self.manager.requestWhenInUseAuthorization() }
        else { self.authorized() }
      case "settings":
        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        result(nil)
      case "reverseGeocode":
        guard let args = call.arguments as? [String: Any], let lat = args["lat"] as? Double,
              let lng = args["lng"] as? Double, lat.isFinite, lng.isFinite,
              (-90...90).contains(lat), (-180...180).contains(lng) else {
          result(FlutterError(code: "location", message: "Invalid coordinates", details: nil)); return
        }
        let status = CLLocationManager.authorizationStatus()
        guard status == .authorizedWhenInUse || status == .authorizedAlways else { result(nil); return }
        var finished = false
        let timeout = DispatchWorkItem { [weak self] in
          guard !finished else { return }; finished = true
          self?.geocoder.cancelGeocode(); result(nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.5, execute: timeout)
        self.geocoder.reverseGeocodeLocation(CLLocation(latitude: lat, longitude: lng), preferredLocale: Locale(identifier: "ar")) { places, _ in
          DispatchQueue.main.async {
            guard !finished else { return }; finished = true; timeout.cancel()
            guard let place = places?.first, let city = place.locality ?? place.subAdministrativeArea,
                  !city.isEmpty, let country = place.country, !country.isEmpty else { result(nil); return }
            result(["city": city, "country": country])
          }
        }
      case "openMap":
        guard let raw = call.arguments as? String, let url = URL(string: raw), url.scheme == "https", url.host == "www.openstreetmap.org" else {
          result(FlutterError(code: "map", message: "Invalid map URL", details: nil)); return
        }
        UIApplication.shared.open(url, options: [:]) { opened in
          result(opened ? nil : FlutterError(code: "map", message: "No map handler", details: nil))
        }
      default: result(FlutterMethodNotImplemented)
      }
    }
  }
  private func authorized() {
    guard pending != nil else { return }
    let status = CLLocationManager.authorizationStatus()
    if status == .denied || status == .restricted { fail("denied", "Location permission denied") }
    else if (status == .authorizedWhenInUse || status == .authorizedAlways) && !requested {
      requested = true; manager.requestLocation()
    }
  }
  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { authorized() }
  func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) { authorized() }
  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let result = pending else { return }
    guard let location = locations.last, location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 5000,
          abs(location.timestamp.timeIntervalSinceNow) <= 300 else { fail("stale", "No accurate recent location"); return }
    pending = nil; timeout?.cancel(); timeout = nil
    result(["lat": location.coordinate.latitude, "lng": location.coordinate.longitude,
            "accuracy": location.horizontalAccuracy, "measured": Int64(location.timestamp.timeIntervalSince1970 * 1000),
            "zone": TimeZone.current.identifier])
  }
  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    if pending != nil { fail((error as? CLError)?.code == .denied ? "denied" : "location", "Location unavailable") }
  }
  private func fail(_ code: String, _ message: String) {
    let result = pending; pending = nil; timeout?.cancel(); timeout = nil
    if sink == nil { manager.stopUpdatingLocation() }
    result?(FlutterError(code: code, message: message, details: nil))
  }
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    stopHeading()
    guard CLLocationManager.headingAvailable() else { events(FlutterError(code: "sensor", message: "Heading sensor unavailable", details: nil)); return nil }
    sink = events
    _ = updateHeadingOrientation()
    let status = CLLocationManager.authorizationStatus()
    if status == .authorizedWhenInUse || status == .authorizedAlways { manager.startUpdatingLocation() }
    manager.startUpdatingHeading()
    return nil
  }
  func onCancel(withArguments arguments: Any?) -> FlutterError? { stopHeading(); return nil }
  func stopHeading() {
    sink = nil; manager.stopUpdatingHeading()
    if pending == nil { manager.stopUpdatingLocation() }
  }
  func locationManager(_ manager: CLLocationManager, didUpdateHeading heading: CLHeading) {
    guard let sink = sink else { return }
    guard abs(heading.timestamp.timeIntervalSinceNow) < 5 else { return }
    guard updateHeadingOrientation() else { return }
    let quality = heading.headingAccuracy < 0 ? 0 : heading.headingAccuracy <= 15 ? 3 : heading.headingAccuracy <= 30 ? 2 : 1
    sink(["degrees": heading.trueHeading >= 0 ? heading.trueHeading : heading.magneticHeading,
          "accuracy": quality, "trueNorth": heading.trueHeading >= 0])
  }
  func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool { true }
  private func updateHeadingOrientation() -> Bool {
    let orientation: CLDeviceOrientation
    switch UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive })?.interfaceOrientation {
      case .landscapeLeft: orientation = .landscapeLeft
      case .landscapeRight: orientation = .landscapeRight
      case .portraitUpsideDown: orientation = .portraitUpsideDown
      default: orientation = .portrait
    }
    if manager.headingOrientation == orientation { return true }
    manager.headingOrientation = orientation
    return false
  }
  deinit {
    if let observer = backgroundObserver { NotificationCenter.default.removeObserver(observer) }
    timeout?.cancel(); manager.stopUpdatingHeading(); manager.stopUpdatingLocation()
  }
}
