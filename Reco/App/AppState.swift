import Foundation
import SwiftUI

// MARK: - App Phase

enum AppPhase: Equatable {
    case setup
    case recording
    case editing(projectURL: URL)

    static func == (lhs: AppPhase, rhs: AppPhase) -> Bool {
        switch (lhs, rhs) {
        case (.setup, .setup): return true
        case (.recording, .recording): return true
        case (.editing(let a), .editing(let b)): return a == b
        default: return false
        }
    }
}

// MARK: - App State

@Observable
final class AppState {
    var phase: AppPhase = .setup
    var recordingConfig: RecordingConfig = .init()

    // Recording state
    var isRecording: Bool = false
    var isPaused: Bool = false
    var elapsedTime: TimeInterval = 0

    // Engine
    private let engine: CaptureEngineProtocol
    private var timerTask: Task<Void, Never>?

    /// Window ID of the recording panel, to be excluded from screen capture.
    var excludedWindowID: CGWindowID?

    init(engine: CaptureEngineProtocol = CaptureEngine()) {
        self.engine = engine
    }

    // MARK: - Recording Controls

    func startRecording() async throws {
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Reco", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        // Pass excluded window ID to the engine's screen recorder
        if let windowID = excludedWindowID, let captureEngine = engine as? CaptureEngine {
            captureEngine.addExcludedWindow(windowID)
        }

        try await engine.startRecording(config: recordingConfig, outputDirectory: outputDir)
        isRecording = true
        isPaused = false
        elapsedTime = 0
        phase = .recording
        startPollingElapsed()
    }

    func pauseRecording() {
        engine.pauseRecording()
        isPaused = true
        stopPollingElapsed()
    }

    func resumeRecording() {
        engine.resumeRecording()
        isPaused = false
        startPollingElapsed()
    }

    func stopRecording() async throws {
        stopPollingElapsed()
        let url = try await engine.stopRecording()
        isRecording = false
        isPaused = false
        phase = .editing(projectURL: url)
    }

    func discardRecording() {
        stopPollingElapsed()
        engine.discardRecording()
        isRecording = false
        isPaused = false
        elapsedTime = 0
        phase = .setup
    }

    /// Return to setup phase from editor (new recording)
    func newRecording() {
        phase = .setup
    }

    // MARK: - Elapsed Time Polling

    private func startPollingElapsed() {
        timerTask?.cancel()
        timerTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.elapsedTime = self.engine.elapsedTime
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func stopPollingElapsed() {
        timerTask?.cancel()
        timerTask = nil
    }
}
