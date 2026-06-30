#import "NosmaiBridge.h"

#import <UIKit/UIKit.h>

#import "NosmaiDetection/NosmaiSDK.h"

/// Forwards SDK stream callbacks to a plain block (image-shaped dictionary).
@interface NosmaiStreamListener : NSObject <NosmaiListener>
@property (nonatomic, copy, nullable) void (^handler)(NSDictionary<NSString *, id> *);
@end

@interface NosmaiBridge ()
+ (NSDictionary<NSString *, id> *)dictFromResult:(NosmaiResult *)r;
@end

@implementation NosmaiBridge

/// Image/stream result -> dictionary (shared by analyzeImage and the live stream).
+ (NSDictionary<NSString *, id> *)dictFromResult:(NosmaiResult *)r {
    NSMutableArray *detections = [NSMutableArray array];
    for (NosmaiDetectionInfo *d in r.detections) {
        [detections addObject:@{
            @"category": @((NSInteger)d.category),
            @"confidence": @(d.confidence),
        }];
    }
    return @{
        @"isUnsafe": @(r.isUnsafe),
        @"detections": detections,
        @"nsfw": @((NSInteger)r.nsfw),
        @"nsfwSafe": @(r.nsfwSafe),
        @"nsfwSexy": @(r.nsfwSexy),
        @"nsfwExplicit": @(r.nsfwExplicit),
        @"rawWeapon": @(r.rawWeapon),
        @"rawDrug": @(r.rawDrug),
        @"rawCigarette": @(r.rawCigarette),
        @"rawAlcohol": @(r.rawAlcohol),
    };
}

+ (nullable NSString *)initializeWithLicenseKey:(NSString *)licenseKey
                                         models:(NSUInteger)models {
    NSError *error = nil;
    const BOOL ok = [NosmaiSDK initializeWithLicenseKey:licenseKey
                                                 models:(NosmaiModelOptions)models
                                                  error:&error];
    if (ok) return nil;
    return error.localizedDescription ?: @"initialization failed";
}

+ (BOOL)initializeText {
    return [NosmaiSDK initializeTextWithError:nil];
}

+ (NSDictionary<NSString *, id> *)analyzeImageAtPath:(NSString *)path {
    UIImage *image = [UIImage imageWithContentsOfFile:path];
    if (image == nil) return @{};
    NosmaiResult *r = [NosmaiSDK analyzeImage:image];
    if (r == nil) return @{};
    return [self dictFromResult:r];
}

+ (void)analyzeVideoAtPath:(NSString *)path
           frameIntervalMs:(int64_t)frameIntervalMs
                completion:(void (^)(NSDictionary<NSString *, id> *))completion {
    NSURL *url = [NSURL fileURLWithPath:path];
    [NosmaiSDK analyzeVideoURL:url
               frameIntervalMs:frameIntervalMs
                      progress:nil
                    completion:^(NosmaiVideoResult *r) {
        NSMutableArray *categories = [NSMutableArray array];
        for (NSNumber *c in r.categories) [categories addObject:c];
        NSMutableArray *flags = [NSMutableArray array];
        for (NosmaiVideoFlag *f in r.flags) {
            [flags addObject:@{
                @"timestampMs": @(f.timestampMs),
                @"category": @((NSInteger)f.category),
                @"confidence": @(f.confidence),
            }];
        }
        NSMutableArray *nsfwFlagged = [NSMutableArray array];
        for (NSNumber *t in r.nsfwFlaggedTimestampsMs) [nsfwFlagged addObject:t];
        completion(@{
            @"isUnsafe": @(r.isUnsafe),
            @"framesAnalyzed": @(r.framesAnalyzed),
            @"nsfw": @((NSInteger)r.nsfw),
            @"categories": categories,
            @"flags": flags,
            @"nsfwFlaggedMs": nsfwFlagged,
        });
    }];
}

+ (NSDictionary<NSString *, id> *)moderateText:(NSString *)message {
    NosmaiTextResult *r = [NosmaiSDK moderateText:message];
    if (r == nil) return @{};
    return @{
        @"blocked": @(r.blocked),
        @"layer": @((NSInteger)r.layer),
        @"category": @((NSInteger)r.category),
        @"score": @(r.score),
        @"matchedWord": r.matchedWord ?: @"",
    };
}

+ (void)setThreshold:(NSInteger)category value:(double)value {
    [NosmaiSDK setThreshold:(NosmaiCategory)category value:(float)value];
}

+ (void)setNsfwThreshold:(NSInteger)nsfwClass value:(double)value {
    [NosmaiSDK setNsfwThreshold:(NosmaiNsfwClass)nsfwClass value:(float)value];
}

+ (void)shutdown {
    [NosmaiSDK shutdown];
}

#pragma mark - Live stream

static NosmaiStreamListener *g_streamListener;

+ (void)startStreamWithResultHandler:(void (^)(NSDictionary<NSString *, id> *))handler {
    if (g_streamListener == nil) g_streamListener = [NosmaiStreamListener new];
    g_streamListener.handler = handler;
    [NosmaiSDK startStreamWithListener:g_streamListener];
}

+ (void)pushFrame:(CVPixelBufferRef)pixelBuffer rotation:(int)rotation {
    [NosmaiSDK pushFrame:pixelBuffer rotationDegrees:rotation];
}

+ (void)stopStream {
    [NosmaiSDK stopStream];
    if (g_streamListener != nil) g_streamListener.handler = nil;
}

@end

@implementation NosmaiStreamListener

- (void)nosmaiOnResult:(NosmaiResult *)result {
    void (^h)(NSDictionary<NSString *, id> *) = self.handler;
    if (h != nil) h([NosmaiBridge dictFromResult:result]);
}

// The Flutter API delivers EVERY frame's result via nosmaiOnResult (the Dart side
// derives safe/unsafe transitions from result.isUnsafe), so the edge callbacks are
// intentionally no-ops here. The native SDK still fires them for native consumers.
- (void)nosmaiOnUnsafe:(NosmaiResult *)result {
}

- (void)nosmaiOnSafe {
}

@end
