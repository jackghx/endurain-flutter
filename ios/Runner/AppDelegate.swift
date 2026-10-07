import BackgroundTasks
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  /// Strong reference so the native activity recorder channel outlives engine
  /// setup and keeps its method/event handlers registered.
  private var activityRecorderChannel: ActivityRecorderChannel?

  /// Strong reference for device-region settings queried by Flutter.
  private var deviceSettingsChannel: FlutterMethodChannel?

  /// Channel used by background refresh to drain the Dart upload queue.
  private var backgroundUploadChannel: FlutterMethodChannel?

  /// Must match `BGTaskSchedulerPermittedIdentifiers` in Info.plist.
  static let uploadDrainTaskIdentifier = "com.endurain.endurain.upload-drain"

  /// Whether iOS relaunched the process to deliver a location event.
  ///
  /// Set before the Flutter engine finishes initializing, and consumed in
  /// `didInitializeImplicitFlutterEngine` once the recorder channel exists.
  private var launchedForLocationEvent = false

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    excludeHealthDataFromBackup()
    // A location key means the app was relaunched in the background by
    // significant-location-change monitoring, which the recorder arms while a
    // recording is active. Without this the process would start, do nothing,
    // and the remainder of the activity would be lost.
    launchedForLocationEvent = launchOptions?[.location] != nil
    registerUploadDrainTask()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - Background upload drain

  /// Registers the refresh task that retries failed uploads while suspended,
  /// e.g. when the server was unreachable at the end of a recording and the
  /// tailnet/VPN route comes back later. iOS decides when (and whether) the
  /// task runs; app-resume and connectivity triggers in Dart still apply.
  /// Registration must happen before launch finishes.
  private func registerUploadDrainTask() {
    BGTaskScheduler.shared.register(
      forTaskWithIdentifier: Self.uploadDrainTaskIdentifier,
      using: .main
    ) { [weak self] task in
      guard let self, let refreshTask = task as? BGAppRefreshTask else {
        task.setTaskCompleted(success: false)
        return
      }
      self.handleUploadDrain(refreshTask)
    }
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(scheduleUploadDrain),
      name: UIApplication.didEnterBackgroundNotification,
      object: nil
    )
  }

  @objc private func scheduleUploadDrain() {
    let request = BGAppRefreshTaskRequest(identifier: Self.uploadDrainTaskIdentifier)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
    do {
      try BGTaskScheduler.shared.submit(request)
    } catch {
      NSLog("Unable to schedule upload drain: %@", error.localizedDescription)
    }
  }

  private func handleUploadDrain(_ task: BGAppRefreshTask) {
    // Without a live engine (cold background launch) there is no Dart queue to
    // drain; the next foreground resume drains instead.
    guard let channel = backgroundUploadChannel else {
      task.setTaskCompleted(success: false)
      return
    }
    var completed = false
    let complete: (Bool) -> Void = { success in
      guard !completed else {
        return
      }
      completed = true
      task.setTaskCompleted(success: success)
    }
    task.expirationHandler = {
      DispatchQueue.main.async { complete(false) }
    }
    channel.invokeMethod("drain", arguments: nil) { [weak self] result in
      if result is FlutterError || (result as AnyObject?) === FlutterMethodNotImplemented {
        complete(false)
        return
      }
      if (result as? Bool) == true {
        // Uploads still failing: ask for another window later.
        self?.scheduleUploadDrain()
      }
      complete(true)
    }
  }

  private func excludeHealthDataFromBackup() {
    guard let support = FileManager.default.urls(
      for: .applicationSupportDirectory,
      in: .userDomainMask
    ).first else {
      return
    }
    let directoryNames = ["activity_records", "endurain_private"]
    for directoryName in directoryNames {
      var directory = support.appendingPathComponent(directoryName, isDirectory: true)
      do {
        try FileManager.default.createDirectory(
          at: directory,
          withIntermediateDirectories: true
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
      } catch {
        NSLog("Unable to exclude private Endurain storage from backup: %@", error.localizedDescription)
      }
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "EndurainDeviceSettingsChannel"
    ) {
      let channel = FlutterMethodChannel(
        name: "endurain/device_settings",
        binaryMessenger: registrar.messenger()
      )
      channel.setMethodCallHandler { call, result in
        guard call.method == "getMeasurementSystem" else {
          result(FlutterMethodNotImplemented)
          return
        }
        if #available(iOS 16.0, *) {
          result(Locale.current.measurementSystem == .metric ? "metric" : "imperial")
        } else {
          result(Locale.current.usesMetricSystem ? "metric" : "imperial")
        }
      }
      deviceSettingsChannel = channel
    }
    if let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "EndurainBackgroundUploadChannel"
    ) {
      backgroundUploadChannel = FlutterMethodChannel(
        name: "endurain/background_upload",
        binaryMessenger: registrar.messenger()
      )
    }
    if let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "EndurainActivityRecorderChannel"
    ) {
      let channel = ActivityRecorderChannel()
      channel.register(with: registrar.messenger())
      activityRecorderChannel = channel
      if launchedForLocationEvent {
        launchedForLocationEvent = false
        // Resume the accurate stream immediately rather than waiting for Dart
        // to attach: a background relaunch has a short execution window, and
        // the durable store already holds everything needed to continue.
        channel.resumeAfterRelaunch()
      }
    }
  }
}
