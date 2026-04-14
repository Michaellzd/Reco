> **Requires**: Run in a dedicated worktree (`--worktree task-1-capture-engine` on branch `task-1-capture-engine`). Branch from `main` AFTER Task 0 has been merged.

# Task 1: Capture Engine

## Objective

Implement the screen capture, camera capture, audio capture, and cursor tracking engine. This is the core recording pipeline — it must reliably produce separate track files without dropping frames.

## Scope — Files to Create/Modify

**Create:**
```
Reco/Engine/CaptureEngine.swift      # Main capture orchestrator
Reco/Engine/ScreenRecorder.swift     # ScreenCaptureKit stream handler
Reco/Engine/CameraRecorder.swift     # AVCaptureSession for webcam
Reco/Engine/AudioRecorder.swift      # Mic + system audio capture
Reco/Engine/CursorTracker.swift      # Cursor position & click logging
```

**Do NOT touch:**
- Anything in `Views/`, `App/`, `Models/`, `Protocols/`, `Resources/`
- `RecordingConfig.swift`, `EditSettings.swift` — use them as-is from Task 0
- `CaptureEngineProtocol.swift` — conform to it, do not modify it

## Context

### Key Frameworks
- **ScreenCaptureKit** (`SCStream`, `SCStreamOutput`, `SCShareableContent`, `SCContentFilter`)
  - Use `SCContentFilter` with `excludingWindows` to exclude the recording control panel
  - The control panel's `CGWindowID` will be passed in at recording start time
  - `SCStream` provides both video frames (`CMSampleBuffer`) and audio buffers
  - Cursor position is available via `SCStreamFrameInfo` metadata on each frame
- **AVFoundation** (`AVCaptureSession`, `AVCaptureDeviceInput`, `AVAssetWriter`)
  - Camera capture: `AVCaptureSession` → `AVCaptureVideoDataOutput` → `AVAssetWriter`
  - Audio from ScreenCaptureKit for system audio, `AVCaptureSession` for mic

### Recording Pipeline
```
ScreenCaptureKit SCStream
  ├── Video frames → AVAssetWriter → screen.mov
  ├── System audio → AVAssetWriter → audio-system.caf
  └── Frame metadata → CursorTracker → cursor.json

AVCaptureSession (camera)
  └── Video frames → AVAssetWriter → camera.mov

AVCaptureSession (microphone)
  └── Audio buffers → AVAssetWriter → audio-mic.caf
```

### Output Files (written to the project bundle directory)
- `screen.mov` — H.264 encoded screen capture, no cursor baked in
- `camera.mov` — H.264 encoded webcam feed (only if camera enabled)
- `audio-mic.caf` — AAC encoded microphone audio (only if mic enabled)
- `audio-system.caf` — AAC encoded system audio (only if enabled)
- `cursor.json` — Array of cursor events with timestamps

### Cursor Data Format
```json
{
  "events": [
    {
      "timestamp": 0.0,
      "x": 512.0,
      "y": 384.0,
      "visible": true,
      "clicked": false
    },
    {
      "timestamp": 0.033,
      "x": 515.0,
      "y": 380.0,
      "visible": true,
      "clicked": true
    }
  ],
  "screenWidth": 1920,
  "screenHeight": 1080
}
```

## Detailed Requirements

### CaptureEngine.swift
- Conforms to `CaptureEngineProtocol`
- Use `@Observable` class (or Actor for thread safety)
- Orchestrates all sub-recorders
- `startRecording(config:outputDirectory:)`:
  1. Create project bundle directory (named `Recording-YYYY-MM-DD-HH-MM-SS.reco`)
  2. Query `SCShareableContent` for available displays
  3. Build `SCContentFilter` for the selected display/area, excluding provided window IDs
  4. Start `SCStream` for screen + system audio
  5. Start `AVCaptureSession` for camera (if enabled)
  6. Start `AVCaptureSession` for microphone (if enabled)
  7. Start `CursorTracker`
- `pauseRecording()`: Pause all writers (stop appending buffers, track pause duration)
- `resumeRecording()`: Resume appending with adjusted timestamps
- `stopRecording()`: Stop all streams/sessions, finalize all writers, return bundle URL
- `discardRecording()`: Stop all streams, delete the bundle directory

### ScreenRecorder.swift
- Wraps `SCStream` setup and delegate handling
- Implements `SCStreamOutput` to receive video and audio sample buffers
- Configures stream for requested resolution and frame rate
- Handles the `excludedWindows` list via a public method: `addExcludedWindow(_ windowID: CGWindowID)`

### CameraRecorder.swift
- Wraps `AVCaptureSession` for the default or selected camera
- Writes to `camera.mov` via `AVAssetWriter`
- Must handle camera not available gracefully (no crash)

### AudioRecorder.swift
- Handles microphone capture via `AVCaptureSession`
- System audio comes from `SCStream` audio output — route it to a separate `AVAssetWriter`
- Writes mic audio to `audio-mic.caf`, system audio to `audio-system.caf`

### CursorTracker.swift
- Extracts cursor position from `SCStreamFrameInfo` metadata on each captured frame
- Also monitors `NSEvent.addGlobalMonitorForEvents` for click events (mouseDown/mouseUp)
- Accumulates events in memory, writes `cursor.json` on stop
- Must be lightweight — no blocking I/O during recording

### Thread Safety
- Screen/camera/audio callbacks come on different queues
- Each `AVAssetWriter` must only be accessed from its designated serial queue
- Use `DispatchQueue` per writer or Swift actors to avoid data races

### Error Handling
- Permission denied → throw descriptive error (caller shows alert)
- Device disconnected mid-recording → log warning, continue other streams
- Disk full → stop recording gracefully, save what we have

## What NOT to Do
- Do not bake cursor rendering into the screen recording frames
- Do not composite camera onto screen during recording
- Do not modify any files outside `Reco/Engine/`
- Do not add UI code
- Do not add third-party dependencies

## Checklist

- [ ] `CaptureEngine` conforms to `CaptureEngineProtocol`
- [ ] Screen recording produces valid `screen.mov` playable in QuickTime
- [ ] Camera recording produces valid `camera.mov` (when camera enabled)
- [ ] Microphone audio produces valid `audio-mic.caf` (when mic enabled)
- [ ] System audio produces valid `audio-system.caf` (when enabled)
- [ ] Cursor tracking produces valid `cursor.json` with position + click data
- [ ] Recording can be paused and resumed without corruption
- [ ] Recording can be discarded (files cleaned up)
- [ ] A specific window can be excluded from screen capture
- [ ] No frame drops during 60-second test recording at native resolution
- [ ] Handles missing camera/mic gracefully (no crash)
- [ ] All capture callbacks are thread-safe
- [ ] Project builds with no warnings
- [ ] Commit message: `feat: implement capture engine with multi-track recording`
