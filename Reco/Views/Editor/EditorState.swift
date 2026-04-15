import Foundation
import CoreGraphics
import CoreMedia
import SwiftUI
import AVFoundation

// MARK: - Mock Compositor

/// A mock compositor for development. Returns placeholder images and simulates export progress.
/// Will be replaced by the real Compositor when Task 3 merges.
final class MockCompositor: CompositorProtocol {
    func renderPreviewFrame(
        projectURL: URL,
        settings: EditSettings,
        at time: CMTime
    ) async throws -> CGImage {
        // Create a placeholder colored rectangle
        let width = 1280
        let height = 720
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw MockCompositorError.cannotCreateContext
        }

        // Draw background based on settings
        let bgColor: CGColor
        switch settings.background.type {
        case .solidColor:
            bgColor = NSColor(hex: settings.background.solidColor)?.cgColor
                ?? CGColor(red: 0.15, green: 0.15, blue: 0.2, alpha: 1)
        case .gradient:
            bgColor = CGColor(red: 0.1, green: 0.1, blue: 0.3, alpha: 1)
        case .wallpaper:
            bgColor = CGColor(red: 0.2, green: 0.3, blue: 0.4, alpha: 1)
        case .customImage:
            bgColor = CGColor(red: 0.3, green: 0.2, blue: 0.3, alpha: 1)
        }

        context.setFillColor(bgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Draw a "screen" rectangle in the center
        let scale = settings.background.screenScale / 100.0
        let screenW = Double(width) * scale * 0.8
        let screenH = Double(height) * scale * 0.8
        let screenX = (Double(width) - screenW) / 2
        let screenY = (Double(height) - screenH) / 2
        let radius = settings.background.cornerRadius

        let screenRect = CGRect(x: screenX, y: screenY, width: screenW, height: screenH)
        let path = CGPath(roundedRect: screenRect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        context.setFillColor(CGColor(red: 0.3, green: 0.3, blue: 0.35, alpha: 1))
        context.addPath(path)
        context.fillPath()

        // Draw camera circle if not hidden
        if !settings.camera.hidden {
            let camSize = min(Double(width), Double(height)) * settings.camera.size / 100.0
            let camX: Double
            let camY: Double
            switch settings.camera.position {
            case .topLeft: camX = 20; camY = Double(height) - camSize - 20
            case .topCenter: camX = (Double(width) - camSize) / 2; camY = Double(height) - camSize - 20
            case .topRight: camX = Double(width) - camSize - 20; camY = Double(height) - camSize - 20
            case .middleLeft: camX = 20; camY = (Double(height) - camSize) / 2
            case .middleCenter: camX = (Double(width) - camSize) / 2; camY = (Double(height) - camSize) / 2
            case .middleRight: camX = Double(width) - camSize - 20; camY = (Double(height) - camSize) / 2
            case .bottomLeft: camX = 20; camY = 20
            case .bottomCenter: camX = (Double(width) - camSize) / 2; camY = 20
            case .bottomRight: camX = Double(width) - camSize - 20; camY = 20
            }
            context.setFillColor(CGColor(red: 0.5, green: 0.6, blue: 0.7, alpha: 0.8))
            if settings.camera.shape == .circle {
                context.fillEllipse(in: CGRect(x: camX, y: camY, width: camSize, height: camSize))
            } else {
                let camRect = CGRect(x: camX, y: camY, width: camSize, height: camSize)
                let camPath = CGPath(
                    roundedRect: camRect,
                    cornerWidth: settings.camera.cornerRadius,
                    cornerHeight: settings.camera.cornerRadius,
                    transform: nil
                )
                context.addPath(camPath)
                context.fillPath()
            }
        }

        // Draw playhead time indicator text area
        let seconds = CMTimeGetSeconds(time)
        let timeStr = String(format: "%.1fs", seconds)
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.7))
        context.fill(CGRect(x: Double(width) / 2 - 30, y: Double(height) / 2 - 10, width: 60, height: 20))

        guard let image = context.makeImage() else {
            throw MockCompositorError.cannotCreateImage
        }
        return image
    }

    func export(
        projectURL: URL,
        settings: EditSettings,
        outputURL: URL,
        progress: @escaping (Double) -> Void
    ) async throws {
        // Simulate export over ~3 seconds
        let steps = 30
        for i in 0...steps {
            try Task.checkCancellation()
            progress(Double(i) / Double(steps))
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    enum MockCompositorError: Error {
        case cannotCreateContext
        case cannotCreateImage
    }
}

// MARK: - NSColor Hex Extension (for mock)

private extension NSColor {
    convenience init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        guard hexSanitized.count == 6,
              let hexNumber = UInt64(hexSanitized, radix: 16) else {
            return nil
        }

        let r = CGFloat((hexNumber & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((hexNumber & 0x00FF00) >> 8) / 255.0
        let b = CGFloat(hexNumber & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b, alpha: 1.0)
    }
}

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

    // MARK: - Playback Timer

    private var playbackTask: Task<Void, Never>?

    // MARK: - Init

    init(
        projectURL: URL,
        duration: TimeInterval = 57 * 60 + 31, // Default mock: 57:31
        compositor: CompositorProtocol = MockCompositor()
    ) {
        self.projectURL = projectURL
        self.duration = duration
        self.trimEnd = duration
        self.compositor = compositor
    }

    // MARK: - Preview

    func updatePreview() async {
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
        Task { await updatePreview() }
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
            Task { await updatePreview() }
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
        var boundaries = [trimStart] + splitPoints.filter { $0 > trimStart && $0 < trimEnd } + [trimEnd]
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

        let count = Int(duration / thumbnailInterval)
        var images: [CGImage] = []

        for i in 0..<count {
            let time = CMTime(seconds: Double(i) * thumbnailInterval, preferredTimescale: 600)
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
                progress: { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.exportProgress = progress
                    }
                }
            )
            exportComplete = true
        } catch {
            isExporting = false
            throw error
        }
    }

    func cancelExport() {
        exportTask?.cancel()
        exportTask = nil
        isExporting = false
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
            Task { await updatePreview() }
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
