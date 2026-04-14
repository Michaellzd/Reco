# Reco - Feature Specification

## Phase 1: Record Setup

The main window that appears when the app is launched.

### Record Mode
- **Portrait + Screen**: Records screen with camera overlay embedded
- **Screen Only**: Records screen without camera

### Screen Selection
- Dropdown to select which display (Screen1, Screen2, etc.)
- **Full Screen**: Captures the entire selected display
- **Custom Area**: User drags to select a rectangular region

### Resolution Selection
- **Original**: Native resolution of the selected screen/area
- Common presets: 1080p, 720p, 4K (downscaled from native)

### Audio/Video Sources (Record Section)
- **Camera**: Select camera device or disable
- **Microphone**: Select mic input or disable
- **System Audio**: Capture system audio output (Yes/No)

### Start Recording
- Single prominent button: "Screen Recording"
- Triggers permission prompts on first use (Screen Recording, Camera, Microphone)

---

## Phase 2: Recording Controls

A floating panel visible to the user but **excluded from the screen capture** (achieved via ScreenCaptureKit's content filter).

### Controls
- **Stop**: End recording, transition to editor (Phase 3)
- **Pause / Resume**: Temporarily pause capture
- **Timer**: Displays elapsed recording time (HH:MM:SS)
- **Delete**: Discard current recording and return to Phase 1

### Technical Requirement
- The control panel window must be added to ScreenCaptureKit's `excludedWindows` list so it never appears in the captured video
- Panel should be always-on-top and draggable

---

## Phase 3: Edit & Export

Post-recording editor for video beautification and basic trimming.

### 3.1 Timeline & Basic Editing
- Visual waveform/thumbnail timeline at the bottom
- **Trim**: Drag handles at start/end to trim
- **Split**: Hold modifier key (e.g., Control) + click to split at playhead position
- **Delete segment**: Select a split segment and delete it
- **Playback controls**: Play, pause, skip forward/back, scrub
- **Zoom**: Pinch or scroll to zoom in/out on timeline for precision editing
- FPS display and adjustment (e.g., 30 FPS, 60 FPS)

### 3.2 Background Settings
Right-side panel, tab-based:

- **Wallpaper**: Preset backgrounds (macOS-style dynamic wallpapers, abstract patterns)
- **Gradient**: Configurable gradient backgrounds (two-color picker + angle)
- **Color**: Solid color picker
- **Custom**: Upload custom image as background

Related controls:
- **Shadow Size**: Slider (0-100%) — drop shadow behind the screen recording
- **Shadow Opacity**: Slider (0-100%)
- **Shadow Blur**: Slider (0-100%)
- **Corner Radius**: Slider — rounds the corners of the screen recording
- **Screen Size**: Slider — scale the recording within the background (allows background to show around edges)

### 3.3 Cursor Settings
- **Hide Cursor**: Toggle to completely remove cursor from export
- **Cursor Size**: Slider (1.0x - 5.0x) to enlarge cursor for visibility
- **Cursor Custom**: Style options
  - **None**: No special effect
  - **Touch**: Adds a click/touch ripple effect on mouse clicks
- **Rotation Intensity**: Slider — subtle cursor rotation animation on movement (for visual flair)

### 3.4 Camera Settings
- **Hide Camera**: Toggle to remove camera overlay from export
- **Camera Size**: Slider (10% - 50% of video frame)
- **Follow Video Zoom**: Toggle — camera overlay follows zoom/pan if applied
- **Corner Radius**: Slider for camera overlay corner rounding
- **Shape**: Preset shapes
  - Circle
  - Rounded rectangle (various aspect ratios)
  - Hidden (X button)
- **Camera Position**: 3x3 grid (9 positions) — click a position, preview updates live on the left

### 3.5 Export
- Export button (top-right)
- Output format: MP4 (H.264) as default, with option for ProRes or HEVC
- Resolution selection for export
- Export progress indicator

---

## Future Considerations (Post-MVP)
These are NOT in scope for MVP but worth noting:

- Zoom/pan effects (auto-zoom on click areas)
- Annotations (arrows, text overlays, highlights)
- Keyboard shortcut overlay display
- Auto-caption / subtitle generation
- Preset export profiles (for YouTube, Twitter, etc.)
- Audio editing (noise reduction, volume adjustment)
