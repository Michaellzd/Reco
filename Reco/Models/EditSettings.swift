import Foundation
import CoreGraphics
import CoreMedia

enum BackgroundType: String, Codable {
    case wallpaper
    case gradient
    case solidColor
    case customImage
}

struct BackgroundConfig: Codable {
    var type: BackgroundType = .solidColor
    var wallpaperName: String?
    var gradientColors: [String] = ["#000000", "#333333"]  // Hex colors
    var gradientAngle: Double = 0
    var solidColor: String = "#FFFFFF"
    var customImagePath: String?
    var shadowSize: Double = 30
    var shadowOpacity: Double = 60
    var shadowBlur: Double = 40
    var cornerRadius: Double = 12
    var screenScale: Double = 85  // percentage
}

enum CursorStyle: String, Codable {
    case none
    case touch
}

struct CursorConfig: Codable {
    var hidden: Bool = false
    var size: Double = 2.0
    var style: CursorStyle = .none
    var rotationIntensity: Double = 0
}

enum CameraShape: String, Codable, CaseIterable {
    case circle
    case roundedRect
    case roundedRectWide
    case squareRounded
    case square
    case hidden
}

enum CameraPosition: Int, Codable, CaseIterable {
    case topLeft = 0, topCenter, topRight
    case middleLeft, middleCenter, middleRight
    case bottomLeft, bottomCenter, bottomRight
}

struct CameraConfig: Codable {
    var hidden: Bool = false
    var size: Double = 30  // percentage
    var followVideoZoom: Bool = true
    var cornerRadius: Double = 20
    var shape: CameraShape = .circle
    var position: CameraPosition = .bottomLeft
}

struct TrimRange: Codable {
    var startTime: Double  // seconds
    var endTime: Double    // seconds
}

struct EditSettings: Codable {
    var background: BackgroundConfig = .init()
    var cursor: CursorConfig = .init()
    var camera: CameraConfig = .init()
    var trimRanges: [TrimRange] = []       // Segments to KEEP
    var deletedSegments: [TrimRange] = []  // Segments to REMOVE
    var fps: Int = 60
}
