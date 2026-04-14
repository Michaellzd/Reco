> **Requires**: Run in a dedicated worktree (`--worktree task-3-compositor` on branch `task-3-compositor`). Branch from `main` AFTER Task 0 has been merged.

# Task 3: Compositor & Renderer

## Objective

Implement the video compositor that reads a `.reco` project bundle and produces the final composited video with background, cursor effects, camera overlay, and trimming applied.

## Scope — Files to Create/Modify

**Create:**
```
Reco/Engine/Compositor.swift             # Main compositor orchestrator
Reco/Engine/FrameRenderer.swift          # Single-frame compositing via CoreImage
Reco/Engine/CursorRenderer.swift         # Cursor overlay rendering
Reco/Engine/CameraRenderer.swift         # Camera overlay with shape masking
Reco/Engine/BackgroundRenderer.swift     # Background layer rendering
```

**Do NOT touch:**
- Anything in `Views/`, `App/`, `Models/`, `Protocols/`, `Resources/`
- Other `Engine/` files (CaptureEngine, ProjectBundle, etc.)

## Context

### Compositing Pipeline (per frame)

```
Layer 0 (bottom):  Background (wallpaper / gradient / solid / custom image)
Layer 1:           Screen recording frame (scaled, rounded corners, shadow)
Layer 2:           Cursor overlay (sized, styled, with click effects)
Layer 3 (top):     Camera overlay (shaped, positioned, sized)
```

Each layer is rendered using CoreImage, then composited bottom-to-top.

### Key Frameworks
- **AVAssetReader**: Read video/audio frames from .mov/.caf files
- **CoreImage** (`CIContext`, `CIFilter`, `CIImage`): GPU-accelerated image compositing
- **AVAssetWriter**: Write composited frames + mixed audio to output file
- **CoreMedia** (`CMTime`, `CMSampleBuffer`): Frame timing

### Export Flow
```
AVAssetReader (screen.mov) ──► frames
AVAssetReader (camera.mov) ──► frames    ──► FrameRenderer ──► AVAssetWriter ──► output.mp4
cursor.json ──► CursorRenderer               (per frame)
EditSettings ──► BackgroundRenderer
AVAssetReader (audio tracks) ──────────────────────────────► AVAssetWriter (audio)
```

## Detailed Requirements

### Compositor.swift
- Conforms to `CompositorProtocol`
- Orchestrates the full export pipeline

**`renderPreviewFrame(projectURL:settings:at:)`**
- Reads a single frame from `screen.mov` at the given time
- Composites it with background, cursor, camera at that moment
- Returns a `CGImage` for display in the editor preview
- Must be fast (< 100ms) for responsive scrubbing

**`export(projectURL:settings:outputURL:progress:)`**
- Reads all tracks frame-by-frame
- Applies trimming (skip deleted segments, based on `EditSettings.trimRanges` / `deletedSegments`)
- Composites each frame through the pipeline
- Mixes audio tracks (mic + system audio)
- Encodes to output format (H.264 MP4 default)
- Reports progress (0.0 to 1.0) via callback
- Runs on a background queue, supports cancellation via Swift Task

### FrameRenderer.swift
The per-frame compositing engine using CoreImage.

```swift
class FrameRenderer {
    private let ciContext: CIContext  // Reuse across frames for performance

    func renderFrame(
        screenFrame: CIImage,
        cursorOverlay: CIImage?,
        cameraFrame: CIImage?,
        settings: EditSettings,
        outputSize: CGSize
    ) -> CIImage
}
```

Pipeline per frame:
1. Create background `CIImage` (from BackgroundRenderer)
2. Scale screen frame to `settings.background.screenScale`%
3. Apply corner radius to screen frame (CIFilter: `CIRoundedRectangleGenerator` as mask, or manual clip)
4. Apply drop shadow (CIFilter: `CIShadow` or manual gaussian blur of silhouette)
5. Composite screen on background (CIFilter: `CISourceOverCompositing`)
6. Composite cursor overlay on top
7. Composite camera overlay on top
8. Return final `CIImage`

