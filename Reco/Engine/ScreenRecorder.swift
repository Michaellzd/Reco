import Foundation
import ScreenCaptureKit
import AVFoundation
import CoreMedia

/// Wraps SCStream setup and delegate handling for screen video + system audio capture.
/// Implements SCStreamOutput to receive video and audio sample buffers.
final class ScreenRecorder: NSObject, @unchecked Sendable {

    // MARK: - Properties

    private var stream: SCStream?
    private var filter: SCContentFilter?

    // Video writer
    private var videoWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private let videoWriterQueue = DispatchQueue(label: "com.reco.screenRecorder.videoWriter", qos: .userInteractive)

    // System audio writer
    private var audioWriter: AVAssetWriter?
    private var audioWriterInput: AVAssetWriterInput?
    private let audioWriterQueue = DispatchQueue(label: "com.reco.screenRecorder.audioWriter", qos: .userInteractive)

    // State
    private var isRecording = false
    private var isPaused = false
    private var videoSessionStarted = false
    private var audioSessionStarted = false

    // Pause handling
    private var pauseStartTime: CMTime = .zero
    private var totalPauseDuration: CMTime = .zero

    // Excluded windows
    private var excludedWindowIDs: [CGWindowID] = []

    // Callbacks
    var onVideoSampleBuffer: ((CMSampleBuffer) -> Void)?

    // MARK: - Configuration

    func addExcludedWindow(_ windowID: CGWindowID) {
        excludedWindowIDs.append(windowID)
    }

    // MARK: - Start

    func start(
        config: RecordingConfig,
        screenOutputURL: URL,
        systemAudioOutputURL: URL?,
        display: SCDisplay
    ) async throws {
        // Build content filter
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        // Find windows to exclude
        let excludedWindows = content.windows.filter { window in
            excludedWindowIDs.contains(window.windowID)
        }

        filter = SCContentFilter(display: display, excludingWindows: excludedWindows)

        guard let filter = filter else {
            throw CaptureEngineError.configurationFailed("Failed to create content filter")
        }

        // Configure stream
        let streamConfig = SCStreamConfiguration()

        // Set resolution
        switch config.resolution {
        case .original:
            streamConfig.width = display.width
            streamConfig.height = display.height
        case .p2160:
            streamConfig.width = 3840
            streamConfig.height = 2160
        case .p1080:
            streamConfig.width = 1920
            streamConfig.height = 1080
        case .p720:
            streamConfig.width = 1280
            streamConfig.height = 720
        }

        // Handle custom capture area
        if case .custom(let rect) = config.captureArea {
            streamConfig.sourceRect = rect
        }

        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        streamConfig.showsCursor = false // We track cursor separately
        streamConfig.pixelFormat = kCVPixelFormatType_32BGRA

        // Enable audio capture for system audio
        if config.systemAudioEnabled {
            streamConfig.capturesAudio = true
            streamConfig.sampleRate = 48000
            streamConfig.channelCount = 2
        }

        // Setup video asset writer
        try setupVideoWriter(outputURL: screenOutputURL, width: streamConfig.width, height: streamConfig.height)

        // Setup system audio writer if needed
        if config.systemAudioEnabled, let audioURL = systemAudioOutputURL {
            try setupAudioWriter(outputURL: audioURL)
        }

        // Create and start stream
        let scStream = SCStream(filter: filter, configuration: streamConfig, delegate: self)
        try scStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoWriterQueue)
        if config.systemAudioEnabled {
            try scStream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioWriterQueue)
        }

        self.stream = scStream
        self.isRecording = true
        self.isPaused = false
        self.videoSessionStarted = false
        self.audioSessionStarted = false
        self.totalPauseDuration = .zero

        try await scStream.startCapture()
    }

    // MARK: - Pause / Resume

    func pause() {
        videoWriterQueue.sync {
            self.isPaused = true
            self.pauseStartTime = CMClockGetTime(CMClockGetHostTimeClock())
        }
    }

    func resume() {
        videoWriterQueue.sync {
            let now = CMClockGetTime(CMClockGetHostTimeClock())
            let pauseDuration = CMTimeSubtract(now, self.pauseStartTime)
            self.totalPauseDuration = CMTimeAdd(self.totalPauseDuration, pauseDuration)
            self.isPaused = false
        }
    }

    // MARK: - Stop

    func stop() async throws {
        isRecording = false

        if let stream = stream {
            try await stream.stopCapture()
            self.stream = nil
        }

        // Finalize video writer
        try await finalizeWriter(videoWriterInput, writer: videoWriter, queue: videoWriterQueue)

        // Finalize audio writer
        try await finalizeWriter(audioWriterInput, writer: audioWriter, queue: audioWriterQueue)
    }

    // MARK: - Private Setup

    private func setupVideoWriter(outputURL: URL, width: Int, height: Int) throws {
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: width * height * 6,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: 60
            ]
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        input.expectsMediaDataInRealTime = true

        writer.add(input)
        self.videoWriter = writer
        self.videoWriterInput = input
    }

    private func setupAudioWriter(outputURL: URL) throws {
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .caf)

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128000
        ]

        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        input.expectsMediaDataInRealTime = true

        writer.add(input)
        self.audioWriter = writer
        self.audioWriterInput = input
    }

    private func finalizeWriter(_ input: AVAssetWriterInput?, writer: AVAssetWriter?, queue: DispatchQueue) async throws {
        guard let writer = writer, writer.status == .writing else { return }
        input?.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }
    }

    private func adjustTimestamp(_ timestamp: CMTime) -> CMTime {
        return CMTimeSubtract(timestamp, totalPauseDuration)
    }
}

