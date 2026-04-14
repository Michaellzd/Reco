import Foundation
import AVFoundation
import CoreMedia

/// Wraps AVCaptureSession for webcam capture, writing to camera.mov via AVAssetWriter.
/// Handles camera not available gracefully (no crash).
final class CameraRecorder: NSObject, @unchecked Sendable {

    // MARK: - Properties

    private var captureSession: AVCaptureSession?
    private var videoWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private let writerQueue = DispatchQueue(label: "com.reco.cameraRecorder.writer", qos: .userInteractive)

    private var isRecording = false
    private var isPaused = false
    private var sessionStarted = false

    // Pause handling
    private var pauseStartTime: CMTime = .zero
    private var totalPauseDuration: CMTime = .zero

    // MARK: - Start

    func start(outputURL: URL) throws {
        guard let camera = AVCaptureDevice.default(for: .video) else {
            print("[CameraRecorder] No camera device available, skipping camera capture")
            return
        }

        let session = AVCaptureSession()
        session.beginConfiguration()
        session.sessionPreset = .high

        // Add camera input
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: camera)
        } catch {
            print("[CameraRecorder] Failed to create camera input: \(error.localizedDescription)")
            return
        }

        guard session.canAddInput(input) else {
            print("[CameraRecorder] Cannot add camera input to session")
            return
        }
        session.addInput(input)

        // Add video data output
        let output = AVCaptureVideoDataOutput()
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.setSampleBufferDelegate(self, queue: writerQueue)
        output.alwaysDiscardsLateVideoFrames = true

        guard session.canAddOutput(output) else {
            print("[CameraRecorder] Cannot add video output to session")
            return
        }
        session.addOutput(output)

        session.commitConfiguration()

        // Setup asset writer
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mov)

        // Get dimensions from the camera's active format
        let dimensions = CMVideoFormatDescriptionGetDimensions(camera.activeFormat.formatDescription)
        let width = Int(dimensions.width)
        let height = Int(dimensions.height)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: width * height * 4,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ]

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = true

        writer.add(writerInput)

        self.videoWriter = writer
        self.videoWriterInput = writerInput
        self.captureSession = session
        self.isRecording = true
        self.isPaused = false
        self.sessionStarted = false
        self.totalPauseDuration = .zero

        session.startRunning()
    }

    // MARK: - Pause / Resume

    func pause() {
        writerQueue.sync {
            self.isPaused = true
            self.pauseStartTime = CMClockGetTime(CMClockGetHostTimeClock())
        }
    }

    func resume() {
        writerQueue.sync {
            let now = CMClockGetTime(CMClockGetHostTimeClock())
            let pauseDuration = CMTimeSubtract(now, self.pauseStartTime)
            self.totalPauseDuration = CMTimeAdd(self.totalPauseDuration, pauseDuration)
            self.isPaused = false
        }
    }

    // MARK: - Stop

    func stop() async {
        isRecording = false

        captureSession?.stopRunning()
        captureSession = nil

        guard let writer = videoWriter, writer.status == .writing else { return }
        videoWriterInput?.markAsFinished()
        await withCheckedContinuation { continuation in
            writer.finishWriting {
                continuation.resume()
            }
        }
    }

    // MARK: - Timestamp Adjustment

    private func adjustTimestamp(_ timestamp: CMTime) -> CMTime {
        return CMTimeSubtract(timestamp, totalPauseDuration)
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension CameraRecorder: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isRecording, !isPaused else { return }
        guard let writer = videoWriter, let writerInput = videoWriterInput else { return }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let adjustedPTS = adjustTimestamp(pts)

        if !sessionStarted {
            writer.startWriting()
            writer.startSession(atSourceTime: adjustedPTS)
            sessionStarted = true
        }

        if writerInput.isReadyForMoreMediaData {
            if let adjusted = sampleBuffer.adjustingTimestamp(to: adjustedPTS) {
                writerInput.append(adjusted)
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didDrop sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        print("[CameraRecorder] Dropped frame")
    }
}

// MARK: - CMSampleBuffer Timestamp Adjustment (Camera)

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
