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

// MARK: - Mock Capture Engine

/// A mock capture engine for development and testing.
/// Conforms to CaptureEngineProtocol without requiring the real capture pipeline.
final class MockCaptureEngine: CaptureEngineProtocol {
    private(set) var state: CaptureState = .idle
    private(set) var elapsedTime: TimeInterval = 0

    private var timer: Timer?
    private var recordingStartDate: Date?
    private var accumulatedTime: TimeInterval = 0
    private var bundleURL: URL?

    func startRecording(config: RecordingConfig, outputDirectory: URL) async throws {
        let bundleName = "recording-\(UUID().uuidString).reco"
        let url = outputDirectory.appendingPathComponent(bundleName)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        bundleURL = url
        state = .recording
        accumulatedTime = 0
        elapsedTime = 0
        recordingStartDate = Date()

        startTimer()
    }

    func pauseRecording() {
        guard state == .recording else { return }
        accumulatedTime += Date().timeIntervalSince(recordingStartDate ?? Date())
        recordingStartDate = nil
        state = .paused
        stopTimer()
    }

    func resumeRecording() {
        guard state == .paused else { return }
        recordingStartDate = Date()
        state = .recording
        startTimer()
    }

    func stopRecording() async throws -> URL {
        guard let url = bundleURL else {
            throw MockCaptureError.noActiveRecording
        }
        if state == .recording {
            accumulatedTime += Date().timeIntervalSince(recordingStartDate ?? Date())
        }
        stopTimer()
        state = .idle
        elapsedTime = accumulatedTime
        return url
    }

    func discardRecording() {
        stopTimer()
        if let url = bundleURL {
            try? FileManager.default.removeItem(at: url)
        }
        bundleURL = nil
        state = .idle
        elapsedTime = 0
        accumulatedTime = 0
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, let start = self.recordingStartDate else { return }
            self.elapsedTime = self.accumulatedTime + Date().timeIntervalSince(start)
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    enum MockCaptureError: Error {
        case noActiveRecording
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

    init(engine: CaptureEngineProtocol = MockCaptureEngine()) {
        self.engine = engine
    }

    // MARK: - Recording Controls

    func startRecording() async throws {
        let outputDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("Reco", isDirectory: true)
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

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
