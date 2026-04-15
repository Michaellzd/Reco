import Foundation
import CoreImage
import CoreMedia
import AVFoundation
import AppKit

/// Main compositor orchestrator that conforms to `CompositorProtocol`.
/// Reads a `.reco` project bundle and produces composited video with background,
/// cursor effects, camera overlay, and trimming applied.
final class Compositor: CompositorProtocol {

    // MARK: - Sub-renderers

    private let frameRenderer = FrameRenderer()
    private let cursorRenderer = CursorRenderer()
    private let cameraRenderer = CameraRenderer()

    // MARK: - CompositorProtocol

    /// Render a single composite frame at the given time for preview.
    /// Designed to be fast (< 100ms) for responsive scrubbing.
    func renderPreviewFrame(
        projectURL: URL,
        settings: EditSettings,
        at time: CMTime
    ) async throws -> CGImage {
        let screenURL = projectURL.appendingPathComponent("screen.mov")

        // Read a single frame from screen.mov
        let screenFrame = try await readSingleFrame(from: screenURL, at: time)
        let screenSize = screenFrame.extent.size

        // Determine output size (same as screen recording size)
        let outputSize = screenSize

        // Load cursor data if available
        let cursorURL = projectURL.appendingPathComponent("cursor.json")
        if FileManager.default.fileExists(atPath: cursorURL.path) {
            try? cursorRenderer.loadCursorData(from: cursorURL)
        }

        let screenRect = frameRenderer.screenRect(
            screenSize: screenSize,
            config: settings.background,
            outputSize: outputSize
        )

        // Render cursor overlay
        let timeSeconds = CMTimeGetSeconds(time)
        let cursorOverlay = cursorRenderer.renderCursor(
            at: timeSeconds,
            config: settings.cursor,
            recordingSize: screenSize,
            outputSize: outputSize,
            screenRect: screenRect
        )

        // Read camera frame if available
        let cameraURL = projectURL.appendingPathComponent("camera.mov")
        var cameraOverlay: CIImage?
        if !settings.camera.hidden,
           settings.camera.shape != .hidden,
           FileManager.default.fileExists(atPath: cameraURL.path) {
            if let cameraFrame = cameraRenderer.readFrame(at: time, from: cameraURL) {
                cameraOverlay = cameraRenderer.renderCameraOverlay(
                    cameraFrame: cameraFrame,
                    config: settings.camera,
                    outputSize: outputSize
                )
            }
        }

        // Composite all layers
        let composited = frameRenderer.renderFrame(
            screenFrame: screenFrame,
            cursorOverlay: cursorOverlay,
            cameraFrame: cameraOverlay,
            settings: settings,
            outputSize: outputSize
        )

        // Convert to CGImage
        guard let cgImage = frameRenderer.renderToCGImage(composited, size: outputSize) else {
            throw CompositorError.failedToRenderFrame
        }

        return cgImage
    }

    /// Export the full composited video.
    /// Reads all tracks frame-by-frame, applies trimming and compositing,
    /// mixes audio, and encodes to output format.
    func export(
        projectURL: URL,
        settings: EditSettings,
        outputURL: URL,
        format: ExportFormat,
        resolution: ExportResolution,
        progress: @escaping (Double) -> Void
    ) async throws {
        let screenURL = projectURL.appendingPathComponent("screen.mov")
        let cameraURL = projectURL.appendingPathComponent("camera.mov")
        let cursorURL = projectURL.appendingPathComponent("cursor.json")
        let micAudioURL = projectURL.appendingPathComponent("audio-mic.caf")
        let systemAudioURL = projectURL.appendingPathComponent("audio-system.caf")

        // Load cursor data
        if FileManager.default.fileExists(atPath: cursorURL.path) {
            try? cursorRenderer.loadCursorData(from: cursorURL)
        }

        // Set up screen asset reader
        let screenAsset = AVAsset(url: screenURL)
        let screenReader = try AVAssetReader(asset: screenAsset)

        guard let screenVideoTrack = screenAsset.tracks(withMediaType: .video).first else {
            throw CompositorError.noVideoTrack
        }

        let screenOutputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let screenOutput = AVAssetReaderTrackOutput(
            track: screenVideoTrack,
            outputSettings: screenOutputSettings
        )
        screenOutput.alwaysCopiesSampleData = false
        screenReader.add(screenOutput)

        // Get video properties
        let naturalSize = screenVideoTrack.naturalSize
        let exportConfiguration = makeExportConfiguration(
            format: format,
            resolution: resolution,
            sourceSize: naturalSize
        )
        let outputSize = exportConfiguration.outputSize
        let duration = screenAsset.duration
        let totalSeconds = CMTimeGetSeconds(duration)

        // Prepare camera reader if available
        let hasCameraFile = FileManager.default.fileExists(atPath: cameraURL.path)
        let cameraEnabled = !settings.camera.hidden && settings.camera.shape != .hidden && hasCameraFile
        if cameraEnabled {
            try? cameraRenderer.prepare(cameraURL: cameraURL)
        }

        // Build trim map for timestamp remapping
        let trimMap = TrimMap(
            trimRanges: settings.trimRanges,
            deletedSegments: settings.deletedSegments,
            totalDuration: totalSeconds
        )

        // Set up asset writer
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: exportConfiguration.fileType)