### BackgroundRenderer.swift
Generates background `CIImage` for a given size.

- **Solid color**: `CIImage(color:)` with extent
- **Gradient**: `CILinearGradient` filter with configurable colors and angle
- **Wallpaper**: Load from bundled `Resources/Wallpapers/` by name, scale to fit
- **Custom image**: Load from path in project bundle, scale to fit

Cache the background image across frames (it doesn't change frame-to-frame).

### CursorRenderer.swift
Renders cursor overlay for a given frame.

- Read cursor position from `CursorData` at the current frame timestamp (interpolate between nearest events)
- Scale cursor position from recording coordinates to output coordinates
- If `settings.cursor.hidden`: return nil
- Apply cursor size scaling
- Render cursor image (use system default cursor image via `NSCursor.arrow.image`)
- If `settings.cursor.style == .touch` and click is active: render a radial ripple effect at click position
- Apply rotation intensity (slight tilt based on cursor movement direction)

### CameraRenderer.swift
Renders camera overlay for a given frame.

- Read camera frame at current timestamp from `camera.mov`
- If `settings.camera.hidden`: return nil
- Apply shape mask:
  - `.circle`: Circular clip
  - `.roundedRect`, `.roundedRectWide`, `.squareRounded`, `.square`: Various rect clips with corner radius
- Scale to `settings.camera.size`% of output frame
- Position according to `settings.camera.position` (9-point grid mapped to actual coordinates with padding)
- Apply corner radius from settings
- Return composited `CIImage`

### Audio Mixing
- Read audio buffers from `audio-mic.caf` and `audio-system.caf` via `AVAssetReader`
- Mix into a single stereo audio track
- Write mixed audio alongside video frames in `AVAssetWriter`
- Apply trim ranges — skip audio segments that correspond to deleted video segments

### Trimming Logic
- `EditSettings.trimRanges` defines segments to KEEP
- If `trimRanges` is empty, keep everything
- When reading frames, check if current timestamp falls within a kept range
- Remap output timestamps to be continuous (no gaps from deleted segments)

### Performance
- Reuse `CIContext` across all frames (creating one per frame is extremely slow)
- Use `CIContext(options: [.useSoftwareRenderer: false])` to force GPU
- Background image should be rendered once and cached
- Camera frame reading should be synchronized with screen frame timestamps
- Target: export 1080p 60fps video at >= 30fps processing speed (2x realtime)

## What NOT to Do
- Do not modify any shared types or protocols
- Do not implement UI
- Do not read/write `project.json` (that's ProjectBundle's job — receive settings as parameter)
- Do not add third-party dependencies (no FFmpeg)

## Checklist

- [ ] `Compositor` conforms to `CompositorProtocol`
- [ ] `renderPreviewFrame` returns a valid `CGImage` in < 100ms
- [ ] Export produces a valid MP4 playable in QuickTime
- [ ] Background renders correctly for all 4 types (solid, gradient, wallpaper, custom)
- [ ] Screen frame has correct corner radius and shadow in output
- [ ] Screen frame is correctly scaled within background
- [ ] Cursor appears at correct positions matching `cursor.json` data
- [ ] Cursor size setting is applied
- [ ] Cursor click effect (touch ripple) renders on click events
- [ ] Camera overlay renders with correct shape and size
- [ ] Camera position matches the 9-point grid selection
- [ ] Audio is present in export (both mic and system when available)
- [ ] Trim/split is respected — deleted segments are excluded from output
- [ ] Output timestamps are continuous after trimming (no jumps)
- [ ] Export progress callback reports accurate 0.0-1.0 values
- [ ] Export can be cancelled via Task cancellation
- [ ] No memory leaks (frames are released after processing)
- [ ] Project builds with no warnings
- [ ] Commit message: `feat: implement compositor with background, cursor, and camera rendering`
