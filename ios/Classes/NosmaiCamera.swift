import AVFoundation
import Foundation
import UIKit

/// Owns the camera session for live moderation. Runs an AVCaptureSession and
/// forwards every frame to the native SDK via NosmaiBridge.pushFrame. The session
/// is shared with the preview platform view, so detection and preview stay native.
///
/// Lifecycle-correct: checks camera permission, stops on app background (so the
/// camera is never left running off-screen), recovers from runtime errors, and
/// reports failures to Dart instead of showing a silent black preview.
final class NosmaiCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {

  static let shared = NosmaiCamera()

  let session = AVCaptureSession()

  private let videoOutput = AVCaptureVideoDataOutput()
  private let sessionQueue = DispatchQueue(label: "nosmai.camera.session")
  private let videoQueue = DispatchQueue(label: "nosmai.camera.video")
  private var currentInput: AVCaptureDeviceInput?
  private var lensPosition: AVCaptureDevice.Position = .back
  private var running = false           // user intent (start requested, not yet stopped)
  private var streaming = false         // frames should be pushed
  private var onError: ((String) -> Void)?
  private var observersAdded = false
  private var previewCount = 0          // live preview views (main-thread confined)

  // MARK: - Preview ref-counting

  /// Called when a preview platform view is created.
  func previewAttached() { previewCount += 1 }

  /// Called when a preview platform view is disposed. Returns true if it was the
  /// LAST preview (the caller should then stop the stream) — so navigating A->B
  /// (B attaches before A disposes) never tears down the still-visible camera.
  func previewDetached() -> Bool {
    previewCount = max(0, previewCount - 1)
    if previewCount == 0 {
      stop()
      return true
    }
    return false
  }

  // MARK: - Public control

  /// Starts the camera for [position], invoking [onError] (on main) if permission
  /// is missing or no usable camera can be configured. Idempotent.
  func start(position: AVCaptureDevice.Position, onError: @escaping (String) -> Void) {
    self.onError = onError
    self.lensPosition = position
    running = true
    addObserversIfNeeded()

    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized:
      configureAndRun()
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
        guard let self = self else { return }
        if granted {
          self.configureAndRun()
        } else {
          self.reportError("Camera permission denied")
        }
      }
    case .denied, .restricted:
      reportError("Camera access is denied. Enable it in Settings to use the live camera.")
    @unknown default:
      reportError("Camera unavailable")
    }
  }

  func stop() {
    running = false
    streaming = false
    onError = nil
    sessionQueue.async { [session] in
      if session.isRunning { session.stopRunning() }
    }
  }

  // MARK: - Configuration

  private func configureAndRun() {
    sessionQueue.async { [weak self] in
      guard let self = self, self.running else { return }
      if !self.configureInput(for: self.lensPosition) {
        self.reportError("No \(self.lensPosition == .front ? "front" : "back") camera available")
        return
      }
      if !self.session.isRunning { self.session.startRunning() }
      self.streaming = true
    }
  }

  /// (Re)configures the session for the given lens. Returns false if no camera /
  /// input could be added. Runs on the session queue.
  private func configureInput(for position: AVCaptureDevice.Position) -> Bool {
    session.beginConfiguration()
    defer { session.commitConfiguration() }

    session.sessionPreset = .hd1280x720

    // Swap the input if the requested lens changed.
    if let existing = currentInput {
      session.removeInput(existing)
      currentInput = nil
    }
    guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
        ?? AVCaptureDevice.default(for: .video),
      let input = try? AVCaptureDeviceInput(device: camera),
      session.canAddInput(input)
    else {
      return false
    }
    session.addInput(input)
    currentInput = input

    // Output is added once.
    if session.outputs.isEmpty {
      videoOutput.alwaysDiscardsLateVideoFrames = true
      videoOutput.videoSettings = [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
      ]
      videoOutput.setSampleBufferDelegate(self, queue: videoQueue)
      if session.canAddOutput(videoOutput) {
        session.addOutput(videoOutput)
      }
    }
    return true
  }

  // MARK: - App-background + runtime-error handling

  private func addObserversIfNeeded() {
    guard !observersAdded else { return }
    observersAdded = true
    let nc = NotificationCenter.default
    nc.addObserver(self, selector: #selector(appDidBackground),
                   name: UIApplication.didEnterBackgroundNotification, object: nil)
    nc.addObserver(self, selector: #selector(appWillForeground),
                   name: UIApplication.willEnterForegroundNotification, object: nil)
    nc.addObserver(self, selector: #selector(sessionRuntimeError(_:)),
                   name: .AVCaptureSessionRuntimeError, object: session)
  }

  @objc private func appDidBackground() {
    // Never keep the camera running off-screen.
    streaming = false
    sessionQueue.async { [session] in
      if session.isRunning { session.stopRunning() }
    }
  }

  @objc private func appWillForeground() {
    guard running else { return }
    sessionQueue.async { [weak self] in
      guard let self = self, self.running else { return }
      if !self.session.isRunning { self.session.startRunning() }
      self.streaming = true
    }
  }

  @objc private func sessionRuntimeError(_ note: Notification) {
    // A runtime error is usually transient (interrupted by a call, another app
    // grabbed the camera, thermal). Log + auto-recover; do NOT report it to Dart,
    // because an EventChannel error would permanently terminate the results
    // stream. Only the genuinely terminal cases (permission denied, no camera)
    // call reportError.
    let err = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
    NSLog("[nosmai] capture session runtime error: %@", err?.localizedDescription ?? "unknown")
    if running {
      sessionQueue.async { [weak self] in
        guard let self = self, self.running else { return }
        if !self.session.isRunning { self.session.startRunning() }
      }
    }
  }

  private func reportError(_ message: String) {
    let cb = onError
    DispatchQueue.main.async { cb?(message) }
  }

  // MARK: - Frame delivery

  func captureOutput(_ output: AVCaptureOutput,
                     didOutput sampleBuffer: CMSampleBuffer,
                     from connection: AVCaptureConnection) {
    guard streaming, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    // The front camera is mirrored; both lenses deliver sensor-native buffers, so
    // 90deg makes them upright for the detector (matches the native demo).
    NosmaiBridge.pushFrame(pixelBuffer, rotation: 90)
  }
}