        var compressionProperties: [String: Any] = [
            AVVideoAverageBitRateKey: exportConfiguration.averageBitRate,
            AVVideoExpectedSourceFrameRateKey: settings.fps
        ]
        if let profileLevel = exportConfiguration.profileLevel {
            compressionProperties[AVVideoProfileLevelKey] = profileLevel
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: exportConfiguration.codec,
            AVVideoWidthKey: Int(outputSize.width),
            AVVideoHeightKey: Int(outputSize.height),
            AVVideoCompressionPropertiesKey: compressionProperties
        ]
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = false
        writer.add(videoInput)

        let pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: Int(outputSize.width),
                kCVPixelBufferHeightKey as String: Int(outputSize.height)
            ]
        )

        // Set up audio inputs
        let audioInputs = try setupAudioInputs(
            writer: writer,
            micURL: micAudioURL,
            systemURL: systemAudioURL
        )

        // Start reading and writing
        guard screenReader.startReading() else {
            throw CompositorError.readerFailed(screenReader.error)
        }

        guard writer.startWriting() else {
            throw CompositorError.writerFailed(writer.error)
        }

        writer.startSession(atSourceTime: .zero)

        let screenRect = frameRenderer.screenRect(
            screenSize: naturalSize,
            config: settings.background,
            outputSize: outputSize
        )

        // Process video frames
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let processingQueue = DispatchQueue(label: "com.reco.compositor.export")

            videoInput.requestMediaDataWhenReady(on: processingQueue) { [weak self] in
                guard let self = self else {
                    continuation.resume(throwing: CompositorError.cancelled)
                    return
                }

                while videoInput.isReadyForMoreMediaData {
                    // Check for cancellation
                    if Task.isCancelled {
                        screenReader.cancelReading()
                        writer.cancelWriting()
                        continuation.resume(throwing: CompositorError.cancelled)
                        return
                    }

                    guard let sampleBuffer = screenOutput.copyNextSampleBuffer() else {
                        // Done reading video
                        videoInput.markAsFinished()
                        continuation.resume()
                        return
                    }

                    let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                    let timeSeconds = CMTimeGetSeconds(pts)

                    // Check if this frame should be kept (trimming)
                    guard trimMap.shouldKeep(timestamp: timeSeconds) else {
                        continue
                    }

                    // Get the remapped output time
                    let remappedTime = trimMap.remappedTime(for: timeSeconds)
                    let outputPTS = CMTime(seconds: remappedTime, preferredTimescale: 600)

                    // Extract pixel buffer
                    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                        continue
                    }

                    let screenFrame = CIImage(cvPixelBuffer: pixelBuffer)

                    // Render cursor
                    let cursorOverlay = self.cursorRenderer.renderCursor(
                        at: timeSeconds,
                        config: settings.cursor,
                        recordingSize: naturalSize,
                        outputSize: outputSize,
                        screenRect: screenRect
                    )

                    // Read camera frame (sequential)
                    var cameraOverlay: CIImage?
                    if cameraEnabled {
                        if let (cameraFrame, _) = self.cameraRenderer.readNextFrame() {
                            cameraOverlay = self.cameraRenderer.renderCameraOverlay(
                                cameraFrame: cameraFrame,
                                config: settings.camera,
                                outputSize: outputSize
                            )
                        }
                    }

                    // Composite
                    let composited = self.frameRenderer.renderFrame(
                        screenFrame: screenFrame,
                        cursorOverlay: cursorOverlay,
                        cameraFrame: cameraOverlay,
                        settings: settings,
                        outputSize: outputSize
                    )

                    // Render to pixel buffer
                    guard let outputPixelBuffer = self.createPixelBuffer(
                        from: composited,
                        size: outputSize,
                        pool: pixelBufferAdaptor.pixelBufferPool
                    ) else {
                        continue
                    }

                    pixelBufferAdaptor.append(outputPixelBuffer, withPresentationTime: outputPTS)

                    // Report progress
                    let currentProgress = totalSeconds > 0 ? timeSeconds / totalSeconds : 0
                    progress(min(max(currentProgress, 0), 1.0))
                }
            }
        }

        // Process audio (after video is done)
        try await processAudio(
            audioInputs: audioInputs,
            trimMap: trimMap
        )

        for audioInput in audioInputs {
            audioInput.writerInput.markAsFinished()
        }

        try await finishWriting(writer)

        progress(1.0)

        // Cleanup
        cameraRenderer.reset()
    }

    // MARK: - Private Helpers

    /// Read a single video frame at the given time for preview.
    private func readSingleFrame(from url: URL, at time: CMTime) async throws -> CIImage {
        let asset = AVAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = CMTime(value: 1, timescale: 60)
        generator.requestedTimeToleranceAfter = CMTime(value: 1, timescale: 60)

        let safeTime = max(time, .zero)
        let (image, _) = try await generator.image(at: safeTime)
        return CIImage(cgImage: image)
    }

    /// Create a pixel buffer from a CIImage, using the pool if available.
    private func createPixelBuffer(
        from image: CIImage,
        size: CGSize,
        pool: CVPixelBufferPool?
    ) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?

        if let pool = pool {
            let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
            guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }
            frameRenderer.ciContext.render(
                image,
                to: buffer,
                bounds: CGRect(origin: .zero, size: size),
                colorSpace: CGColorSpaceCreateDeviceRGB()
            )
            return buffer
        }

        // Fallback: create standalone buffer
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(size.width),
            kCVPixelBufferHeightKey as String: Int(size.height)
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let buffer = pixelBuffer else { return nil }

        frameRenderer.ciContext.render(
            image,
            to: buffer,
            bounds: CGRect(origin: .zero, size: size),
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return buffer
    }

    private func finishWriting(_ writer: AVAssetWriter) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            writer.finishWriting {
                if let error = writer.error {
                    continuation.resume(throwing: CompositorError.writerFailed(error))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func makeExportConfiguration(
        format: ExportFormat,
        resolution: ExportResolution,
        sourceSize: CGSize
    ) -> ExportConfiguration {
        let outputSize = resolvedOutputSize(for: resolution, sourceSize: sourceSize)

        switch format {
        case .mp4:
            return ExportConfiguration(
                fileType: .mp4,
                codec: .h264,
                outputSize: outputSize,
                averageBitRate: Int(outputSize.width * outputSize.height) * 8,
                profileLevel: AVVideoProfileLevelH264HighAutoLevel
            )
        case .hevc:
            return ExportConfiguration(
                fileType: .mp4,
                codec: .hevc,
                outputSize: outputSize,
                averageBitRate: Int(outputSize.width * outputSize.height) * 6,
                profileLevel: nil
            )
        case .proRes:
            return ExportConfiguration(
                fileType: .mov,
                codec: .proRes422,
                outputSize: outputSize,
                averageBitRate: Int(outputSize.width * outputSize.height) * 12,
                profileLevel: nil
            )
        }
    }

    private func resolvedOutputSize(for resolution: ExportResolution, sourceSize: CGSize) -> CGSize {
        guard sourceSize.width > 0, sourceSize.height > 0 else {
            return CGSize(width: 1920, height: 1080)
        }

        if resolution == .original {
            return evenSize(sourceSize)
        }

        let targetBounds: CGSize = switch resolution {
        case .p720:
            CGSize(width: 1280, height: 720)
        case .p1080:
            CGSize(width: 1920, height: 1080)
        case .p4K:
            CGSize(width: 3840, height: 2160)
        case .original:
            sourceSize
        }

        let scale = min(
            targetBounds.width / sourceSize.width,
            targetBounds.height / sourceSize.height,
            1.0
        )
        return evenSize(CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale))
    }

    private func evenSize(_ size: CGSize) -> CGSize {
        let width = max(CGFloat(2), floor(size.width / 2) * 2)
        let height = max(CGFloat(2), floor(size.height / 2) * 2)
        return CGSize(width: width, height: height)
    }

    // MARK: - Audio

    /// Container for audio reader/writer pairs.
    private struct AudioTrackIO {
        let reader: AVAssetReader
        let output: AVAssetReaderTrackOutput
        let writerInput: AVAssetWriterInput
    }

    /// Set up audio readers and writer inputs for mic and system audio.
    private func setupAudioInputs(
        writer: AVAssetWriter,
        micURL: URL,
        systemURL: URL
    ) throws -> [AudioTrackIO] {
        var audioInputs: [AudioTrackIO] = []

        let audioOutputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false
        ]

        let writerAudioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2,
            AVEncoderBitRateKey: 128000
        ]

        for url in [micURL, systemURL] {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }

            let asset = AVAsset(url: url)
            guard let audioTrack = asset.tracks(withMediaType: .audio).first else { continue }

            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: audioOutputSettings)
            output.alwaysCopiesSampleData = false
            reader.add(output)

            let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: writerAudioSettings)
            writerInput.expectsMediaDataInRealTime = false

            if writer.canAdd(writerInput) {
                writer.add(writerInput)
                audioInputs.append(AudioTrackIO(reader: reader, output: output, writerInput: writerInput))
            }
        }

        return audioInputs
    }

    /// Process audio tracks, applying trim ranges.
    private func processAudio(
        audioInputs: [AudioTrackIO],
        trimMap: TrimMap
    ) async throws {
        for audioIO in audioInputs {
            guard audioIO.reader.startReading() else { continue }

            while let sampleBuffer = audioIO.output.copyNextSampleBuffer() {
                if Task.isCancelled { break }

                let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                let timeSeconds = CMTimeGetSeconds(pts)

                guard trimMap.shouldKeep(timestamp: timeSeconds) else { continue }
                let remappedTime = CMTime(
                    seconds: trimMap.remappedTime(for: timeSeconds),
                    preferredTimescale: 600
                )

                // Wait for writer input to be ready
                while !audioIO.writerInput.isReadyForMoreMediaData {
                    try await Task.sleep(nanoseconds: 10_000_000) // 10ms
                }

                if let adjusted = sampleBuffer.adjustingTimestamp(to: remappedTime) {
                    audioIO.writerInput.append(adjusted)
                }
            }
        }
    }
}

