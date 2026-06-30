#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>

NS_ASSUME_NONNULL_BEGIN

/// Thin Objective-C bridge to the native NosmaiDetection SDK. It returns plain
/// Foundation types (dictionaries / numbers) so the Swift plugin can map them to
/// the Pigeon value types without importing the SDK's Clang module (which a
/// static-library xcframework does not reliably expose) and without the
/// Pigeon/native type-name collision.
///
/// Result dictionary shapes:
///   image  -> { isUnsafe:Bool, nsfw:Int, nsfwSafe/Sexy/Explicit:Double,
///               rawWeapon/Drug/Cigarette/Alcohol:Double,
///               detections:[{ category:Int, confidence:Double }] }
///   video  -> { isUnsafe:Bool, framesAnalyzed:Int, nsfw:Int,
///               categories:[Int], nsfwFlaggedMs:[Int],
///               flags:[{ timestampMs:Int, category:Int, confidence:Double }] }
///   text   -> { blocked:Bool, layer:Int, category:Int, score:Double,
///               matchedWord:String }
@interface NosmaiBridge : NSObject

/// Returns nil on success, or an error message on failure. `models` is a bitmask
/// matching NosmaiModelOptions (objectDetection=1, nsfw=2, text=4); only the
/// requested models load.
+ (nullable NSString *)initializeWithLicenseKey:(NSString *)licenseKey
                                         models:(NSUInteger)models;
+ (BOOL)initializeText;
+ (NSDictionary<NSString *, id> *)analyzeImageAtPath:(NSString *)path;
+ (void)analyzeVideoAtPath:(NSString *)path
           frameIntervalMs:(int64_t)frameIntervalMs
                completion:(void (^)(NSDictionary<NSString *, id> *))completion;
+ (NSDictionary<NSString *, id> *)moderateText:(NSString *)message;
+ (void)setThreshold:(NSInteger)category value:(double)value;
+ (void)setNsfwThreshold:(NSInteger)nsfwClass value:(double)value;
+ (void)shutdown;

#pragma mark - Live stream

/// Starts real-time moderation. `handler` is invoked (on the main thread) with an
/// image-shaped result dictionary for every processed frame. Feed frames with
/// pushFrame:rotation:.
+ (void)startStreamWithResultHandler:(void (^)(NSDictionary<NSString *, id> *))handler;

/// Hands a camera frame to the stream. `rotation` (degrees, e.g. 90) makes the
/// frame upright for the detector.
+ (void)pushFrame:(CVPixelBufferRef)pixelBuffer rotation:(int)rotation;

+ (void)stopStream;

@end

NS_ASSUME_NONNULL_END
