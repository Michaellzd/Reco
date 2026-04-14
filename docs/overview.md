# Reco - Project Overview

## What is Reco?

Reco is a free, open-source macOS screen recording application designed for creating polished presentation recordings with minimal effort. It bridges the gap between raw screen capture and professional-looking video output — without requiring a separate video editor.

## Problem

Recording a presentation on macOS today is painful:

1. Built-in screen recording (Screenshot.app / QuickTime) gives you a raw, unpolished `.mov` file
2. Making it look good (background, camera overlay, cursor highlights) requires importing into a video editor
3. Existing tools that do this well (Screen Studio, DemoGet) are paid and closed-source

## Solution

Reco provides a three-phase workflow in a single app:

**Phase 1: Record Setup** — Configure recording mode, screen/area selection, resolution, camera, and audio sources. One click to start.

**Phase 2: Recording** — A floating control panel (excluded from capture) with stop, pause, timer, and discard controls.

**Phase 3: Edit & Export** — A post-recording editor for video beautification (background, cursor styling, camera overlay, shadow/corner radius) with basic timeline trimming, then export.

## Core Principle

**Harness engineering first.** The recording and compositing pipeline must be rock-solid before any UI polish. A beautiful UI on top of a broken recording engine is worthless.

## Target User

- Developers recording demos, tutorials, or presentations
- Content creators who want polished screen recordings without complex video editors
- Anyone who needs "Screen Studio quality" without the price tag

## Scope (MVP)

- macOS 14+ only (leverages ScreenCaptureKit v3)
- Single-app workflow: record → edit → export
- No cloud features, no accounts, no telemetry
- Fully open-source (MIT license)