// MARK: - Trim Map

/// Handles trim logic: determines which timestamps to keep and remaps output timestamps
/// to be continuous (no gaps from deleted segments).
struct TrimMap {
    let keepRanges: [TrimRange]
    let totalDuration: Double

    init(trimRanges: [TrimRange], deletedSegments: [TrimRange], totalDuration: Double) {
        self.totalDuration = totalDuration

        if !trimRanges.isEmpty {
            // trimRanges defines segments to KEEP
            self.keepRanges = trimRanges.sorted { $0.startTime < $1.startTime }
        } else if !deletedSegments.isEmpty {
            // Invert deleted segments to get keep ranges
            self.keepRanges = TrimMap.invertSegments(
                deleted: deletedSegments.sorted { $0.startTime < $1.startTime },
                totalDuration: totalDuration
            )
        } else {
            // Keep everything
            self.keepRanges = [TrimRange(startTime: 0, endTime: totalDuration)]
        }
    }

    /// Check if a timestamp falls within a kept range.
    func shouldKeep(timestamp: Double) -> Bool {
        if keepRanges.isEmpty { return true }
        // If keepRanges covers everything (single range 0..totalDuration), skip check
        if keepRanges.count == 1,
           keepRanges[0].startTime <= 0,
           keepRanges[0].endTime >= totalDuration {
            return true
        }
        return keepRanges.contains { timestamp >= $0.startTime && timestamp <= $0.endTime }
    }

