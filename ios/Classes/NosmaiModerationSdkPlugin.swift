import AVFoundation
import Flutter
import Foundation

/// iOS side of the Nosmai moderation Flutter plugin. Implements the
/// Pigeon-generated NosmaiModerationApi and bridges to the native SDK through
/// NosmaiBridge (Obj-C), which returns plain dictionaries — keeping the SDK's
/// Clang module and its type names out of Swift entirely.
public class NosmaiModerationSdkPlugin: NSObject, FlutterPlugin, NosmaiModerationApi, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = NosmaiModerationSdkPlugin()
    NosmaiModerationApiSetup.setUp(binaryMessenger: registrar.messenger(), api: instance)

    // Live streaming: native camera preview (platform view) + start/stop control
    // channel + a result event stream. Frames and detection stay native; only the
    // per-frame result crosses to Dart.
    registrar.register(NosmaiPreviewFactory(), withId: "nosmai_moderation_sdk/preview")

    let control = FlutterMethodChannel(
      name: "nosmai_moderation_sdk/live", binaryMessenger: registrar.messenger())
    control.setMethodCallHandler { [weak instance] call, result in
      switch call.method {
      case "start":
        let facing = (call.arguments as? [String: Any])?["facing"] as? String
        let position: AVCaptureDevice.Position = (facing == "front") ? .front : .back
        NosmaiBridge.startStream { dict in
          DispatchQueue.main.async { instance?.eventSink?(dict) }
        }
        NosmaiCamera.shared.start(position: position) { message in
          // Surface camera-start failures (permission denied, no camera, runtime
          // error) on the results stream so Dart's onError fires.
          instance?.eventSink?(FlutterError(code: "camera_error", message: message, details: nil))
        }
        result(nil)
      case "stop":
        NosmaiBridge.stopStream()
        NosmaiCamera.shared.stop()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let events = FlutterEventChannel(
      name: "nosmai_moderation_sdk/live_events", binaryMessenger: registrar.messenger())
    events.setStreamHandler(instance)
  }

  public func onListen(withArguments arguments: Any?,
                       eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  func initialize(
    licenseKey: String,
    models: [NosmaiModel],
    completion: @escaping (Result<NosmaiInitResult, Error>) -> Void
  ) {
    // Bitmask matching NosmaiModelOptions (objectDetection=1, nsfw=2, text=4).
    var mask: UInt = 0
    for m in models {
      switch m {
      case .objectDetection: mask |= 1
      case .nsfw: mask |= 2
      case .text: mask |= 4
      }
    }
    DispatchQueue.global(qos: .userInitiated).async {
      let error = NosmaiBridge.initialize(withLicenseKey: licenseKey, models: mask)
      completion(.success(NosmaiInitResult(success: error == nil, error: error)))
    }
  }

  func initializeText(completion: @escaping (Result<Bool, Error>) -> Void) {
    DispatchQueue.global(qos: .userInitiated).async {
      completion(.success(NosmaiBridge.initializeText()))
    }
  }

  func analyzeImage(
    filePath: String,
    completion: @escaping (Result<NosmaiResult, Error>) -> Void
  ) {
    DispatchQueue.global(qos: .userInitiated).async {
      let d = NosmaiBridge.analyzeImage(atPath: filePath)
      // An empty dict means the image couldn't be analyzed (bad path / not
      // initialized). Surface that as a real error rather than a fake SAFE result.
      if d.isEmpty {
        completion(.failure(PigeonError(code: "analyze_failed",
                                        message: "Could not analyze image at \(filePath)",
                                        details: nil)))
        return
      }
      completion(.success(Self.toResult(d)))
    }
  }

  func analyzeVideo(
    filePath: String,
    frameIntervalMs: Int64,
    completion: @escaping (Result<NosmaiVideoResult, Error>) -> Void
  ) {
    NosmaiBridge.analyzeVideo(atPath: filePath, frameIntervalMs: frameIntervalMs) { d in
      completion(.success(Self.toVideoResult(d)))
    }
  }

  func moderateText(
    message: String,
    completion: @escaping (Result<NosmaiTextResult, Error>) -> Void
  ) {
    DispatchQueue.global(qos: .userInitiated).async {
      let d = NosmaiBridge.moderateText(message)
      if d.isEmpty {
        completion(.failure(PigeonError(code: "text_not_ready",
                                        message: "Text moderation not initialized",
                                        details: nil)))
        return
      }
      completion(.success(Self.toTextResult(d)))
    }
  }

  func setThreshold(category: NosmaiCategory, value: Double) throws {
    NosmaiBridge.setThreshold(category.rawValue, value: value)
  }

  func setNsfwThreshold(nsfwClass: NosmaiNsfwClass, value: Double) throws {
    NosmaiBridge.setNsfwThreshold(nsfwClass.rawValue, value: value)
  }

  func shutdown() throws {
    // Stop the camera synchronously (cheap), but run the SDK teardown (joins
    // worker threads) off the platform thread so it never hitches the UI.
    NosmaiCamera.shared.stop()
    DispatchQueue.global(qos: .userInitiated).async {
      NosmaiBridge.shutdown()
    }
  }

  // ---- dictionary -> Pigeon mapping ----

  private static func b(_ d: [AnyHashable: Any], _ k: String) -> Bool {
    (d[k] as? NSNumber)?.boolValue ?? false
  }
  private static func i(_ d: [AnyHashable: Any], _ k: String) -> Int {
    (d[k] as? NSNumber)?.intValue ?? 0
  }
  private static func dbl(_ d: [AnyHashable: Any], _ k: String) -> Double {
    (d[k] as? NSNumber)?.doubleValue ?? 0
  }

  private static func toResult(_ d: [AnyHashable: Any]) -> NosmaiResult {
    let detections: [NosmaiObjectDetection?] = (d["detections"] as? [[AnyHashable: Any]] ?? []).map {
      NosmaiObjectDetection(
        category: NosmaiCategory(rawValue: i($0, "category")) ?? .weapon,
        confidence: dbl($0, "confidence"))
    }
    return NosmaiResult(
      isUnsafe: b(d, "isUnsafe"),
      detections: detections,
      nsfw: NosmaiNsfwVerdict(rawValue: i(d, "nsfw")) ?? .safe,
      nsfwSafe: dbl(d, "nsfwSafe"),
      nsfwSexy: dbl(d, "nsfwSexy"),
      nsfwExplicit: dbl(d, "nsfwExplicit"),
      rawWeapon: dbl(d, "rawWeapon"),
      rawDrug: dbl(d, "rawDrug"),
      rawCigarette: dbl(d, "rawCigarette"),
      rawAlcohol: dbl(d, "rawAlcohol"))
  }

  private static func toVideoResult(_ d: [AnyHashable: Any]) -> NosmaiVideoResult {
    let categories: [NosmaiCategory?] = (d["categories"] as? [NSNumber] ?? []).map {
      NosmaiCategory(rawValue: $0.intValue) ?? .weapon
    }
    let flags: [NosmaiVideoFlag?] = (d["flags"] as? [[AnyHashable: Any]] ?? []).map {
      NosmaiVideoFlag(
        timestampMs: Int64(i($0, "timestampMs")),
        category: NosmaiCategory(rawValue: i($0, "category")) ?? .weapon,
        confidence: dbl($0, "confidence"))
    }
    let nsfwFlagged: [Int64?] = (d["nsfwFlaggedMs"] as? [NSNumber] ?? []).map { $0.int64Value }
    return NosmaiVideoResult(
      isUnsafe: b(d, "isUnsafe"),
      categories: categories,
      flags: flags,
      framesAnalyzed: Int64(i(d, "framesAnalyzed")),
      nsfw: NosmaiNsfwVerdict(rawValue: i(d, "nsfw")) ?? .safe,
      nsfwFlaggedMs: nsfwFlagged)
  }

  private static func toTextResult(_ d: [AnyHashable: Any]) -> NosmaiTextResult {
    NosmaiTextResult(
      blocked: b(d, "blocked"),
      layer: NosmaiTextLayer(rawValue: i(d, "layer")) ?? NosmaiTextLayer.none,
      category: NosmaiTextCategory(rawValue: i(d, "category")) ?? .safe,
      score: dbl(d, "score"),
      matchedWord: (d["matchedWord"] as? String) ?? "")
  }
}
