# Reco - Technical Decisions

## Tech Stack

| Component | Choice | Rationale |
|-----------|--------|-----------|
| Language | Swift | Native macOS, best performance for video processing |
| UI Framework | SwiftUI | Modern declarative UI, good for settings panels and controls |
| Screen Capture | ScreenCaptureKit | Apple's dedicated framework; supports window exclusion, cursor data, system audio |
| Camera/Audio | AVFoundation | Mature framework for camera capture and audio recording |
| Video Compositing | CoreImage + Metal | GPU-accelerated frame processing for effects (shadow, corner radius, background) |
| Video Encoding | AVAssetWriter | Hardware-accelerated H.264/HEVC/ProRes encoding |
| State Management | Swift Observation (`@Observable`) | Lightweight, built-in, no dependencies needed |
| Minimum macOS | 14 Sonoma | ScreenCaptureKit v3 with best API surface; covers ~80% of active Macs |

## Key Technical Decisions

### 1. Multi-track recording over baked-in composition

**Decision**: Record screen, camera, audio, and cursor data as separate tracks. Compose only at export time.

**Why**:
- Maximum editing flexibility after recording
- Users can re-export with different settings without re-recording
- Cursor effects (size, click highlight) can be applied retroactively
- Simpler recording pipeline — each stream is independent

**Trade-off**: Larger project files on disk (multiple streams stored). Acceptable for a desktop app.

### 2. NSPanel for recording controls

**Decision**: Use `NSPanel` (not a regular `NSWindow` or SwiftUI overlay) for the floating recording controls.

**Why**:
- `NSPanel` with `.nonactivatingPanel` behavior doesn't steal focus from the user's active app
- Has its own `CGWindowID` → easily excluded via `SCContentFilter.excludingWindows`
- Can be set to `.floating` window level to stay above all other windows
- Standard macOS pattern for tool palettes and inspectors

### 3. On-demand preview in editor (MVP)

**Decision**: For MVP, the editor preview renders a static composite frame when settings change. Full playback shows raw screen recording only.

**Why**:
- Real-time compositing during playback requires a GPU rendering pipeline with synchronized multi-track playback
- This is significant engineering effort for a feature that's "nice to have"
- Users can scrub to any point and see the composite preview; they just can't play back with all effects in real-time
- Export always produces the fully composited result

**Future**: Build real-time preview as a post-MVP enhancement using Metal render pipeline.

### 4. Project bundle format (directory, not single file)

**Decision**: Each recording is a directory (`.reco` bundle) containing individual files.

**Why**:
- Easy to inspect and debug during development
- Individual streams can be read/written independently
- No need for a custom container format
- macOS treats directory bundles as single items in Finder (with proper UTI registration)

### 5. CoreImage + Metal for compositing (not AVComposition)

**Decision**: Use CoreImage filters and Metal shaders for frame-by-frame compositing rather than AVFoundation's built-in `AVMutableComposition`.

**Why**:
- `AVMutableComposition` is designed for simple track-based editing (trim, concat), not for the kind of effects Reco needs (arbitrary backgrounds, cursor overlays, camera shape masking, shadows)
- CoreImage provides compositing filters (overlay, shadow, round rect masking) out of the box
- Metal shaders give us full control for custom effects if needed
- Frame-by-frame processing through AVAssetReader → CoreImage pipeline → AVAssetWriter is a well-proven pattern

### 6. No third-party dependencies (MVP)

**Decision**: Build MVP with Apple frameworks only. No FFmpeg, no Electron, no third-party video libraries.

**Why**:
- Reduces build complexity and binary size
- Apple frameworks are optimized for macOS hardware (especially Apple Silicon)
- ScreenCaptureKit + AVFoundation + CoreImage cover all our needs
- Easier for contributors to build the project (just clone and open in Xcode)

**Exception**: If specific codec support or performance needs arise post-MVP, FFmpeg can be added as an optional dependency.

### 7. Open source (MIT license)

**Decision**: Fully open source under MIT license.

**Why**:
- Maximizes community adoption and contribution
- No commercial ambitions — this solves a personal pain point
- MIT is simple and permissive, no licensing complexity

## Performance Considerations

- **Recording**: Must not drop frames. Capture engine writes directly to disk via AVAssetWriter with hardware encoding. No processing during recording.
- **Cursor tracking**: Lightweight — just logging coordinates and click events to JSON. Negligible overhead.
- **Export compositing**: Can be slow (frame-by-frame GPU processing). Show progress bar. Target: export time should be ≤ 2x recording duration for 1080p.
- **Memory**: Don't load entire video into memory. Use AVAssetReader for sequential frame access during export.
