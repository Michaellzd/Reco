import Foundation
import CoreGraphics

/// Metadata describing a recording session, persisted as `metadata.json` inside the `.reco` bundle.
struct ProjectMetadata: Codable {
    /// When the recording was created
    var createdAt: Date

    /// Total recording duration in seconds
    var duration: TimeInterval

    /// The configuration used during recording
    var recordingConfig: RecordingConfig

    /// Actual captured screen resolution
    var screenResolution: CGSize

    /// Whether the bundle contains a camera track
    var hasCamera: Bool

    /// Whether the bundle contains a microphone audio track
    var hasMicAudio: Bool

    /// Whether the bundle contains a system audio track
    var hasSystemAudio: Bool

    /// Whether the bundle contains cursor tracking data
    var hasCursorData: Bool

    // MARK: - Factory

    /// Creates default metadata for a new recording.
    static func makeDefault(config: RecordingConfig = RecordingConfig()) -> ProjectMetadata {
        ProjectMetadata(
            createdAt: Date(),
            duration: 0,
            recordingConfig: config,
            screenResolution: CGSize(width: 1920, height: 1080),
            hasCamera: config.cameraEnabled,
            hasMicAudio: config.micEnabled,
            hasSystemAudio: config.systemAudioEnabled,
            hasCursorData: false
        )
    }
}
