> **Requires**: Run in a dedicated worktree (`--worktree task-2-project-bundle` on branch `task-2-project-bundle`). Branch from `main` AFTER Task 0 has been merged.

# Task 2: Project Bundle & Storage

## Objective

Implement the project bundle manager that handles reading, writing, and validating `.reco` recording bundles. This is the bridge between the capture engine and the editor/compositor.

## Scope — Files to Create/Modify

**Create:**
```
Reco/Engine/ProjectBundle.swift      # Project bundle read/write/validation
Reco/Engine/ProjectMetadata.swift    # Bundle metadata and manifest
```

**Do NOT touch:**
- Anything in `Views/`, `App/`, `Protocols/`, `Resources/`
- Other `Engine/` files (CaptureEngine, Compositor, etc.)
- `Models/` files — use `RecordingConfig.swift` and `EditSettings.swift` as-is

## Context

### Bundle Structure
```
Recording-2026-04-14-16-57-19.reco/
├── screen.mov              # Screen capture video
├── camera.mov              # Camera feed (optional)
├── audio-mic.caf           # Microphone audio (optional)
├── audio-system.caf        # System audio (optional)
├── cursor.json             # Cursor position + click timeline
├── metadata.json           # Recording metadata (date, duration, config)
└── project.json            # Edit settings (background, cursor, camera, trim)
```

### Design Decisions
- The bundle is a plain directory (not a macOS document bundle — keep it simple for MVP)
- All settings are JSON, readable and debuggable
- The bundle is self-contained — all paths are relative within the bundle
- Custom background images are copied into the bundle when selected

## Detailed Requirements

### ProjectBundle.swift

A struct or class that represents an opened project bundle.

```swift
// Conceptual API — implement with these semantics
struct ProjectBundle {
    let url: URL  // Path to the .reco directory

    // Track URLs (nil if track doesn't exist)
    var screenURL: URL? { get }
    var cameraURL: URL? { get }
    var micAudioURL: URL? { get }
    var systemAudioURL: URL? { get }
    var cursorURL: URL? { get }

    // Metadata
    var metadata: ProjectMetadata { get set }

    // Edit settings
    var editSettings: EditSettings { get set }

    // Lifecycle
    static func create(at directory: URL, name: String) throws -> ProjectBundle
    static func open(at url: URL) throws -> ProjectBundle

    // Persistence
    func saveEditSettings() throws
    func saveMetadata() throws

    // Validation
    func validate() throws  // Checks required files exist

    // Cursor data
    func loadCursorData() throws -> CursorData

    // Custom background image
    func importBackgroundImage(from sourceURL: URL) throws -> String  // Returns relative path within bundle
}
```

### ProjectMetadata.swift

```swift
struct ProjectMetadata: Codable {
    var createdAt: Date
    var duration: TimeInterval          // Total recording duration in seconds
    var recordingConfig: RecordingConfig // Config used during recording
    var screenResolution: CGSize        // Actual captured resolution
    var hasCamera: Bool
    var hasMicAudio: Bool
    var hasSystemAudio: Bool
    var hasCursorData: Bool
}
```

### CursorData (in ProjectBundle.swift or separate file)

```swift
struct CursorEvent: Codable {
    var timestamp: Double
    var x: Double
    var y: Double
    var visible: Bool
    var clicked: Bool
}

struct CursorData: Codable {
    var events: [CursorEvent]
    var screenWidth: Double
    var screenHeight: Double
}
```

### File Operations
- `create(at:name:)`: Creates the `.reco` directory and initializes `metadata.json` and `project.json` with defaults
- `open(at:)`: Opens an existing bundle, reads metadata and settings
- `saveEditSettings()`: Writes current `EditSettings` to `project.json`
- `validate()`: Checks that `screen.mov` exists (required), other tracks are optional
- `importBackgroundImage(from:)`: Copies an image file into the bundle (e.g., `background.png`), returns relative path

### RecordingConfig Codable Conformance
- `RecordingConfig` in Task 0 may not be `Codable` — if it's not, add `Codable` conformance to a **separate extension file** in this task: `Reco/Engine/RecordingConfig+Codable.swift`
- Handle `CGDirectDisplayID` (UInt32) and `CGRect` serialization

### Error Handling
- `ProjectBundleError` enum with cases: `.bundleNotFound`, `.invalidBundle`, `.missingScreenTrack`, `.corruptedMetadata`, `.corruptedSettings`
- All errors should have descriptive messages

## What NOT to Do
- Do not implement video reading/decoding (that's the Compositor's job)
- Do not implement any UI
- Do not modify shared types in `Models/` or `Protocols/`
- Do not add third-party dependencies

## Checklist

- [ ] Can create a new empty `.reco` bundle with metadata and default settings
- [ ] Can open an existing bundle and read metadata + settings
- [ ] Can save modified edit settings back to `project.json`
- [ ] Can load and parse `cursor.json` into `CursorData`
- [ ] Can import a custom background image into the bundle
- [ ] Validation correctly identifies missing `screen.mov` as error
- [ ] Validation passes when all expected tracks are present
- [ ] All JSON files are human-readable (pretty-printed)
- [ ] Handles corrupt/missing JSON gracefully with descriptive errors
- [ ] `RecordingConfig` is serializable to JSON (via extension if needed)
- [ ] Project builds with no warnings
- [ ] Commit message: `feat: implement project bundle storage and management`
