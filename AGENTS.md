# Reco Agent Guide

## Purpose

Reco is a native macOS app for recording screen, camera, audio, and cursor as separate tracks, then exporting a composited presentation video.

The repo is organized around one pipeline:

1. `SetupView` configures a `RecordingConfig`
2. `AppState` starts `CaptureEngine`
3. `CaptureEngine` writes a `.reco` bundle to disk
4. `EditorState` opens that bundle and drives preview/export through `Compositor`

## Current Status

- As of `2026-04-15`, the project builds successfully from the integrated `main` branch.
- Verified build command:

```bash
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild \
  -project Reco.xcodeproj \
  -scheme Reco \
  -derivedDataPath .derived \
  build
```

- `xcode-select` may still point at CommandLineTools on this machine. Either switch it to Xcode.app or keep using the full Xcode binary path above.
- The next phase is manual runtime testing on macOS hardware with real permissions and capture devices.

## Repo Map

- `Reco/App/`
  - `RecoApp.swift`: phase routing between setup, recording, and editor
  - `AppState.swift`: top-level app state and recording lifecycle
  - `PermissionManager.swift`: screen/camera/microphone permission checks
- `Reco/Engine/`
  - `CaptureEngine.swift`: orchestrates screen, camera, mic, and cursor capture
  - `ScreenRecorder.swift`: ScreenCaptureKit stream + system audio
  - `CameraRecorder.swift`: webcam capture to `camera.mov`
  - `AudioRecorder.swift`: microphone capture to `audio-mic.caf`
  - `CursorTracker.swift`: cursor timeline persisted to `cursor.json`
  - `ProjectBundle.swift`: `.reco` bundle open/save/validate
  - `Compositor.swift`: preview rendering and export pipeline
  - `FrameRenderer.swift`, `BackgroundRenderer.swift`, `CursorRenderer.swift`, `CameraRenderer.swift`: per-layer compositing helpers
- `Reco/Views/Setup/`
  - recording configuration UI, display picker, custom-area selector
- `Reco/Views/Recording/`
  - floating `NSPanel` controls for stop/pause/discard
- `Reco/Views/Editor/`
  - preview, timeline, settings, export sheet, editor state
- `docs/`
  - planning, architecture, progress log, and task breakdown

## Important Flows

### Record

- `RecoApp` enters `.recording` and shows `RecordingPanelController`
- `AppState.startRecording()` passes the panel window ID into `CaptureEngine`
- `CaptureEngine` creates `Recording-*.reco/` under the temp `Reco` directory and starts:
  - `ScreenRecorder`
  - `CameraRecorder` if enabled
  - `AudioRecorder` if enabled
  - `CursorTracker`

### Edit

- `AppState.stopRecording()` transitions to `.editing(projectURL:)`
- `EditorState` opens the bundle with `ProjectBundle.open(at:)`
- Preview frames are rendered on demand through `Compositor.renderPreviewFrame(...)`
- Editor settings save back to `project.json`

### Export

- `ExportView` collects format, resolution, fps, and output URL
- `EditorState.export(...)` rebuilds trim ranges and calls `Compositor.export(...)`
- `Compositor` now applies:
  - selected codec/container
  - selected output resolution
  - trim timestamp remapping for video and audio

## Known Focus Areas For Testing

- Screen-only smoke test should be first.
- Then validate:
  - recording panel exclusion from capture
  - camera track creation and overlay export
  - microphone/system-audio export behavior
  - custom capture-area correctness
  - trim/split/delete behavior in exported output

## Known Caveats

- Manual runtime verification is still pending. A successful build does not guarantee ScreenCaptureKit/AVFoundation behavior on-device.
- There are still non-blocking build warnings around newer AVFoundation async-loading APIs and Sendable captures inside export closures.
- Multi-source audio export has been wired far enough for testing, but it still needs explicit real-device verification, especially when microphone and system audio are both enabled.

## Editing Rules

- Keep the engine layer stable first; avoid UI-only changes that bypass the real pipeline.
- Preserve the `.reco` bundle contract:
  - `screen.mov`
  - `camera.mov`
  - `audio-mic.caf`
  - `audio-system.caf`
  - `cursor.json`
  - `metadata.json`
  - `project.json`
- Prefer extending the existing engine/state/view split instead of introducing a second abstraction layer.
- If you change export or capture behavior, update `docs/progress.md` and leave the manual verification impact explicit.
