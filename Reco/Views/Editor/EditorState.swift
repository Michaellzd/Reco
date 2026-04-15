import Foundation
import CoreGraphics
import CoreMedia
import SwiftUI
import AVFoundation

// MARK: - Editor State

@Observable
@MainActor
final class EditorState {
    // MARK: - Project

    var projectURL: URL
    var duration: TimeInterval

    // MARK: - Playback

    var currentTime: TimeInterval = 0
    var isPlaying: Bool = false

    // MARK: - Settings

    var editSettings: EditSettings = .init()

    // MARK: - Timeline

    var zoomLevel: Double = 1.0
    var splitPoints: [TimeInterval] = []
    var selectedSegmentIndex: Int?
    var trimStart: TimeInterval = 0
    var trimEnd: TimeInterval

    // MARK: - Export

    var isExporting: Bool = false
    var exportProgress: Double = 0
    var exportTask: Task<Void, Error>?
    var showExportSheet: Bool = false
    var exportComplete: Bool = false

    // MARK: - Preview

    var previewImage: CGImage?

    // MARK: - Thumbnails

    var thumbnails: [CGImage] = []
    var thumbnailInterval: TimeInterval = 2.0

    // MARK: - Dependencies

    private let compositor: CompositorProtocol
    private var projectBundle: ProjectBundle?

    // MARK: - Playback Timer

    private var playbackTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?

    /// Debounce timer for saving settings
    private var saveSettingsTask: Task<Void, Never>?

    // MARK: - Init

    init(
        projectURL: URL,
        duration: TimeInterval = 0,
        compositor: CompositorProtocol = Compositor()
    ) {
        self.projectURL = projectURL
        self.duration = duration
        self.trimEnd = duration
        self.compositor = compositor

        // Load project bundle data
        loadProjectBundle()
    }

    // MARK: - Project Bundle Loading

    private func loadProjectBundle() {
        do {
            let bundle = try ProjectBundle.open(at: projectURL)
            self.projectBundle = bundle
            self.editSettings = bundle.editSettings
            self.duration = bundle.metadata.duration
            self.trimEnd = bundle.metadata.duration

            // If duration is 0 (not yet set in metadata), try to read from the screen.mov asset
            if duration <= 0 {
                loadDurationFromAsset()
            }
        } catch {
            print("[EditorState] Failed to open project bundle: \(error). Using defaults.")
            // Fall back to reading duration from screen.mov directly
            loadDurationFromAsset()
        }
    }

    private func loadDurationFromAsset() {
        let screenURL = projectURL.appendingPathComponent("screen.mov")
        guard FileManager.default.fileExists(atPath: screenURL.path) else { return }
        let asset = AVURLAsset(url: screenURL)
        let assetDuration = CMTimeGetSeconds(asset.duration)
        if assetDuration > 0 {
            self.duration = assetDuration
            self.trimEnd = assetDuration
        }
    }

    // MARK: - Preview

    func updatePreview() async {
        previewTask?.cancel()
        let time = CMTime(seconds: currentTime, preferredTimescale: 600)
        do {
            let image = try await compositor.renderPreviewFrame(
                projectURL: projectURL,
                settings: editSettings,
                at: time
            )
            self.previewImage = image
        } catch {
            // In mock mode, errors are not critical
            print("Preview render error: \(error)")
        }
    }

    func schedulePreviewUpdate(delay: Duration = .milliseconds(60)) {
        previewTask?.cancel()
        previewTask = Task { [weak self] in
            if delay > .zero {
                try? await Task.sleep(for: delay)
            }
            guard let self, !Task.isCancelled else { return }
            await self.updatePreview()
        }
    }

    // MARK: - Playback

