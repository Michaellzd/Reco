import Foundation
import AVFoundation
import CoreMedia

/// Handles microphone capture via AVCaptureSession.
/// System audio is handled by ScreenRecorder (via SCStream audio output) and routed
/// to a separate AVAssetWriter — this class manages the mic-only pipeline.
final class AudioRecorder: NSObject, @unchecked Sendable {

    // MARK: - Properties

    private var captureSession: AVCaptureSession?
    private var audioWriter: AVAssetWriter?
    private var audioWriterInput: AVAssetWriterInput?
    private let writerQueue = DispatchQueue(label: "com.reco.audioRecorder.writer", qos: .userInteractive)

    private var isRecording = false
    private var isPaused = false
    private var sessionStarted = false

    // Pause handling
    private var pauseStartTime: CMTime = .zero
    private var totalPauseDuration: CMTime = .zero

    // MARK: - Start

    func start(outputURL: URL) throws {
        guard let microphone = AVCaptureDevice.default(for: .audio) else {
            print("[AudioRecorder] No microphone device available, skipping mic capture")
            return
        }

        let session = AVCaptureSession()
        session.beginConfiguration()

        // Add mic input
        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: microphone)
        } catch {
            print("[AudioRecorder] Failed to create mic input: \(error.localizedDescription)")
            return
        }

        guard session.canAddInput(input) else {
            print("[AudioRecorder] Cannot add mic input to session")
            return
        }
        session.addInput(input)

        // Add audio data output
        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: writerQueue)

        guard session.canAddOutput(output) else {
            print("[AudioRecorder] Cannot add audio output to session")
            return
        }
        session.addOutput(output)

        session.commitConfiguration()

        // Setup asset writer for mic audio
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .caf)

        let audioSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128000
        ]

        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
        writerInput.expectsMediaDataInRealTime = true

        writer.add(writerInput)

        self.audioWriter = writer
        self.audioWriterInput = writerInput
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

        guard let writer = audioWriter, writer.status == .writing else { return }
        audioWriterInput?.markAsFinished()
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

// MARK: - AVCaptureAudioDataOutputSampleBufferDelegate

extension AudioRecorder: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard isRecording, !isPaused else { return }
        guard let writer = audioWriter, let writerInput = audioWriterInput else { return }

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
}

// MARK: - CMSampleBuffer Timestamp Adjustment (Audio)

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
