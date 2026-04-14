> **Requires**: Run in a dedicated worktree (`--worktree task-5-editor-ui` on branch `task-5-editor-ui`). Branch from `main` AFTER Task 0 has been merged.

# Task 5: Editor UI

## Objective

Implement the entire post-recording editor interface — video preview, timeline with trim/split, and all settings panels (background, cursor, camera). This is the Phase 3 UI where users beautify their recording before export.

## Scope — Files to Create/Modify

**Create:**
```
Reco/Views/Editor/EditorView.swift           # Main editor layout (preview + panels + timeline)
Reco/Views/Editor/VideoPreview.swift         # Video preview area
Reco/Views/Editor/TimelineView.swift         # Timeline with trim, split, scrub, zoom
Reco/Views/Editor/SettingsPanel.swift        # Right-side panel container with tab switching
Reco/Views/Editor/BackgroundPanel.swift      # Background settings tab
Reco/Views/Editor/CursorPanel.swift          # Cursor settings tab
Reco/Views/Editor/CameraPanel.swift          # Camera settings tab
Reco/Views/Editor/ExportView.swift           # Export dialog/sheet
Reco/Views/Editor/EditorState.swift          # Editor-specific state management
```

**Do NOT touch:**
- Anything in `Engine/`, `Models/`, `Protocols/`, `App/`
- Anything in `Views/Setup/`, `Views/Recording/`
- Do not modify `RecoApp.swift` — Task 4 handles the phase routing

## Context

### Editor Layout (reference: Image 3)
```
┌───────────────────────────────────────────────────────────────────┐
│  [filename]                              FPS [60▼] [camIcon] [Export] │
├────────────────────────────────────┬──────────────────────────────┤
│                                    │  [BG] [Cursor] [Camera] [Audio] │
│                                    │                              │
│        Video Preview               │     Settings Panel           │
│        (composited frame)          │     (active tab content)     │
│                                    │                              │
│                                    │                              │
├────────────────────────────────────┴──────────────────────────────┤
│  [Tracks▼]  [◄◄] [►] [►►]  00:00:00 / 00:57:31   🔍 [zoom slider] │
│  ╔══════════════════════════════════════════════════════════════╗  │
│  ║  Timeline (thumbnail strip with trim handles)               ║  │
│  ╚══════════════════════════════════════════════════════════════╝  │
└───────────────────────────────────────────────────────────────────┘
```

### This task uses protocol stubs
Since the actual `Compositor` (Task 3) and `ProjectBundle` (Task 2) may not exist in this worktree, create **mock implementations** for development:

- `MockCompositor`: Conforms to `CompositorProtocol`, returns a placeholder `CGImage` for preview, simulates export with progress
- `MockProjectBundle`: Provides test data (duration, dummy settings, etc.)

These mocks live in this task's files and will be replaced when branches merge.

## Detailed Requirements

### EditorState.swift
```swift
@Observable
class EditorState {
    // Project
    var projectURL: URL
    var duration: TimeInterval  // Total recording duration

    // Playback
    var currentTime: TimeInterval = 0
    var isPlaying: Bool = false

    // Settings (bound to UI controls, saved to project.json on change)
    var editSettings: EditSettings = .init()

    // Timeline
    var zoomLevel: Double = 1.0  // 1.0 = fit all, higher = zoomed in
    var splitPoints: [TimeInterval] = []
    var selectedSegmentIndex: Int?

    // Export
    var isExporting: Bool = false
    var exportProgress: Double = 0

    // Preview
    var previewImage: CGImage?

    // Methods
    func updatePreview() async  // Re-render preview frame at currentTime
    func play()
    func pause()
    func seekTo(_ time: TimeInterval)
    func splitAtPlayhead()
    func deleteSelectedSegment()
    func export() async throws
}
```

### EditorView.swift
Main container with three areas:
- **Top bar**: Filename, FPS selector, camera toggle shortcut, Export button
- **Center**: `HSplitView` with VideoPreview (left, ~70%) and SettingsPanel (right, ~30%)
- **Bottom**: TimelineView

Window should be resizable with reasonable minimum size (~900x600).

### VideoPreview.swift
- Displays `editorState.previewImage` scaled to fit the preview area
- Shows the composited result (background + screen + cursor + camera)
- Updates when:
  - User scrubs timeline (new `currentTime`)
  - User changes any setting in the panels
- During playback: steps through frames at the configured FPS (use a `DisplayLink` or `Timer`)
- Playback shows raw screen recording (not fully composited — compositing every frame in real-time is too expensive for MVP). Preview frame compositing is only on pause/scrub.

### TimelineView.swift
Horizontal timeline bar at the bottom.

**Visual elements:**
- Thumbnail strip: Generate thumbnails from `screen.mov` at regular intervals (e.g., every 2 seconds), display as a strip
- Playhead: Vertical line showing current position, draggable
- Trim handles: Drag start/end of timeline to trim
- Split indicators: Vertical lines at split points
- Segments: Split regions are visually distinct, selected segment highlighted

**Interactions:**
- **Scrub**: Click or drag on timeline to move playhead
- **Zoom**: Scroll wheel or pinch to zoom in/out on timeline; zoom slider in toolbar
- **Split**: With playhead at desired position, press a split button (or keyboard shortcut) to split
- **Select segment**: Click on a segment between splits to select it
- **Delete segment**: Press Delete key or button to remove selected segment
- **Trim handles**: Drag the start/end handles to adjust trim points

