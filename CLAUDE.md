# Reco - Claude Code Instructions

## Project Overview

Reco is an open-source macOS screen recording app (Swift + SwiftUI) that captures screen, camera, audio, and cursor data as separate tracks, then composites them into polished videos with customizable backgrounds, cursor effects, and camera overlays.

## Architecture

- **Engine Layer** (highest priority): CaptureEngine, CursorTracker, ProjectBundle, Compositor
- **State Layer**: AppState with Swift Observation (`@Observable`)
- **UI Layer**: SwiftUI views for Setup, Recording (NSPanel), and Editor phases

See `docs/architecture.md` for full details.

## Tech Stack

- Swift + SwiftUI (macOS 14+)
- ScreenCaptureKit for screen capture
- AVFoundation for camera/audio capture and video encoding
- CoreImage + Metal for compositing
- No third-party dependencies in MVP

## Key Conventions

### Code Style
- Follow Swift API Design Guidelines
- Use Swift concurrency (async/await, actors) for capture pipelines
- Use `@Observable` for state management, not Combine
- Keep ViewModels thin — business logic belongs in the Engine layer

### File Organization
```
Reco/
  App/          — Entry point, app state
  Engine/       — Capture, compositing, project management (core logic)
  Views/        — SwiftUI views organized by phase (Setup, Recording, Editor)
  Models/       — Data models and configurations
  Resources/    — Bundled assets (wallpapers, etc.)
```

### Project Bundle Format
Each recording produces a `.reco` directory:
```
Recording-YYYY-MM-DD-HH-MM-SS.reco/
  screen.mov, camera.mov, audio-mic.caf, audio-system.caf
  cursor.json, project.json
```

### Development Priorities
1. **Harness engineering first** — recording pipeline and compositing engine must work before UI polish
2. Engine layer is testable independently of UI
3. Each capture stream (screen, camera, audio, cursor) is independent
4. Composition happens at export time, never during recording

### What NOT to Do
- Do not bake camera/cursor into the screen recording during capture
- Do not use AVMutableComposition for effects — use CoreImage pipeline
- Do not add third-party dependencies without discussion
- Do not build real-time preview playback for MVP — on-demand frame preview is sufficient

## Task Workflow

Development is split into isolated tasks under `docs/tasks/`. Each task runs in its own git worktree on a dedicated branch.

### Execution Order
```
Task 0 (Foundation) → merge to main
    │
    ├── Task 1 (Capture Engine)      ─┐
    ├── Task 2 (Project Bundle)       ├── All parallel, all branch from main after Task 0
    ├── Task 3 (Compositor)           │
    ├── Task 4 (App + Setup + Panel)  │
    └── Task 5 (Editor UI)           ─┘
                                      │
                                      ▼
                              Task 6 (Integration & Merge)
```

### Rules
- Each task only touches files listed in its scope — never modify files owned by another task
- Tasks 1-5 use mock/stub implementations for cross-module dependencies
- Task 6 replaces all mocks with real implementations and wires everything together
- Each task's first line specifies its required worktree and branch name

## Building & Running

```bash
# Open in Xcode
open Reco.xcodeproj

# Build from command line
xcodebuild -scheme Reco -configuration Debug build

# Run tests
xcodebuild -scheme Reco -configuration Debug test
```

## Useful Commands

```bash
# Check Swift formatting
swift format --recursive Reco/

# List ScreenCaptureKit available content (for debugging)
# Use SCShareableContent.current in a test or playground
```
