import Foundation
import AVFoundation
import ScreenCaptureKit

// MARK: - Permission Status

enum PermissionStatus: String {
    case unknown
    case granted
    case denied
    case restricted
}

// MARK: - Permission Manager

@Observable
final class PermissionManager {
    var screenRecordingStatus: PermissionStatus = .unknown
    var cameraStatus: PermissionStatus = .unknown
    var microphoneStatus: PermissionStatus = .unknown

    var allRequiredGranted: Bool {
        screenRecordingStatus == .granted
    }

    // MARK: - Check All

    func checkAllPermissions() async {
        await checkScreenRecordingPermission()
        await checkCameraPermission()
        await checkMicrophonePermission()
    }

    // MARK: - Screen Recording

    /// Checks screen recording permission by attempting to fetch shareable content.
    /// ScreenCaptureKit will prompt the user if not yet determined.
    func checkScreenRecordingPermission() async {
        do {
            _ = try await SCShareableContent.current
            screenRecordingStatus = .granted
        } catch {
            screenRecordingStatus = .denied
        }
    }

    /// Request screen recording permission. On macOS, simply attempting to use
    /// SCShareableContent triggers the system prompt.
    func requestScreenRecordingPermission() async {
        await checkScreenRecordingPermission()
    }

    // MARK: - Camera

    func checkCameraPermission() async {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        await MainActor.run {
            cameraStatus = mapAVStatus(status)
        }
    }

    func requestCameraPermission() async {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        await MainActor.run {
            cameraStatus = granted ? .granted : .denied
        }
    }

    // MARK: - Microphone

    func checkMicrophonePermission() async {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        await MainActor.run {
            microphoneStatus = mapAVStatus(status)
        }
    }

    func requestMicrophonePermission() async {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        await MainActor.run {
            microphoneStatus = granted ? .granted : .denied
        }
    }

    // MARK: - Helpers

    private func mapAVStatus(_ status: AVAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorized: return .granted
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .unknown
        @unknown default: return .unknown
        }
    }

    /// Opens System Settings to the relevant privacy pane.
    func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    func openCameraSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
            NSWorkspace.shared.open(url)
        }
    }

    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}