**Keyboard shortcuts (register in EditorView):**
- Space: Play/Pause
- Left/Right arrows: Step forward/back by 1 frame
- Cmd+Left/Right: Jump to start/end
- S or Cmd+Shift+S: Split at playhead

### SettingsPanel.swift
Tab-based right panel. Tabs shown as icons in a vertical sidebar (matching reference Image 4/5):
- Background icon (rectangle)
- Cursor icon (arrow pointer)
- Camera icon (camera)
- Audio icon (speaker) — for MVP, just show a volume slider placeholder

Active tab content fills the panel area.

### BackgroundPanel.swift
Tab selector row at top: Wallpaper | Gradient | Color | Custom

**Wallpaper tab:**
- Grid of preset wallpaper thumbnails (6-8 options)
- Click to select, shows border highlight

**Gradient tab:**
- Two color pickers (start/end color)
- Angle slider (0-360 degrees)
- Live preview in the small swatch

**Color tab:**
- macOS native `ColorPicker` for solid color selection

**Custom tab:**
- "Choose Image" button → file picker (PNG, JPG, HEIC)
- Shows selected image thumbnail
- "Remove" button to clear

**Below tabs (always visible):**
- Shadow Size: labeled slider (0-100)
- Shadow Opacity: labeled slider (0-100)
- Shadow Blur: labeled slider (0-100)
- Corner Radius: labeled slider (0-50)
- Screen Size: labeled slider (50-100%)
- Each slider has a "Reset" button to restore default

All sliders update `editorState.editSettings.background` and trigger preview refresh.

### CursorPanel.swift
- **Hide Cursor**: Toggle switch
- **Cursor Size**: Labeled slider (1.0 - 5.0) with value display
- **Cursor Custom**: Segmented control — None | Touch
- **Rotation Intensity**: Labeled slider (0-45 degrees) with Reset button

All controls update `editorState.editSettings.cursor` and trigger preview refresh.

### CameraPanel.swift
- **Hide Camera**: Toggle switch
- **Camera Size**: Labeled slider (10% - 50%) with value display and Reset
- **Follow Video Zoom**: Toggle switch
- **Corner Radius**: Labeled slider (0-50) with Reset
- **Shape**: Horizontal row of shape option buttons (circle, rounded rects, square, hidden X)
  - Selected shape has highlight background
- **Camera Position**: 3x3 grid of circular buttons
  - Selected position is filled/highlighted
  - Clicking a position updates `editorState.editSettings.camera.position`
  - Preview updates live to show camera in new position

### ExportView.swift
Modal sheet triggered by Export button:
- Output format selector: MP4 (H.264) | HEVC | ProRes
- Resolution: Original | 1080p | 720p | 4K
- FPS: 30 | 60
- Output path: "Choose..." button with file picker, shows selected path
- "Export" button to start
- Progress bar during export (bound to `editorState.exportProgress`)
- "Cancel" button during export
- "Done" / "Open in Finder" on completion

### Mock Implementations (for development)

**MockCompositor:**
```swift
class MockCompositor: CompositorProtocol {
    func renderPreviewFrame(projectURL:settings:at:) async throws -> CGImage {
        // Return a colored rectangle CGImage as placeholder
    }
    func export(projectURL:settings:outputURL:progress:) async throws {
        // Simulate export: increment progress over 3 seconds
    }
}
```

**Thumbnail generation:**
- Use `AVAssetImageGenerator` to extract frames from `screen.mov` at intervals
- If `screen.mov` doesn't exist (mock mode), show gray placeholder thumbnails

## What NOT to Do
- Do not implement actual video compositing (use MockCompositor)
- Do not implement actual project bundle reading (mock it)
- Do not modify `RecoApp.swift` or any App/ files
- Do not modify shared types in Models/ or Protocols/
- Do not add third-party dependencies

## Checklist

- [ ] EditorView shows three-area layout (preview, settings, timeline)
- [ ] VideoPreview displays a composited preview frame
- [ ] Preview updates when scrubbing timeline
- [ ] Preview updates when changing settings
- [ ] TimelineView shows thumbnail strip (or placeholders in mock mode)
- [ ] Playhead is draggable and shows current position
- [ ] Split at playhead creates visual split indicator
- [ ] Segments can be selected and deleted
- [ ] Trim handles at start/end work
- [ ] Timeline zoom in/out works (scroll + slider)
- [ ] Play/Pause with Space key works
- [ ] Arrow keys step frame-by-frame
- [ ] BackgroundPanel: all 4 tabs render correctly (Wallpaper, Gradient, Color, Custom)
- [ ] BackgroundPanel: all sliders (shadow, corner radius, screen size) update settings
- [ ] CursorPanel: hide toggle, size slider, style selector, rotation slider all work
- [ ] CameraPanel: hide toggle, size slider, corner radius, shape selector all work
- [ ] CameraPanel: 3x3 position grid selection works and updates preview
- [ ] ExportView: modal appears with format/resolution/fps options
- [ ] ExportView: shows progress bar during (mock) export
- [ ] All Reset buttons restore default values
- [ ] Settings panel tabs switch correctly
- [ ] Keyboard shortcuts work (Space, arrows, S for split)
- [ ] Window is resizable with reasonable constraints
- [ ] App builds and runs with no warnings
- [ ] Commit message: `feat: implement editor UI with timeline, settings panels, and export`
