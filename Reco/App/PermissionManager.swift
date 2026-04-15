import Foundation
import AVFoundation
import ScreenCaptureKit
import CoreGraphics
import AppKit

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
    var screenPermissionNeedsRestartHint: Bool = false

    var allRequiredGranted: Bool {
        screenRecordingStatus == .granted
    }

    // MARK: - Check All

    func checkAllPermissions(forceScreenProbe: Bool = false) async {
        await checkScreenRecordingPermission(forceProbe: forceScreenProbe)
        await checkCameraPermission()
        await checkMicrophonePermission()
    }

    // MARK: - Screen Recording

    /// Checks screen recording permission by attempting to fetch shareable content.
    /// ScreenCaptureKit will prompt the user if not yet determined.
    func checkScreenRecordingPermission(forceProbe: Bool = false) async {
        let preflightGranted = await MainActor.run {
            CGPreflightScreenCaptureAccess()
        }

        if preflightGranted {
            await updateScreenRecordingStatus(granted: true, clearRestartHint: true)
            return
        }

        let shouldProbe = await MainActor.run {
            forceProbe || screenPermissionNeedsRestartHint
        }

        if shouldProbe {
            do {
                _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                await updateScreenRecordingStatus(granted: true, clearRestartHint: true)
                return
            } catch {
                // Fall through to denied state. On newer macOS versions this can still
                // require a relaunch even after the toggle is enabled in System Settings.
            }
        }

        await updateScreenRecordingStatus(granted: false, clearRestartHint: false)
    }

    /// Request screen recording permission using the system prompt.
    func requestScreenRecordingPermission() async {
        let granted = await MainActor.run {
            CGRequestScreenCaptureAccess()
        }
        await updateScreenRecordingStatus(granted: granted, clearRestartHint: granted)
    }

    func markScreenSettingsOpened() {
        screenPermissionNeedsRestartHint = true
    }

    func relaunchApp() {
        let bundleURL = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, _ in
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
        }
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
        markScreenSettingsOpened()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    @MainActor
    private func updateScreenRecordingStatus(granted: Bool, clearRestartHint: Bool) {
        screenRecordingStatus = granted ? .granted : .denied
        if clearRestartHint {
            screenPermissionNeedsRestartHint = false
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
