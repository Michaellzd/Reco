import Foundation
import CoreMedia

enum CaptureState {
    case idle
    case recording
    case paused
}

protocol CaptureEngineProtocol: AnyObject {
    var state: CaptureState { get }
    var elapsedTime: TimeInterval { get }

    func startRecording(config: RecordingConfig, outputDirectory: URL) async throws
    func pauseRecording()
    func resumeRecording()
    func stopRecording() async throws -> URL  // Returns .reco bundle URL
    func discardRecording()
}
