> **Requires**: Run in a dedicated worktree (`--worktree task-0-foundation` on branch `task-0-foundation`)

# Task 0: Foundation & Scaffold

**Run this task FIRST and merge to main before any other task starts.** All other tasks branch from the commit this task produces.

## Objective

Create the Xcode project, directory structure, and all shared protocols/types that other tasks depend on. This task produces zero business logic — only the skeleton and contracts.

## Scope — Files to Create

```
Reco/
├── Reco.xcodeproj                          # Xcode project (macOS app, SwiftUI lifecycle)
├── Reco/
│   ├── App/
│   │   └── RecoApp.swift                   # Minimal app entry: just launches a placeholder view
│   ├── Engine/
│   │   └── .gitkeep
│   ├── Views/
│   │   ├── Setup/
│   │   │   └── .gitkeep
│   │   ├── Recording/
│   │   │   └── .gitkeep
│   │   └── Editor/
│   │       └── .gitkeep
│   ├── Models/
│   │   ├── RecordingConfig.swift           # RecordingConfig struct + related enums
│   │   └── EditSettings.swift              # EditSettings + sub-configs (Background, Cursor, Camera, Trim)
│   ├── Protocols/
│   │   ├── CaptureEngineProtocol.swift     # Protocol for capture engine
│   │   └── CompositorProtocol.swift        # Protocol for compositor/renderer
│   └── Resources/
│       └── Wallpapers/
│           └── .gitkeep
├── Reco/Info.plist                          # With required permission descriptions
├── Reco/Reco.entitlements                   # App Sandbox entitlements
├── CLAUDE.md                                # Already exists — verify it's in the project
└── README.md                                # Already exists — verify it's in the project
```

## Detailed Requirements

### Xcode Project Setup
- macOS app target, minimum deployment: macOS 14.0
- SwiftUI App lifecycle
- Bundle identifier: `com.reco.app` (placeholder)
- App Sandbox enabled with entitlements:
  - `com.apple.security.device.camera`
  - `com.apple.security.device.audio-input`
  - `com.apple.security.files.user-selected.read-write`

### Info.plist Permission Descriptions
- `NSCameraUsageDescription`: "Reco needs camera access to record your webcam overlay"
- `NSMicrophoneUsageDescription`: "Reco needs microphone access to record audio narration"
- `NSScreenCaptureUsageDescription` (if applicable via ScreenCaptureKit)

### Shared Types — RecordingConfig.swift
```swift
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
    var micEnabled: Bool = false
    var systemAudioEnabled: Bool = true
}
```

### Shared Types — EditSettings.swift
```swift
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
```

### Shared Protocols — CaptureEngineProtocol.swift
```swift
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
```

### Shared Protocols — CompositorProtocol.swift
```swift
import Foundation
import CoreGraphics
import CoreMedia

protocol CompositorProtocol {
    /// Render a single composite frame at the given time for preview
    func renderPreviewFrame(
        projectURL: URL,
        settings: EditSettings,
        at time: CMTime
    ) async throws -> CGImage

    /// Export the full composited video
    func export(
        projectURL: URL,
        settings: EditSettings,
        outputURL: URL,
        progress: @escaping (Double) -> Void
    ) async throws
}
```

### RecoApp.swift (Minimal)
```swift
import SwiftUI

@main
struct RecoApp: App {
    var body: some Scene {
        WindowGroup {
            Text("Reco — coming soon")
                .frame(width: 400, height: 300)
        }
    }
}
```

## What NOT to Do
- Do not implement any business logic
- Do not add third-party dependencies
- Do not create any views beyond the placeholder

## Checklist

- [ ] Xcode project builds and runs (shows placeholder window)
- [ ] All directories exist with correct structure
- [ ] `RecordingConfig` and all related enums compile
- [ ] `EditSettings` and all sub-configs compile and conform to `Codable`
- [ ] `CaptureEngineProtocol` compiles with correct method signatures
- [ ] `CompositorProtocol` compiles with correct method signatures
- [ ] Info.plist contains all required permission descriptions
- [ ] Entitlements file contains camera, microphone, and file access
- [ ] App Sandbox is enabled
- [ ] Deployment target is macOS 14.0
- [ ] No warnings, no errors on build
- [ ] Commit message: `feat: project scaffold with shared types and protocols`
