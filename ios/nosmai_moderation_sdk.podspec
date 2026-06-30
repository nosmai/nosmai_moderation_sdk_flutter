#
# To learn more about a Podspec see https://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint nosmai_moderation_sdk.podspec` to validate.
#
Pod::Spec.new do |s|
  s.name             = 'nosmai_moderation_sdk'
  s.version          = '1.0.0'
  s.summary          = 'On-device content + text moderation for Flutter.'
  s.description      = <<-DESC
On-device image NSFW + object detection (weapon/drug/cigarette/alcohol) and chat
toxicity, powered by the native Nosmai SDK. Fully offline.
                       DESC
  s.homepage         = 'https://github.com/nosmai/nosmai_moderation_sdk_flutter'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Nosmai' => 'support@nosmai.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.swift_version    = '5.0'
  s.platform         = :ios, '15.1'

  # The native SDK is a static-library framework; mark this plugin static too so
  # CocoaPods does not flag a dynamic-framework-depends-on-static-binary conflict
  # under the host app's use_frameworks!.
  s.static_framework = true

  s.dependency 'Flutter'
  # The native SDK ships as its own CocoaPods pod (xcframework + encrypted models
  # + privacy manifest + linking). This plugin carries only the Dart/Swift glue;
  # CocoaPods pulls the SDK automatically, so the host app does nothing extra.
  s.dependency 'NosmaiModerationSDK', '~> 1.0.1'

  # System frameworks the plugin's own camera / preview code uses (the SDK
  # declares the ones it needs itself).
  s.frameworks = 'AVFoundation', 'CoreVideo', 'CoreMedia'

  # The Obj-C bridge does `#import "NosmaiDetection/NosmaiSDK.h"`, so put the
  # NosmaiModerationSDK pod's xcframework headers (for the active slice) on the
  # search path. Linking and the model resources are provided by that pod.
  hdr = '$(PODS_ROOT)/NosmaiModerationSDK/NosmaiDetection.xcframework'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'x86_64',
    'HEADER_SEARCH_PATHS[sdk=iphoneos*]' => "\"#{hdr}/ios-arm64/Headers\"",
    'HEADER_SEARCH_PATHS[sdk=iphonesimulator*]' => "\"#{hdr}/ios-arm64-simulator/Headers\"",
  }

  # Privacy manifest for the plugin's own required-reason API use.
  s.resource_bundles = { 'nosmai_moderation_sdk_privacy' => ['Resources/PrivacyInfo.xcprivacy'] }
end
