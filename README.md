# Reco

A free, open-source macOS screen recording app that turns raw screen captures into polished presentation videos.

## Why Reco?

Recording a presentation on macOS shouldn't require a separate video editor. Reco combines screen recording, camera overlay, and post-recording beautification in a single workflow:

**Record** → **Edit** → **Export**

No subscriptions. No telemetry. No cloud accounts.

## Features

### Record
- Screen capture (full screen or custom area)
- Camera overlay (webcam)
- System audio + microphone
- Multi-screen support
- Floating control panel (invisible in recording)

### Edit
- **Background**: Wallpaper presets, gradients, solid colors, or custom images
- **Cursor**: Show/hide, resize, click effects (touch ripple)
- **Camera**: Shape, size, position (9-point grid), corner radius
- **Video**: Shadow, corner radius, scaling within background
- **Timeline**: Trim, split, delete segments, zoom

### Export
- MP4 (H.264), HEVC, or ProRes output
- Configurable resolution and FPS

## Requirements

- macOS 14 Sonoma or later
- Xcode 15+ (for building from source)

## Building from Source

```bash
git clone https://github.com/your-username/reco.git
cd reco
open Reco.xcodeproj
```

Build and run from Xcode (Cmd+R).

## How It Works

Reco records screen, camera, audio, and cursor data as **separate tracks**. Nothing is baked together during recording. This means you can change backgrounds, reposition the camera, adjust cursor effects, and re-export — all without re-recording.

```
Screen stream  ─┐
Camera stream  ─┤
Audio streams  ─┼── .reco project bundle ──► Editor ──► Compositor ──► Final MP4
Cursor data    ─┘
```

## Project Status

**Early development** — not yet usable. See `docs/` for architecture and feature planning.

## Tech Stack

- Swift + SwiftUI
- ScreenCaptureKit (screen capture)
- AVFoundation (camera, audio, video encoding)
- CoreImage + Metal (compositing)
- Zero third-party dependencies

## Documentation

- [Project Overview](docs/overview.md)
- [Feature Specification](docs/features.md)
- [Architecture](docs/architecture.md)
- [Technical Decisions](docs/tech-decisions.md)
- Task Documents: [`docs/tasks/`](docs/tasks/)
  - [Task 0: Foundation & Scaffold](docs/tasks/task-0-foundation.md)
  - [Task 1: Capture Engine](docs/tasks/task-1-capture-engine.md)
  - [Task 2: Project Bundle & Storage](docs/tasks/task-2-project-bundle.md)
  - [Task 3: Compositor & Renderer](docs/tasks/task-3-compositor.md)
  - [Task 4: App State, Setup & Recording UI](docs/tasks/task-4-app-and-setup-ui.md)
  - [Task 5: Editor UI](docs/tasks/task-5-editor-ui.md)
  - [Task 6: Integration & Final Merge](docs/tasks/task-6-integration-merge.md)

## Contributing

Contributions welcome. Please read the architecture docs before starting work — the project follows a strict "engine first, UI second" development order.

## License

MIT
