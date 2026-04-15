import Foundation
import CoreGraphics

// MARK: - RecordingConfig Codable Conformance

extension RecordingConfig: Codable {
    enum CodingKeys: String, CodingKey {
        case mode
        case displayID
        case captureArea
        case resolution
        case cameraEnabled
        case cameraDeviceID
        case micEnabled
        case microphoneDeviceID
        case systemAudioEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decode(RecordMode.self, forKey: .mode)
        displayID = try container.decode(CGDirectDisplayID.self, forKey: .displayID)
        captureArea = try container.decode(CaptureArea.self, forKey: .captureArea)
        resolution = try container.decode(Resolution.self, forKey: .resolution)
        cameraEnabled = try container.decode(Bool.self, forKey: .cameraEnabled)
        cameraDeviceID = try container.decodeIfPresent(String.self, forKey: .cameraDeviceID)
        micEnabled = try container.decode(Bool.self, forKey: .micEnabled)
        microphoneDeviceID = try container.decodeIfPresent(String.self, forKey: .microphoneDeviceID)
        systemAudioEnabled = try container.decode(Bool.self, forKey: .systemAudioEnabled)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode, forKey: .mode)
        try container.encode(displayID, forKey: .displayID)
        try container.encode(captureArea, forKey: .captureArea)
        try container.encode(resolution, forKey: .resolution)
        try container.encode(cameraEnabled, forKey: .cameraEnabled)
        try container.encodeIfPresent(cameraDeviceID, forKey: .cameraDeviceID)
        try container.encode(micEnabled, forKey: .micEnabled)
        try container.encodeIfPresent(microphoneDeviceID, forKey: .microphoneDeviceID)
        try container.encode(systemAudioEnabled, forKey: .systemAudioEnabled)
    }
}