// MARK: - SCStreamOutput

extension ScreenRecorder: SCStreamOutput {
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard isRecording, !isPaused else { return }

        switch type {
        case .screen:
            handleVideoSampleBuffer(sampleBuffer)
        case .audio:
            handleAudioSampleBuffer(sampleBuffer)
        @unknown default:
            break
        }
    }

    private func handleVideoSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let videoWriter = videoWriter,
              let videoWriterInput = videoWriterInput else { return }

        // Notify cursor tracker
        onVideoSampleBuffer?(sampleBuffer)

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let adjustedPTS = adjustTimestamp(pts)

        if !videoSessionStarted {
            videoWriter.startWriting()
            videoWriter.startSession(atSourceTime: adjustedPTS)
            videoSessionStarted = true
        }

        if videoWriterInput.isReadyForMoreMediaData {
            // Create adjusted sample buffer
            if let adjusted = sampleBuffer.adjustingTimestamp(to: adjustedPTS) {
                videoWriterInput.append(adjusted)
            }
        }
    }

    private func handleAudioSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let audioWriter = audioWriter,
              let audioWriterInput = audioWriterInput else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let adjustedPTS = adjustTimestamp(pts)

        if !audioSessionStarted {
            audioWriter.startWriting()
            audioWriter.startSession(atSourceTime: adjustedPTS)
            audioSessionStarted = true
        }

        if audioWriterInput.isReadyForMoreMediaData {
            if let adjusted = sampleBuffer.adjustingTimestamp(to: adjustedPTS) {
                audioWriterInput.append(adjusted)
            }
        }
    }
}

// MARK: - SCStreamDelegate

extension ScreenRecorder: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        print("[ScreenRecorder] Stream stopped with error: \(error.localizedDescription)")
        isRecording = false
    }
}

// MARK: - CMSampleBuffer Timestamp Adjustment

private extension CMSampleBuffer {
    func adjustingTimestamp(to newPTS: CMTime) -> CMSampleBuffer? {
        var timingInfo = CMSampleTimingInfo(
            duration: CMSampleBufferGetDuration(self),
            presentationTimeStamp: newPTS,
            decodeTimeStamp: .invalid
        )
        var newBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateCopyWithNewTiming(
            allocator: kCFAllocatorDefault,
            sampleBuffer: self,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timingInfo,
            sampleBufferOut: &newBuffer
        )
        guard status == noErr else { return nil }
        return newBuffer
    }
}
