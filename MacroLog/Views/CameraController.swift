import AVFoundation
import UIKit

/// Wraps an AVCaptureSession for the capture viewfinder. Configures on a
/// background queue so cold launch reaches a ready camera quickly (PERF-01).
@MainActor
final class CameraController: NSObject, ObservableObject {

    enum Status { case configuring, ready, denied, unavailable }

    @Published private(set) var status: Status = .configuring

    // Accessed from both the main actor (preview layer, capture trigger) and
    // sessionQueue (configuration, start/stop), per AVCaptureSession's
    // documented usage pattern — hence nonisolated(unsafe).
    nonisolated(unsafe) let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "macrolog.camera.session")
    private nonisolated(unsafe) let photoOutput = AVCapturePhotoOutput()
    private var captureContinuation: CheckedContinuation<UIImage?, Never>?

    func configureAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configure()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted { self.configure() } else { self.status = .denied }
                }
            }
        default:
            status = .denied
        }
    }

    private func configure() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.session.beginConfiguration()
            self.session.sessionPreset = .photo

            guard
                let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                let input = try? AVCaptureDeviceInput(device: device),
                self.session.canAddInput(input),
                self.session.canAddOutput(self.photoOutput)
            else {
                self.session.commitConfiguration()
                Task { @MainActor in self.status = .unavailable }
                return
            }

            self.session.addInput(input)
            self.session.addOutput(self.photoOutput)
            self.session.commitConfiguration()
            self.session.startRunning()
            Task { @MainActor in self.status = .ready }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self, self.session.isRunning else { return }
            self.session.stopRunning()
        }
    }

    /// Captures a photo and returns it upright-oriented, or nil on failure.
    func capturePhoto() async -> UIImage? {
        await withCheckedContinuation { continuation in
            self.captureContinuation = continuation
            let settings = AVCapturePhotoSettings()
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        let image = photo.fileDataRepresentation().flatMap(UIImage.init(data:))
        Task { @MainActor in
            self.captureContinuation?.resume(returning: image)
            self.captureContinuation = nil
        }
    }
}
