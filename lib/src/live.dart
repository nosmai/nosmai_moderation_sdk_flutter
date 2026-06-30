import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'messages.g.dart';

/// Which camera the live preview uses.
enum NosmaiCameraFacing { back, front }

/// Real-time camera moderation. The camera, frame capture and detection all run
/// natively for performance; only the per-frame [NosmaiResult] crosses to Dart.
///
/// Usage: show [NosmaiCameraPreview] on screen, call [start], listen to
/// [results], and call [stop] when leaving the screen.
class NosmaiLive {
  NosmaiLive._();

  static const MethodChannel _control =
      MethodChannel('nosmai_moderation_sdk/live');
  static const EventChannel _events =
      EventChannel('nosmai_moderation_sdk/live_events');

  /// Starts the camera and live detection. Request camera permission first.
  /// If [facing] is unavailable the SDK falls back to the other camera; if no
  /// camera can be bound, [results] emits a stream error.
  static Future<void> start({
    NosmaiCameraFacing facing = NosmaiCameraFacing.back,
  }) =>
      _control.invokeMethod<void>('start', {'facing': facing.name});

  /// Stops the camera and live detection.
  static Future<void> stop() => _control.invokeMethod<void>('stop');

  /// A broadcast stream of per-frame results while the camera is running.
  /// Emits a stream error (PlatformException) if the camera fails to start.
  static Stream<NosmaiResult> results() => _events
      .receiveBroadcastStream()
      .map((event) => _toResult(Map<Object?, Object?>.from(event as Map)));

  static NosmaiResult _toResult(Map<Object?, Object?> d) {
    final detections = ((d['detections'] as List<Object?>?) ?? const [])
        .map((e) {
          final m = Map<Object?, Object?>.from(e! as Map);
          return NosmaiObjectDetection(
            category: NosmaiCategory.values[(m['category'] as num?)?.toInt() ?? 0],
            confidence: (m['confidence'] as num?)?.toDouble() ?? 0,
          );
        })
        .toList();
    return NosmaiResult(
      isUnsafe: d['isUnsafe'] == true,
      detections: detections,
      nsfw: NosmaiNsfwVerdict.values[(d['nsfw'] as num?)?.toInt() ?? 0],
      nsfwSafe: (d['nsfwSafe'] as num?)?.toDouble() ?? 0,
      nsfwSexy: (d['nsfwSexy'] as num?)?.toDouble() ?? 0,
      nsfwExplicit: (d['nsfwExplicit'] as num?)?.toDouble() ?? 0,
      rawWeapon: (d['rawWeapon'] as num?)?.toDouble() ?? 0,
      rawDrug: (d['rawDrug'] as num?)?.toDouble() ?? 0,
      rawCigarette: (d['rawCigarette'] as num?)?.toDouble() ?? 0,
      rawAlcohol: (d['rawAlcohol'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Native camera preview for live moderation. Pair with [NosmaiLive].
class NosmaiCameraPreview extends StatelessWidget {
  const NosmaiCameraPreview({super.key});

  static const String _viewType = 'nosmai_moderation_sdk/preview';

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return const UiKitView(
        viewType: _viewType,
        creationParamsCodec: StandardMessageCodec(),
      );
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return const AndroidView(
        viewType: _viewType,
        creationParamsCodec: StandardMessageCodec(),
      );
    }
    return const ColoredBox(color: Color(0xFF000000));
  }
}
