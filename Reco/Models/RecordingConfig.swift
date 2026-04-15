import Foundation
import CoreGraphics

enum RecordMode: String, Codable {
    case portraitAndScreen
    case screenOnly
}

enum CaptureArea: Codable, Equatable {
    case fullScreen
    case custom(CGRect)
}

enum Resolution: String, Codable, CaseIterable {
    case original
    case p2160  // 4K
    case p1080
    case p720
}

struct RecordingConfig {
    var mode: RecordMode = .screenOnly
    var displayID: CGDirectDisplayID = CGMainDisplayID()
    var captureArea: CaptureArea = .fullScreen
    var resolution: Resolution = .original
    var cameraEnabled: Bool = false
    var cameraDeviceID: String?
    var micEnabled: Bool = false
    var microphoneDeviceID: String?
    var systemAudioEnabled: Bool = true
}
