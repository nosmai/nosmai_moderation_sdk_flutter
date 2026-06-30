import AVFoundation
import Flutter
import UIKit

/// Platform-view factory for the live camera preview. Registered under the view
/// type "nosmai_moderation_sdk/preview" and embedded in Flutter via UiKitView.
final class NosmaiPreviewFactory: NSObject, FlutterPlatformViewFactory {
  func create(withFrame frame: CGRect,
              viewIdentifier viewId: Int64,
              arguments args: Any?) -> FlutterPlatformView {
    return NosmaiPreviewView(frame: frame)
  }
}

final class NosmaiPreviewView: NSObject, FlutterPlatformView {
  private let previewView: PreviewUIView

  init(frame: CGRect) {
    previewView = PreviewUIView(frame: frame)
    super.init()
    NosmaiCamera.shared.previewAttached()
    previewView.attach(session: NosmaiCamera.shared.session)
  }

  func view() -> UIView { previewView }

  deinit {
    // Defensive: when the LAST preview is disposed (user left the screen) without
    // an explicit NosmaiLive.stop(), stop the camera + stream so it never stays
    // running off-screen. Ref-counted, so navigating A->B (B attaches before A
    // disposes) keeps the camera alive for B.
    if NosmaiCamera.shared.previewDetached() {
      NosmaiBridge.stopStream()
    }
  }
}

/// A UIView whose backing layer IS the capture preview layer, so it resizes with
/// the view automatically.
private final class PreviewUIView: UIView {
  override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

  private var previewLayer: AVCaptureVideoPreviewLayer {
    layer as! AVCaptureVideoPreviewLayer
  }

  func attach(session: AVCaptureSession) {
    previewLayer.session = session
    previewLayer.videoGravity = .resizeAspectFill
    if let connection = previewLayer.connection, connection.isVideoOrientationSupported {
      connection.videoOrientation = .portrait
    }
  }
}
