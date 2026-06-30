# nosmai_moderation_sdk

On-device content and text moderation for Flutter, powered by the native Nosmai
SDK. It detects weapons, drugs, cigarettes, and alcohol (object detection) and
NSFW content (nudity and suggestive) in images, videos, and a live camera feed,
and it moderates chat text for toxicity. Everything runs fully offline. No frame
or message leaves the device.

## Features

- Image moderation: objects and NSFW in a single result.
- Video moderation: samples frames and aggregates a verdict.
- Live camera moderation: a native preview with per-frame results.
- Text moderation: chat toxicity using a keyword layer and an AI classifier.
- Selective model loading: load only the models you use.
- Runtime threshold tuning per category.

## Requirements

- iOS 15.1 or later, Android 7.0 (API 24) or later.
- An arm64-v8a Android device (the SDK ships arm64 only).
- Kotlin 2.2.0 or later in the Android host app.
- A Nosmai license key. Register your app's bundle id (iOS) and package id
  (Android) at https://nosmai.com/.

## Installation

Add the plugin:

```bash
flutter pub add nosmai_moderation_sdk
```

The native SDK is not bundled inside this plugin because it is large. Each
platform pulls it from its own published channel.

### iOS

No extra steps. The plugin depends on the `NosmaiModerationSDK` CocoaPods pod, so
`pod install` (run automatically by `flutter run`) downloads the native SDK,
links it, and bundles the encrypted models. Add these keys to your app's
`Info.plist`:

- `NSCameraUsageDescription`: a usage string, required for the live camera.
- `ITSAppUsesNonExemptEncryption` set to `false`: the SDK uses AES only to
  decrypt its own models on device, which qualifies for the export-compliance
  exemption. Confirm with your legal team.

Device builds are arm64. Apple-silicon simulators are supported. Intel-Mac
simulators are not.

### Android

The Android SDK ships as a downloadable AAR because it is too large for pub.dev.
Add it to your app module:

1. Download `nosmai-detection.aar` from the
   [Android SDK releases](https://github.com/nosmai/moderation-sdk-android/releases/latest)
   and place it at `android/app/libs/nosmai-detection.aar`.
2. In `android/app/build.gradle.kts`:
   ```kotlin
   android {
       defaultConfig {
           minSdk = 24
           ndk { abiFilters += "arm64-v8a" }
       }
   }
   dependencies {
       implementation(files("libs/nosmai-detection.aar"))
   }
   ```
3. Distribute as an App Bundle (AAB). The SDK is arm64-v8a only, so test on a
   real device, not an x86_64 emulator.
4. Request the `CAMERA` permission at runtime before starting the live camera,
   for example with the `permission_handler` package.

## Usage

```dart
import 'package:nosmai_moderation_sdk/nosmai_moderation_sdk.dart';

// Initialize once at startup. Load only the models you need.
final init = await NosmaiModeration.initialize(
  'NOSMAI-XXXX',
  models: [NosmaiModel.objectDetection, NosmaiModel.nsfw],
);
if (init.success != true) {
  print('Moderation unavailable: ${init.error}');
}

// Image (objects and NSFW in one result).
final image = await NosmaiModeration.analyzeImage(file.path);
if (image.isUnsafe == true) {
  // image.detections for objects, image.nsfw for SAFE / WARN / BLOCK.
}

// Recorded video.
final video = await NosmaiModeration.analyzeVideo(file.path, frameIntervalMs: 500);

// Chat text (optional model).
await NosmaiModeration.initializeText();
final text = await NosmaiModeration.moderateText('a message to check');
if (text.blocked == true) {
  print('blocked: ${text.category}');
}

// Tune thresholds at runtime.
await NosmaiModeration.setThreshold(NosmaiCategory.weapon, 0.85);
await NosmaiModeration.setNsfwThreshold(NosmaiNsfwClass.explicit, 0.45);

// Free native resources when done.
await NosmaiModeration.shutdown();
```

### Live camera

Show `NosmaiCameraPreview`, start the camera, and listen to results. Call
`NosmaiLive.stop()` when leaving the screen (for example in `dispose`). The
camera does not stop itself on widget disposal.

```dart
@override
void initState() {
  super.initState();
  NosmaiLive.start(facing: NosmaiCameraFacing.back);
  _sub = NosmaiLive.results().listen(
    (r) { /* r.isUnsafe, r.nsfw, r.detections */ },
    onError: (e) { /* camera failed to start */ },
  );
}

@override
void dispose() {
  _sub.cancel();
  NosmaiLive.stop();
  super.dispose();
}

// In build():  const NosmaiCameraPreview()
```

Request the camera permission before opening the live screen. On Android the
preview stays blank if the permission has not been granted.

## How it works

The camera, frame capture, and detection all run natively for performance. Only
the per-frame result crosses to Dart. The request and response APIs (image,
video, text) use Pigeon for type-safe messaging. The live camera uses a method
channel for start and stop, and an event channel for per-frame results. Models
are encrypted and decrypted in native memory.

## License

Proprietary. See [LICENSE](LICENSE). To get a license key, register your app at
https://nosmai.com/.
