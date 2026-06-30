// Pigeon schema — the type-safe contract between Dart and the native Nosmai SDK.
// Edit this file, then regenerate the Dart/Kotlin/Swift messaging code with:
//
//   dart run pigeon --input pigeons/messages.dart
//
// Do NOT edit the generated files (lib/src/messages.g.dart,
// android/.../Messages.g.kt, ios/Classes/Messages.g.swift) by hand.

import 'package:pigeon/pigeon.dart';

@ConfigurePigeon(PigeonOptions(
  dartOut: 'lib/src/messages.g.dart',
  kotlinOut:
      'android/src/main/kotlin/com/nosmai/nosmai_moderation_sdk/Messages.g.kt',
  kotlinOptions: KotlinOptions(package: 'com.nosmai.nosmai_moderation_sdk'),
  swiftOut: 'ios/Classes/Messages.g.swift',
  dartPackageName: 'nosmai_moderation_sdk',
))

/// Object-detector categories (match the native SDK's class order).
enum NosmaiCategory { weapon, drug, cigarette, alcohol }

/// Whole-image NSFW verdict. `block` makes a frame unsafe; `warn` (suggestive)
/// is advisory only.
enum NosmaiNsfwVerdict { safe, warn, block }

/// NSFW classes used by [NosmaiModerationApi.setNsfwThreshold].
enum NosmaiNsfwClass { explicit, safe, sexy }

/// Chat-text moderation categories.
enum NosmaiTextCategory { safe, profanity, toxic, hate, harassment, threat }

/// Which text layer produced the verdict.
enum NosmaiTextLayer { none, blocklist, classifier }

/// Models that can be loaded at [NosmaiModerationApi.initialize]. Only the models
/// you pass are loaded; anything omitted never loads.
enum NosmaiModel { objectDetection, nsfw, text }

class NosmaiObjectDetection {
  NosmaiCategory? category;
  double? confidence;
}

class NosmaiResult {
  bool? isUnsafe;
  List<NosmaiObjectDetection?>? detections;
  // NSFW classifier output for the same frame.
  NosmaiNsfwVerdict? nsfw;
  double? nsfwSafe;
  double? nsfwSexy;
  double? nsfwExplicit;
  // Best raw object score per class (debug / tuning).
  double? rawWeapon;
  double? rawDrug;
  double? rawCigarette;
  double? rawAlcohol;
}

class NosmaiVideoFlag {
  int? timestampMs;
  NosmaiCategory? category;
  double? confidence;
}

class NosmaiVideoResult {
  bool? isUnsafe;
  List<NosmaiCategory?>? categories;
  List<NosmaiVideoFlag?>? flags;
  int? framesAnalyzed;
  NosmaiNsfwVerdict? nsfw;
  List<int?>? nsfwFlaggedMs;
}

class NosmaiTextResult {
  bool? blocked;
  NosmaiTextLayer? layer;
  NosmaiTextCategory? category;
  double? score;
  String? matchedWord;
}

/// Result of [NosmaiModerationApi.initialize] — `success` plus an `error`
/// message (e.g. license invalid / expired) when it fails.
class NosmaiInitResult {
  bool? success;
  String? error;
}

@HostApi()
abstract class NosmaiModerationApi {
  /// Validates the license and loads ONLY the requested [models]. A model you do
  /// not pass never loads. Runs on a background thread natively.
  @async
  NosmaiInitResult initialize(String licenseKey, List<NosmaiModel> models);

  /// Loads the chat text-moderation model. Optional — call only if you moderate
  /// text.
  @async
  bool initializeText();

  /// Moderates a single image file (objects + NSFW).
  @async
  NosmaiResult analyzeImage(String filePath);

  /// Moderates a recorded video, sampling one frame per [frameIntervalMs].
  @async
  NosmaiVideoResult analyzeVideo(String filePath, int frameIntervalMs);

  /// Moderates a chat message (Layer-1 blocklist + Layer-2 toxicity model).
  @async
  NosmaiTextResult moderateText(String message);

  /// Overrides an object-detector confidence threshold (0..1).
  void setThreshold(NosmaiCategory category, double value);

  /// Overrides an NSFW decision threshold (explicit -> BLOCK, sexy -> WARN).
  void setNsfwThreshold(NosmaiNsfwClass nsfwClass, double value);

  /// Releases the engine and frees memory.
  void shutdown();
}