    /// Remap a source timestamp to a continuous output timestamp (removing gaps).
    func remappedTime(for timestamp: Double) -> Double {
        var accumulated: Double = 0
        for range in keepRanges {
            if timestamp < range.startTime {
                return accumulated
            }
            if timestamp <= range.endTime {
                return accumulated + (timestamp - range.startTime)
            }
            accumulated += (range.endTime - range.startTime)
        }
        return accumulated
    }

    /// Invert deleted segments to produce keep ranges.
    private static func invertSegments(deleted: [TrimRange], totalDuration: Double) -> [TrimRange] {
        var keeps: [TrimRange] = []
        var currentStart: Double = 0

        for segment in deleted {
            if segment.startTime > currentStart {
                keeps.append(TrimRange(startTime: currentStart, endTime: segment.startTime))
            }
            currentStart = segment.endTime
        }

        if currentStart < totalDuration {
            keeps.append(TrimRange(startTime: currentStart, endTime: totalDuration))
        }

        return keeps
    }
}

// MARK: - Errors

enum CompositorError: Error, LocalizedError {
    case noVideoTrack
    case failedToReadFrame
    case failedToRenderFrame
    case readerFailed(Error?)
    case writerFailed(Error?)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "Screen recording file contains no video track."
        case .failedToReadFrame:
            return "Failed to read a video frame from the screen recording."
        case .failedToRenderFrame:
            return "Failed to render the composited frame to a CGImage."
        case .readerFailed(let error):
            return "Asset reader failed: \(error?.localizedDescription ?? "unknown")"
        case .writerFailed(let error):
            return "Asset writer failed: \(error?.localizedDescription ?? "unknown")"
        case .cancelled:
            return "Export was cancelled."
        }
    }
}

private struct ExportConfiguration {
    let fileType: AVFileType
    let codec: AVVideoCodecType
    let outputSize: CGSize
    let averageBitRate: Int
    let profileLevel: String?
}

// MARK: - CMTime Helpers

private func max(_ a: CMTime, _ b: CMTime) -> CMTime {
    return CMTimeCompare(a, b) >= 0 ? a : b
}

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