    func play() {
        guard !isPlaying else { return }
        isPlaying = true
        let fps = Double(editSettings.fps)
        let frameInterval = 1.0 / fps

        playbackTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.isPlaying else { break }
                self.currentTime += frameInterval
                if self.currentTime >= self.trimEnd {
                    self.currentTime = self.trimEnd
                    self.pause()
                    break
                }
                try? await Task.sleep(for: .milliseconds(Int(frameInterval * 1000)))
            }
        }
    }

    func pause() {
        isPlaying = false
        playbackTask?.cancel()
        playbackTask = nil
        schedulePreviewUpdate(delay: .zero)
    }

    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func seekTo(_ time: TimeInterval) {
        let clamped = max(trimStart, min(time, trimEnd))
        currentTime = clamped
        if !isPlaying {
            schedulePreviewUpdate(delay: .milliseconds(40))
        }
    }

    func stepForward() {
        let frameTime = 1.0 / Double(editSettings.fps)
        seekTo(currentTime + frameTime)
    }

    func stepBackward() {
        let frameTime = 1.0 / Double(editSettings.fps)
        seekTo(currentTime - frameTime)
    }

    func jumpToStart() {
        seekTo(trimStart)
    }

    func jumpToEnd() {
        seekTo(trimEnd)
    }

    // MARK: - Timeline Editing

    func splitAtPlayhead() {
        guard currentTime > trimStart, currentTime < trimEnd else { return }
        // Don't add duplicate split points
        if splitPoints.contains(where: { abs($0 - currentTime) < 0.01 }) { return }
        splitPoints.append(currentTime)
        splitPoints.sort()
    }

    func deleteSelectedSegment() {
        guard let index = selectedSegmentIndex else { return }
        let boundaries = segmentBoundaries
        guard index < boundaries.count - 1 else { return }

        let start = boundaries[index]
        let end = boundaries[index + 1]
        editSettings.deletedSegments.append(TrimRange(startTime: start, endTime: end))

        // Remove the split points that bounded this segment (if they're not trim start/end)
        if index > 0 {
            splitPoints.removeAll { abs($0 - start) < 0.01 }
        }
        if index < boundaries.count - 2 {
            splitPoints.removeAll { abs($0 - end) < 0.01 }
        }

        selectedSegmentIndex = nil
    }

    /// Returns all segment boundaries: [trimStart, splitPoint1, splitPoint2, ..., trimEnd]
    var segmentBoundaries: [TimeInterval] {
        let boundaries = [trimStart] + splitPoints.filter { $0 > trimStart && $0 < trimEnd } + [trimEnd]
        return boundaries.sorted()
    }

    var segmentCount: Int {
        return max(segmentBoundaries.count - 1, 0)
    }

    func isSegmentDeleted(index: Int) -> Bool {
        let boundaries = segmentBoundaries
        guard index < boundaries.count - 1 else { return false }
        let start = boundaries[index]
        let end = boundaries[index + 1]
        return editSettings.deletedSegments.contains { seg in
            abs(seg.startTime - start) < 0.01 && abs(seg.endTime - end) < 0.01
        }
    }

    // MARK: - Thumbnails

    func generateThumbnails() async {
        let screenMovURL = projectURL.appendingPathComponent("screen.mov")
        let fileExists = FileManager.default.fileExists(atPath: screenMovURL.path)

        if fileExists {
            await generateThumbnailsFromAsset(url: screenMovURL)
        } else {
            generatePlaceholderThumbnails()
        }
    }

    private func generateThumbnailsFromAsset(url: URL) async {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 160, height: 90)

        let maxThumbnailCount = 48
        let effectiveInterval = max(thumbnailInterval, duration / Double(maxThumbnailCount))
        let count = max(Int(ceil(duration / effectiveInterval)), 1)
        var images: [CGImage] = []

        for i in 0..<count {
            let time = CMTime(seconds: Double(i) * effectiveInterval, preferredTimescale: 600)
            do {
                let (image, _) = try await generator.image(at: time)
                images.append(image)
            } catch {
                // Use placeholder on failure
                if let placeholder = createPlaceholderThumbnail() {
                    images.append(placeholder)
                }
            }
        }

        self.thumbnails = images
    }

    private func generatePlaceholderThumbnails() {
        let count = max(Int(duration / thumbnailInterval), 1)
        var images: [CGImage] = []
        for _ in 0..<min(count, 200) { // Cap at 200 thumbnails for mock mode
            if let img = createPlaceholderThumbnail() {
                images.append(img)
            }
        }
        self.thumbnails = images
    }

    private func createPlaceholderThumbnail() -> CGImage? {
        let w = 160, h = 90
        guard let ctx = CGContext(
            data: nil, width: w, height: h,
            bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        ctx.setFillColor(CGColor(red: 0.25, green: 0.25, blue: 0.28, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(CGColor(red: 0.35, green: 0.35, blue: 0.38, alpha: 1))
        ctx.fill(CGRect(x: 10, y: 10, width: w - 20, height: h - 20))
        return ctx.makeImage()
    }

    // MARK: - Export

    func export(
        format: ExportFormat = .mp4,
        resolution: ExportResolution = .original,
        fps: Int = 60,
        outputURL: URL
    ) async throws {
        isExporting = true
        exportProgress = 0
        exportComplete = false

        // Update FPS in settings
        editSettings.fps = fps

        // Build trim ranges (segments to keep)
        rebuildTrimRanges()

        do {
            try await compositor.export(
                projectURL: projectURL,
                settings: editSettings,
                outputURL: outputURL,
                format: format,
                resolution: resolution,
                progress: { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.exportProgress = progress
                    }
                }
            )
            isExporting = false
            exportTask = nil
            exportComplete = true
        } catch {
            isExporting = false
            exportTask = nil
            throw error
        }
    }

    func cancelExport() {
        exportTask?.cancel()
        exportTask = nil
        isExporting = false
        exportComplete = false
        exportProgress = 0
    }

    private func rebuildTrimRanges() {
        let boundaries = segmentBoundaries
        var keepRanges: [TrimRange] = []
        for i in 0..<(boundaries.count - 1) {
            if !isSegmentDeleted(index: i) {
                keepRanges.append(TrimRange(startTime: boundaries[i], endTime: boundaries[i + 1]))
            }
        }
        editSettings.trimRanges = keepRanges
    }

    // MARK: - Settings Change Handler

    func settingsDidChange() {
        if !isPlaying {
            schedulePreviewUpdate()
        }
        // Debounced save to project bundle
        saveSettingsTask?.cancel()
        saveSettingsTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self.projectBundle?.editSettings = self.editSettings
            try? self.projectBundle?.saveEditSettings()
        }
    }
}

// MARK: - Export Types

enum ExportFormat: String, CaseIterable, Identifiable {
    case mp4 = "MP4 (H.264)"
    case hevc = "HEVC"
    case proRes = "ProRes"

    var id: String { rawValue }
}

enum ExportResolution: String, CaseIterable, Identifiable {
    case original = "Original"
    case p1080 = "1080p"
    case p720 = "720p"
    case p4K = "4K"

    var id: String { rawValue }
}
