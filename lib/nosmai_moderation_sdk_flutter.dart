import 'src/messages.g.dart';

export 'src/live.dart' show NosmaiLive, NosmaiCameraPreview, NosmaiCameraFacing;

// Re-export the generated value types so consumers import a single file.
export 'src/messages.g.dart'
    show
        NosmaiCategory,
        NosmaiModel,
        NosmaiNsfwVerdict,
        NosmaiNsfwClass,
        NosmaiTextCategory,
        NosmaiTextLayer,
        NosmaiObjectDetection,
        NosmaiResult,
        NosmaiVideoFlag,
        NosmaiVideoResult,
        NosmaiTextResult,
        NosmaiInitResult;

/// On-device content + text moderation for Flutter, powered by the native
/// Nosmai SDK (CoreML/ANE on iOS, NCNN/Vulkan on Android). Detection runs fully
/// offline — no frame or message leaves the device.
///
/// Every image/video frame is checked by BOTH the object detector
/// (weapon / drug / cigarette / alcohol) and the NSFW classifier; the combined
/// verdict comes back in one [NosmaiResult].
///
/// ```dart
/// final init = await NosmaiModeration.initialize('NOSMAI-XXXX-XXXX',
///     models: [NosmaiModel.objectDetection, NosmaiModel.nsfw]);
/// if (init.success != true) {
///   // license missing / invalid / expired — see init.error
///   return;
/// }
/// final r = await NosmaiModeration.analyzeImage(file.path);
/// if (r.isUnsafe == true) {
///   // r.detections (objects) + r.nsfw (SAFE / WARN / BLOCK)
/// }
/// ```
class NosmaiModeration {
  NosmaiModeration._();

  static final NosmaiModerationApi _api = NosmaiModerationApi();

  /// Validates the [licenseKey] and loads ONLY the [models] you request. A model
  /// you omit never loads (no memory or startup cost); passing an empty list
  /// validates the license but loads nothing. Call once at startup. The native
  /// side runs the (networked) license check on a background thread. On failure,
  /// [NosmaiInitResult.success] is `false` and [NosmaiInitResult.error] explains
  /// why (invalid / expired / network).
  ///
  /// ```dart
  /// await NosmaiModeration.initialize('NOSMAI-XXXX',
  ///     models: [NosmaiModel.objectDetection, NosmaiModel.nsfw]);
  /// ```
  static Future<NosmaiInitResult> initialize(
    String licenseKey, {
    List<NosmaiModel> models = const [],
  }) =>
      _api.initialize(licenseKey, models);

  /// Loads the chat text-moderation model. Optional — call only if you moderate
  /// text. Layer-1 keyword blocklist still applies if the model is unavailable.
  static Future<bool> initializeText() => _api.initializeText();

  /// Moderates a single image [filePath] (objects + NSFW).
  static Future<NosmaiResult> analyzeImage(String filePath) =>
      _api.analyzeImage(filePath);

  /// Moderates the recorded video at [filePath], sampling one frame every
  /// [frameIntervalMs] and aggregating the result.
  static Future<NosmaiVideoResult> analyzeVideo(
    String filePath, {
    int frameIntervalMs = 500,
  }) =>
      _api.analyzeVideo(filePath, frameIntervalMs);

  /// Moderates a chat [message] (Layer-1 blocklist + Layer-2 toxicity model).
  static Future<NosmaiTextResult> moderateText(String message) =>
      _api.moderateText(message);

  /// Overrides an object-detector confidence threshold (0..1).
  static Future<void> setThreshold(NosmaiCategory category, double value) =>
      _api.setThreshold(category, value);

  /// Overrides an NSFW decision threshold ([NosmaiNsfwClass.explicit] = BLOCK
  /// bar, [NosmaiNsfwClass.sexy] = WARN bar).
  static Future<void> setNsfwThreshold(
    NosmaiNsfwClass nsfwClass,
    double value,
  ) =>
      _api.setNsfwThreshold(nsfwClass, value);

  /// Releases the engine and frees memory.
  static Future<void> shutdown() => _api.shutdown();
}
