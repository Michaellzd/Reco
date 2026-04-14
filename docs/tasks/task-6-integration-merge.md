> **Requires**: Run in a dedicated worktree (`--worktree task-6-integration` on branch `task-6-integration`). Branch from `main` AFTER Tasks 1-5 are all complete but NOT yet merged.

# Task 6: Integration & Final Merge

## Objective

Merge all task branches (1-5) into a single working application. Replace all mocks with real implementations, wire up the full pipeline (record → edit → export), and verify end-to-end functionality.

## Prerequisites

All of these branches must be complete and passing their individual checklists:
- `task-1-capture-engine`
- `task-2-project-bundle`
- `task-3-compositor`
- `task-4-app-setup-ui`
- `task-5-editor-ui`

## Merge Order

Merge in this order to minimize conflict complexity:

```
main (with Task 0 foundation)
  │
  ├── merge task-2-project-bundle     # Models/storage first (no deps on others)
  ├── merge task-1-capture-engine     # Engine writes to ProjectBundle format
  ├── merge task-3-compositor         # Reads ProjectBundle, uses EditSettings
  ├── merge task-4-app-setup-ui       # App shell, references CaptureEngine
  └── merge task-5-editor-ui          # Editor, references Compositor
```

Since all tasks write to completely separate files, merges should be conflict-free. If conflicts arise, they'll be in shared files (unlikely given task boundaries) — resolve by keeping the most complete version.

## Integration Wiring

After all branches are merged, the following connections need to be made:

### 1. Replace MockCaptureEngine with real CaptureEngine

**File**: `Reco/App/AppState.swift`

- Remove `MockCaptureEngine` class
- Import and instantiate real `CaptureEngine` from `Engine/`
- Wire `startRecording()` to pass `RecordingConfig` and output directory
- Wire `stopRecording()` to receive project bundle URL and transition to `.editing`
- Pass the RecordingPanel's `CGWindowID` to `CaptureEngine` for exclusion

### 2. Replace MockCompositor with real Compositor

**File**: `Reco/Views/Editor/EditorState.swift`

- Remove `MockCompositor` class
- Import and instantiate real `Compositor` from `Engine/`
- Wire `updatePreview()` to call `compositor.renderPreviewFrame()`
- Wire `export()` to call `compositor.export()`

### 3. Wire ProjectBundle into Editor

**File**: `Reco/Views/Editor/EditorState.swift`

- On editor init, open `ProjectBundle` from the project URL
- Load `EditSettings` from the bundle
- Save `EditSettings` back to bundle when user changes settings (debounced)
- Load `CursorData` for preview rendering
- Use `ProjectBundle.screenURL` for thumbnail generation

### 4. Wire ProjectBundle into CaptureEngine

**File**: `Reco/Engine/CaptureEngine.swift` (if needed)

- Verify CaptureEngine output matches ProjectBundle's expected file names
- Ensure `metadata.json` is written on recording stop
- Align `cursor.json` format between CursorTracker and ProjectBundle's `CursorData`

### 5. Connect RecoApp phase routing

**File**: `Reco/App/RecoApp.swift`

- Replace editor placeholder `Text("Editor — Task 5")` with actual `EditorView`
- Pass `projectURL` from `AppState.phase.editing` to `EditorState`
- Add "New Recording" action in editor to return to setup phase

### 6. Wire RecordingPanel window exclusion

- When recording starts, get `RecordingPanelController.panel.windowNumber`
- Pass it to `CaptureEngine.addExcludedWindow()` (or via `ScreenRecorder`)
- Verify the panel does NOT appear in recorded video

### 7. Bundled Wallpapers

**Directory**: `Reco/Resources/Wallpapers/`

- Add 6-8 wallpaper images (use royalty-free / CC0 images, or generate simple abstract backgrounds)
- Ensure `BackgroundRenderer` can load them by name
- Ensure `BackgroundPanel` shows thumbnails of available wallpapers

## Testing Protocol

### Smoke Test (must pass)
1. Launch app → SetupView appears
2. Select Screen Only mode, Full Screen, Original resolution
3. Enable system audio, disable camera and mic
4. Click "Screen Recording" → RecordingPanel appears
5. Wait 10 seconds → click Stop
6. Editor appears with recording loaded
7. Scrub timeline → preview updates
8. Change background to solid blue → preview shows blue background
9. Export as MP4 → file is created and playable

### Full Feature Test
- [ ] Record with camera enabled → camera.mov exists in bundle
- [ ] Record with mic enabled → audio-mic.caf exists in bundle
- [ ] RecordingPanel is NOT visible in the recorded video
- [ ] Pause and resume during recording → output is continuous
- [ ] Discard recording → returns to setup, files cleaned up
- [ ] Timeline thumbnails load from screen.mov
- [ ] Split video at a point → two segments visible
- [ ] Delete a segment → segment removed, timeline updates
- [ ] Trim start/end → export respects trim points
- [ ] Background: wallpaper preset applied in export
- [ ] Background: gradient applied in export
- [ ] Background: solid color applied in export
- [ ] Background: custom image applied in export
- [ ] Corner radius visible in export
- [ ] Shadow visible in export
- [ ] Screen size scaling visible in export
- [ ] Cursor: visible at correct positions in export
- [ ] Cursor: size scaling applied
- [ ] Cursor: touch effect on clicks (if enabled)
- [ ] Cursor: hidden when toggle is off
- [ ] Camera: overlay visible at correct position in export
- [ ] Camera: shape mask applied (circle, rect, etc.)
- [ ] Camera: position changes reflect in export
- [ ] Camera: hidden when toggle is off
- [ ] Audio present in exported file
- [ ] Export progress bar updates accurately
- [ ] Export can be cancelled
- [ ] Exported MP4 plays in QuickTime without issues

### Performance Test
- [ ] 60-second recording at native resolution: no dropped frames
- [ ] Editor preview renders in < 200ms on settings change
- [ ] Export of 60-second 1080p video completes in < 2 minutes
- [ ] App memory usage stays under 500MB during recording
- [ ] App memory usage stays under 1GB during export

## What NOT to Do
- Do not refactor or restructure code from individual tasks unless required for integration
- Do not add new features beyond what's specified in Tasks 1-5
- Do not optimize prematurely — get it working first

## Checklist

- [ ] All 5 branches merged without unresolved conflicts
- [ ] All mock implementations removed and replaced with real ones
- [ ] Project compiles with zero warnings
- [ ] Smoke test passes completely
- [ ] Full feature test: all items checked
- [ ] Performance test: all items within acceptable bounds
- [ ] No leftover `.gitkeep` files in directories that now have real files
- [ ] `CLAUDE.md` is up to date with any changes discovered during integration
- [ ] Commit message: `feat: integrate all modules into working end-to-end application`
