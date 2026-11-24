import Flutter
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    WorkmanagerPlugin.registerPeriodicTask(
        withIdentifier: "com.rodonisi.kover.periodic_task",
        frequency: NSNumber(value: 60 * 60) // 1 hour (15 min minimum)
    )
      
    WorkmanagerDebug.setCurrent(NotificationDebugHandler())
      
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private var backgroundTask: UIBackgroundTaskIdentifier = .invalid

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "KoverBackgroundTask")
    let channel = FlutterMethodChannel(
      name: "kover/background_task",
      binaryMessenger: registrar!.messenger()
    )
    channel.setMethodCallHandler { [weak self] call, result in
      switch call.method {
      case "begin":
        self?.beginBackgroundTask()
        result(nil)
      case "end":
        self?.endBackgroundTask()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func beginBackgroundTask() {
    guard backgroundTask == .invalid else { return }
    backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "kover.downloads") { [weak self] in
      self?.endBackgroundTask()
    }
  }

  private func endBackgroundTask() {
    guard backgroundTask != .invalid else { return }
    UIApplication.shared.endBackgroundTask(backgroundTask)
    backgroundTask = .invalid
  }
}
