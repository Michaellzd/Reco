# Reco - Architecture

## Guiding Principle

**Harness engineering first.** The recording pipeline, multi-track storage, and compositing engine are the foundation. UI is built on top of a working, tested engine — never the other way around.

## High-Level Architecture

```
┌─────────────────────────────────────────────────┐
│                   SwiftUI Layer                  │
│  ┌─────────┐  ┌──────────────┐  ┌────────────┐  │
│  │  Setup   │  │  Recording   │  │   Editor    │  │
│  │  View    │  │  Controls    │  │   View      │  │
│  └────┬─────┘  └──────┬───────┘  └─────┬──────┘  │
├───────┼────────────────┼────────────────┼─────────┤
│       │          State Layer            │         │
│  ┌────▼────────────────▼────────────────▼──────┐  │
│  │          AppState / ViewModels              │  │
│  └────┬────────────────┬────────────────┬──────┘  │
├───────┼────────────────┼────────────────┼─────────┤
│       │          Engine Layer            │         │
│  ┌────▼─────┐  ┌───────▼──────┐  ┌──────▼──────┐ │
│  │ Capture  │  │  Storage /   │  │ Compositor  │ │
│  │ Engine   │  │  Project     │  │ / Renderer  │ │
│  └──────────┘  └──────────────┘  └─────────────┘ │
├───────────────────────────────────────────────────┤
│                 System Frameworks                 │
│  ScreenCaptureKit  AVFoundation  CoreImage  Metal │
└───────────────────────────────────────────────────┘
```

## Layer Breakdown

### 1. Engine Layer (Priority: Highest)

This is where harness engineering lives. Build and stabilize this first.

#### Capture Engine
- **Screen Capture**: ScreenCaptureKit (`SCStream`) to capture screen content
  - Supports content filtering (exclude the control panel window)
  - Supports full screen and custom area capture
  - Captures at native resolution, downscale at export time
- **Camera Capture**: AVFoundation (`AVCaptureSession`) for webcam feed
  - Separate capture pipeline, stored as independent track
- **Audio Capture**: AVFoundation for microphone + ScreenCaptureKit for system audio
  - Stored as separate audio tracks
- **Cursor Data**: ScreenCaptureKit provides cursor position and visibility per frame
  - Stored as a metadata track (timestamps + positions + click events)

All four streams are captured independently and written to a **multi-track project file**.

#### Storage / Project Format
- Each recording session produces a project bundle (directory):
  ```
  Recording-2026-04-14-16-57-19.reco/
    screen.mov          # Raw screen capture (no cursor baked in)
    camera.mov          # Raw camera feed
    audio-mic.caf       # Microphone audio
    audio-system.caf    # System audio
    cursor.json         # Cursor position + click event timeline
    project.json        # Edit settings (background, camera position, etc.)
  ```
- This separation enables full flexibility in the editor — every element can be toggled, resized, repositioned after recording

#### Compositor / Renderer
- Takes the project bundle + edit settings and produces the final video
- Pipeline:
  1. Read screen frames → apply corner radius, shadow, scaling
  2. Render background layer (wallpaper/gradient/color/image)
  3. Composite screen on background
  4. Render cursor overlay (with size/style/effects applied)
  5. Render camera overlay (with shape, size, position applied)
  6. Encode final frames + mixed audio → output MP4/ProRes
- Uses **AVAssetWriter** for encoding, **CoreImage** or **Metal** for frame compositing
- Runs as a background operation with progress reporting

### 2. State Layer

- **AppState**: Centralized state management using `@Observable` (Swift Observation framework)
- Manages phase transitions: Setup → Recording → Editor
- Holds recording configuration, edit settings, export state
- ViewModels per phase where needed, but keep it flat — avoid over-engineering

### 3. UI Layer (Priority: Lowest initially)

- **Setup View**: Record mode selector, screen/area picker, audio source toggles, start button
- **Recording Controls**: Floating `NSPanel` (not `NSWindow`) — key for excludability and always-on-top behavior
- **Editor View**: Split layout — video preview (left), settings panel (right), timeline (bottom)

## Key Technical Decisions

### Why separate tracks instead of baking everything during recording?
- Users can change their mind about camera position, cursor style, background after recording
- Allows re-export with different settings without re-recording
- Cursor data as metadata means we can apply effects (size change, click highlight) that weren't configured during recording

### Recording control panel exclusion
- `SCContentFilter` accepts an `excludedWindows` parameter
- The control panel must be a separate `NSWindow` (or `NSPanel`) so it has its own `CGWindowID`
- On init, add its window ID to the filter's exclusion list

### Why NSPanel for recording controls?
- `NSPanel` with `.nonactivatingPanel` style stays visible without stealing focus
- Can be set to float above all windows (`.floating` level)
- Minimal footprint — the user's app stays in focus while recording

### Editor preview: real-time vs on-demand
- MVP: **On-demand** — render a preview frame when settings change, not a live video playback with all effects
- Playback shows the raw screen recording; export applies all effects
- This avoids building a real-time compositing engine for MVP (can add later)

## Data Flow

```
[User clicks Record]
    │
    ▼
Capture Engine starts 4 parallel streams
    │
    ▼
Streams write to project bundle on disk
    │
    ▼
[User clicks Stop]
    │
    ▼
Editor loads project bundle
    │
    ▼
User adjusts settings (background, cursor, camera, trim)
    │
    ▼
Settings saved to project.json
    │
    ▼
[User clicks Export]
    │
    ▼
Compositor reads project bundle + settings
    │
    ▼
Renders frame-by-frame → encodes to output file
    │
    ▼
Final MP4/ProRes saved to user-chosen location
```

## File Structure (Planned)

```
Reco/
├── Reco.xcodeproj
├── Reco/
│   ├── App/
│   │   ├── RecoApp.swift            # App entry point
│   │   └── AppState.swift           # Central state management
│   ├── Engine/
│   │   ├── CaptureEngine.swift      # ScreenCaptureKit + AVFoundation capture
│   │   ├── CursorTracker.swift      # Cursor position/click event recording
│   │   ├── ProjectBundle.swift      # Project file read/write
│   │   └── Compositor.swift         # Final video rendering/compositing
│   ├── Views/
│   │   ├── Setup/
│   │   │   └── SetupView.swift
│   │   ├── Recording/
│   │   │   └── RecordingPanel.swift # NSPanel-based floating controls
│   │   └── Editor/
│   │       ├── EditorView.swift
│   │       ├── TimelineView.swift
│   │       ├── BackgroundPanel.swift
│   │       ├── CursorPanel.swift
│   │       └── CameraPanel.swift
│   ├── Models/
│   │   ├── RecordingConfig.swift    # Setup phase configuration
│   │   └── EditSettings.swift       # Editor phase settings
│   └── Resources/
│       └── Wallpapers/             # Bundled background images
├── docs/
├── CLAUDE.md
└── README.md
```
