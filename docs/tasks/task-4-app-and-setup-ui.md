> **Requires**: Run in a dedicated worktree (`--worktree task-4-app-setup-ui` on branch `task-4-app-setup-ui`). Branch from `main` AFTER Task 0 has been merged.

# Task 4: App State, Setup View & Recording Panel

## Objective

Implement the app state management, the setup/configuration view (Phase 1), and the floating recording control panel (Phase 2). This covers the entire flow from app launch through recording completion.

## Scope — Files to Create/Modify

**Modify:**
```
Reco/App/RecoApp.swift                   # Replace placeholder with real app structure
```

**Create:**
```
Reco/App/AppState.swift                  # Central app state management
Reco/App/PermissionManager.swift         # Screen recording, camera, mic permission checks
Reco/Views/Setup/SetupView.swift         # Main setup/configuration view
Reco/Views/Setup/RecordModeSelector.swift    # Portrait+Screen / Screen Only toggle
Reco/Views/Setup/ScreenSelector.swift    # Screen + area selection
Reco/Views/Recording/RecordingPanel.swift    # Floating NSPanel for recording controls
Reco/Views/Recording/RecordingPanelController.swift  # NSPanel window management
```

**Do NOT touch:**
- Anything in `Engine/`, `Models/`, `Protocols/`, `Resources/`
- Anything in `Views/Editor/`

## Context

### App Flow
```
App Launch → SetupView → [Start Recording] → RecordingPanel visible → [Stop] → (transition to Editor)
                                                                       [Discard] → back to SetupView
```

### AppState manages phase transitions
```swift
enum AppPhase {
    case setup
    case recording
    case editing(projectURL: URL)
}
```

The editor phase receives the project URL from the completed recording. Editor UI is built by Task 5 — this task just needs to transition to `.editing` state and show a placeholder.

## Detailed Requirements

### AppState.swift
```swift
@Observable
class AppState {
    var phase: AppPhase = .setup
    var recordingConfig: RecordingConfig = .init()

    // Recording state (updated by engine during recording)
    var isRecording: Bool
    var isPaused: Bool
    var elapsedTime: TimeInterval

    // Methods
    func startRecording() async throws
    func pauseRecording()
    func resumeRecording()
    func stopRecording() async throws  // Transitions to .editing
    func discardRecording()            // Transitions back to .setup
}
```

- Holds a reference to `CaptureEngineProtocol` (use the protocol, not concrete type — engine may not exist yet in this worktree, so use a mock/stub)
- Since the actual `CaptureEngine` is built in Task 1, **create a `MockCaptureEngine`** in this task that conforms to `CaptureEngineProtocol` for development and testing:
  - `startRecording`: creates an empty `.reco` directory, starts a timer
  - `stopRecording`: returns the bundle URL
  - `pauseRecording`/`resumeRecording`: toggle a flag

### PermissionManager.swift
- Check and request screen recording permission (ScreenCaptureKit: `SCShareableContent.current`)
- Check and request camera permission (`AVCaptureDevice.requestAccess(for: .video)`)
- Check and request microphone permission (`AVCaptureDevice.requestAccess(for: .audio)`)
- Expose permission status as `@Observable` properties
- Show guidance if permissions are denied (direct user to System Preferences)

### RecoApp.swift
- Single `WindowGroup` that switches view based on `AppState.phase`
- `.setup` → `SetupView`
- `.recording` → minimal view (or hide main window), show `RecordingPanel`
- `.editing` → placeholder `Text("Editor — Task 5")` (Task 5 replaces this)
- Window should have a reasonable default size (~400x600 for setup)

### SetupView.swift
Layout (top to bottom, matching the reference screenshot):

1. **Header**: App icon + "Reco" title + settings gear icon
2. **Record Mode**: Two cards side-by-side
   - "Portrait + Screen" (with icon showing person + monitor)
   - "Screen Only" (with icon showing monitor only)
   - Selected card has highlighted border
3. **Screen Selection**:
   - Dropdown to pick display (query `NSScreen.screens`)
   - Two buttons: "Full Screen" / "Custom Area"
   - "Custom Area" triggers an overlay for region selection (basic rectangle drag)
4. **Resolution Selection**: Dropdown (Original, 4K, 1080p, 720p)
5. **Record Section** (three rows):
   - Camera: device selector dropdown or "Disabled"
   - Microphone: device selector dropdown or "Disabled"
   - System Audio: Yes/No toggle
6. **Start Button**: Full-width "Screen Recording" button with record icon

Style: Clean, native macOS look using SwiftUI defaults. Subtle section headers. No custom color theme for MVP.

### RecordingPanel (NSPanel)

This is a **floating panel** that appears during recording and must NOT be captured in the recording.

**RecordingPanelController.swift:**
- Creates an `NSPanel` (not `NSWindow`) with these properties:
  - `.nonactivatingPanel` style mask — doesn't steal focus
  - `.floating` window level — always on top
  - `.fullSizeContentView` for clean appearance
  - Compact size (~80x300 vertical layout, or ~300x80 horizontal)
  - Dark background, semi-transparent
- Exposes the panel's `CGWindowID` so the capture engine can exclude it
- Hosts a SwiftUI `RecordingPanel` view via `NSHostingView`

**RecordingPanel.swift (SwiftUI View):**
- Vertical layout:
  - **Stop** button (red circle icon) — calls `appState.stopRecording()`
  - **Pause/Resume** button (toggle icon) — calls pause/resume
  - **Timer** display: `HH:MM:SS` format, updates every second
  - **Delete** button (trash icon) — calls `appState.discardRecording()` with confirmation
- The panel is draggable (user can reposition it)
- Minimal, dark UI to be unobtrusive

### Custom Area Selection
When user clicks "Custom Area":
- Show a semi-transparent overlay on the selected screen
- User drags to select a rectangle
- Display pixel dimensions while dragging
- Confirm selection (click or Enter), or cancel (Escape)
- Store the `CGRect` in `RecordingConfig.captureArea`

This can be a simple implementation — a transparent `NSWindow` covering the screen with mouse tracking.

## What NOT to Do
- Do not implement actual capture logic (use MockCaptureEngine)
- Do not implement the editor view (just transition to `.editing` phase with placeholder)
- Do not modify files in `Engine/`, `Models/`, `Protocols/`
- Do not add third-party dependencies

## Checklist

- [ ] App launches and shows SetupView
- [ ] Record Mode selector toggles between Portrait+Screen and Screen Only
- [ ] Screen selector lists available displays
- [ ] Full Screen / Custom Area toggle works
- [ ] Custom Area selection overlay appears and captures a rectangle
- [ ] Resolution dropdown shows all options
- [ ] Camera/Mic device dropdowns list available devices
- [ ] System Audio toggle works
- [ ] Start Recording button transitions to recording phase
- [ ] RecordingPanel appears as a floating, always-on-top panel
- [ ] RecordingPanel does not steal focus from other apps
- [ ] RecordingPanel `CGWindowID` is accessible for capture exclusion
- [ ] Stop button stops recording and transitions to editing phase
- [ ] Pause/Resume toggles correctly
- [ ] Timer counts up accurately during recording
- [ ] Delete discards recording and returns to setup
- [ ] Permission prompts appear on first use
- [ ] Denied permissions show helpful guidance
- [ ] MockCaptureEngine works for development without real capture
- [ ] App builds and runs with no warnings
- [ ] Commit message: `feat: implement app state, setup view, and recording panel`
