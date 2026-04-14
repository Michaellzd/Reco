import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia

// MARK: - Errors

enum CaptureEngineError: LocalizedError {
    case permissionDenied(String)
    case configurationFailed(String)
    case noDisplayFound
    case notRecording
    case alreadyRecording

    var errorDescription: String? {
        switch self {
        case .permissionDenied(let msg): return "Permission denied: \(msg)"
        case .configurationFailed(let msg): return "Configuration failed: \(msg)"
        case .noDisplayFound: return "No display found matching the requested display ID"
        case .notRecording: return "Not currently recording"
        case .alreadyRecording: return "Already recording"
        }
    }
}

// MARK: - CaptureEngine

/// Main capture orchestrator. Conforms to CaptureEngineProtocol.
/// Coordinates screen, camera, audio, and cursor recording into separate track files
/// within a .reco project bundle directory.
@Observable
final class CaptureEngine: NSObject, CaptureEngineProtocol, @unchecked Sendable {

    // MARK: - CaptureEngineProtocol

    private(set) var state: CaptureState = .idle
    private(set) var elapsedTime: TimeInterval = 0

    // MARK: - Sub-recorders

    private var screenRecorder: ScreenRecorder?
    private var cameraRecorder: CameraRecorder?
    private var audioRecorder: AudioRecorder?
    private var cursorTracker: CursorTracker?

    // MARK: - State

    private var bundleURL: URL?
    private var recordingStartDate: Date?
    private var pauseAccumulated: TimeInterval = 0
    private var lastPauseDate: Date?
    private var elapsedTimer: Timer?

    // MARK: - Start Recording

    func startRecording(config: RecordingConfig, outputDirectory: URL) async throws {
        guard state == .idle else {
            throw CaptureEngineError.alreadyRecording
        }

        // 1. Create project bundle directory
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"
        let bundleName = "Recording-\(formatter.string(from: Date())).reco"
        let bundlePath = outputDirectory.appendingPathComponent(bundleName)

        try FileManager.default.createDirectory(at: bundlePath, withIntermediateDirectories: true)
        self.bundleURL = bundlePath

        // 2. Query SCShareableContent for available displays
        let availableContent = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        guard let display = availableContent.displays.first(where: { $0.displayID == config.displayID })
                ?? availableContent.displays.first else {
            throw CaptureEngineError.noDisplayFound
        }

        // 3. Start screen recorder (screen + system audio)
        let screenURL = bundlePath.appendingPathComponent("screen.mov")
        let systemAudioURL = config.systemAudioEnabled
            ? bundlePath.appendingPathComponent("audio-system.caf")
            : nil

        let screen = ScreenRecorder()
        self.screenRecorder = screen

        // 4. Start cursor tracker
        let cursorURL = bundlePath.appendingPathComponent("cursor.json")
        let tracker = CursorTracker()
        self.cursorTracker = tracker

        let startTime = CMClockGetTime(CMClockGetHostTimeClock())
        tracker.start(
            screenWidth: display.width,
            screenHeight: display.height,
            startTime: startTime,
            outputURL: cursorURL
        )

        // Wire cursor tracker to receive video frames from screen recorder
        screen.onVideoSampleBuffer = { [weak tracker] sampleBuffer in
            tracker?.processSampleBuffer(sampleBuffer)
        }

        try await screen.start(
            config: config,
            screenOutputURL: screenURL,
            systemAudioOutputURL: systemAudioURL,
            display: display
        )

        // 5. Start camera recorder (if enabled)
        if config.cameraEnabled {
            let cameraURL = bundlePath.appendingPathComponent("camera.mov")
            let camera = CameraRecorder()
            self.cameraRecorder = camera
            do {
                try camera.start(outputURL: cameraURL)
            } catch {
                print("[CaptureEngine] Camera failed to start: \(error.localizedDescription). Continuing without camera.")
                self.cameraRecorder = nil
            }
        }

        // 6. Start microphone recorder (if enabled)
        if config.micEnabled {
            let micURL = bundlePath.appendingPathComponent("audio-mic.caf")
            let mic = AudioRecorder()
            self.audioRecorder = mic
            do {
                try mic.start(outputURL: micURL)
            } catch {
                print("[CaptureEngine] Microphone failed to start: \(error.localizedDescription). Continuing without mic.")
                self.audioRecorder = nil
            }
        }

        // 7. Update state
        recordingStartDate = Date()
        pauseAccumulated = 0
        lastPauseDate = nil
        state = .recording
        startElapsedTimer()
    }

    // MARK: - Pause Recording

    func pauseRecording() {
        guard state == .recording else { return }

        screenRecorder?.pause()
        cameraRecorder?.pause()
        audioRecorder?.pause()

        lastPauseDate = Date()
        state = .paused
        stopElapsedTimer()
    }

    // MARK: - Resume Recording

    func resumeRecording() {
        guard state == .paused else { return }

        screenRecorder?.resume()
        cameraRecorder?.resume()
        audioRecorder?.resume()

        if let pauseDate = lastPauseDate {
            pauseAccumulated += Date().timeIntervalSince(pauseDate)
        }
        lastPauseDate = nil
        state = .recording
        startElapsedTimer()
    }

    // MARK: - Stop Recording

    func stopRecording() async throws -> URL {
        guard state == .recording || state == .paused else {
            throw CaptureEngineError.notRecording
        }

        guard let bundleURL = bundleURL else {
            throw CaptureEngineError.notRecording
        }

        stopElapsedTimer()

        // Stop all recorders
        if let screen = screenRecorder {
            try await screen.stop()
        }

        if let camera = cameraRecorder {
            await camera.stop()
        }

        if let mic = audioRecorder {
            await mic.stop()
        }

        cursorTracker?.stop()

        // Clean up
        resetState()

        return bundleURL
    }

    // MARK: - Discard Recording

    func discardRecording() {
        // Stop everything without finalizing
        Task {
            try? await screenRecorder?.stop()
            await cameraRecorder?.stop()
            await audioRecorder?.stop()
            cursorTracker?.stop()

            // Delete bundle directory
            if let bundleURL = bundleURL {
                try? FileManager.default.removeItem(at: bundleURL)
            }

            await MainActor.run {
                self.resetState()
            }
        }
    }

    // MARK: - Private Helpers

    private func resetState() {
        screenRecorder = nil
        cameraRecorder = nil
        audioRecorder = nil
        cursorTracker = nil
        bundleURL = nil
        recordingStartDate = nil
        pauseAccumulated = 0
        lastPauseDate = nil
        elapsedTime = 0
        state = .idle
    }

    private func startElapsedTimer() {
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self = self, let startDate = self.recordingStartDate else { return }
            self.elapsedTime = Date().timeIntervalSince(startDate) - self.pauseAccumulated
        }
    }

    private func stopElapsedTimer() {
        elapsedTimer?.invalidate()
        elapsedTimer = nil
    }
}
