import Foundation
import CoreImage
import AppKit

// CursorEvent and CursorData are defined in ProjectBundle.swift (canonical source)

// MARK: - Cursor Renderer

/// Renders cursor overlay images for the compositor pipeline.
/// Handles cursor positioning, sizing, click ripple effects, and rotation.
final class CursorRenderer {

    // MARK: - Properties

    private var cursorData: CursorData?
    private var cursorImage: CIImage?

    // MARK: - Public API

    /// Load cursor events from a cursor.json file.
    func loadCursorData(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        cursorData = try decoder.decode(CursorData.self, from: data)
    }

    /// Set cursor data directly (for testing or when data is already loaded).
    func setCursorData(_ data: CursorData) {
        self.cursorData = data
    }

    /// Render cursor overlay at the given timestamp.
    /// Returns nil if cursor is hidden or no data is available.
    func renderCursor(
        at timestamp: Double,
        config: CursorConfig,
        recordingSize: CGSize,
        outputSize: CGSize,
        screenRect: CGRect  // The rect where the screen frame is placed in output
    ) -> CIImage? {
        guard !config.hidden else { return nil }
        guard let cursorData = cursorData, !cursorData.events.isEmpty else { return nil }

        // Find interpolated position at timestamp
        let position = interpolatedPosition(at: timestamp, events: cursorData.events)
        let isClick = isClickActive(at: timestamp, events: cursorData.events)

        // Map recording coordinates to output coordinates
        let effectiveRecordingSize = cursorData.recordingSize ?? recordingSize
        let scaleX = screenRect.width / effectiveRecordingSize.width
        let scaleY = screenRect.height / effectiveRecordingSize.height
        let outputX = screenRect.origin.x + position.x * scaleX
        let outputY = screenRect.origin.y + position.y * scaleY

        // Get or create cursor image
        let cursor = getCursorImage(size: config.size)
        let cursorSize = cursor.extent.size

        // Calculate rotation based on movement direction
        let rotation = calculateRotation(
            at: timestamp,
            events: cursorData.events,
            intensity: config.rotationIntensity
        )

        // Apply rotation
        var renderedCursor = cursor
        if abs(rotation) > 0.001 {
            let rotationTransform = CGAffineTransform(rotationAngle: CGFloat(rotation))
            renderedCursor = renderedCursor.transformed(by: rotationTransform)
        }

        // Position cursor (tip of arrow at the point)
        let translatedCursor = renderedCursor.transformed(
            by: CGAffineTransform(
                translationX: outputX - renderedCursor.extent.origin.x,
                y: outputY - renderedCursor.extent.origin.y - cursorSize.height
            )
        )

        // Composite click effect if active
        if isClick && config.style == .touch {
            let ripple = renderClickRipple(
                at: CGPoint(x: outputX, y: outputY),
                timestamp: timestamp,
                events: cursorData.events
            )
            // Ripple behind cursor
            let composited = ripple.composited(over: CIImage.empty())
            let withCursor = translatedCursor.composited(over: composited)
            return withCursor.cropped(to: CGRect(origin: .zero, size: outputSize))
        }

        return translatedCursor.cropped(to: CGRect(origin: .zero, size: outputSize))
    }

    // MARK: - Private Helpers

    /// Get or create a cursor image scaled to the given size multiplier.
    private func getCursorImage(size: Double) -> CIImage {
        if let cached = cursorImage {
            // Re-scale from base if size changed
            let scale = CGFloat(size)
            return cached.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        }

        // Use system arrow cursor image
        let nsImage = NSCursor.arrow.image
        guard let tiffData = nsImage.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let cgImage = bitmap.cgImage else {
            // Fallback: render a small white triangle
            let fallback = renderFallbackCursor()
            cursorImage = fallback
            return fallback.transformed(
                by: CGAffineTransform(scaleX: CGFloat(size), y: CGFloat(size))
            )
        }

        let ciImage = CIImage(cgImage: cgImage)
        cursorImage = ciImage
        return ciImage.transformed(
            by: CGAffineTransform(scaleX: CGFloat(size), y: CGFloat(size))
        )
    }

    /// Render a fallback cursor (white triangle) if system cursor is unavailable.
    private func renderFallbackCursor() -> CIImage {
        let size: CGFloat = 24
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: Int(size),
            height: Int(size),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
        }

        // Draw a simple arrow shape
        context.setFillColor(CGColor.white)
        context.setStrokeColor(CGColor.black)
        context.setLineWidth(1)
        context.move(to: CGPoint(x: 4, y: size - 2))
        context.addLine(to: CGPoint(x: 4, y: 2))
        context.addLine(to: CGPoint(x: size - 6, y: size / 2))
        context.closePath()
        context.drawPath(using: .fillStroke)

        guard let cgImage = context.makeImage() else {
            return CIImage(color: .white).cropped(to: CGRect(x: 0, y: 0, width: size, height: size))
        }

        return CIImage(cgImage: cgImage)
    }

    /// Interpolate cursor position between the two nearest events.
    private func interpolatedPosition(at timestamp: Double, events: [CursorEvent]) -> CGPoint {
        guard !events.isEmpty else { return .zero }

        // Before first event
        if timestamp <= events[0].timestamp {
            return CGPoint(x: events[0].x, y: events[0].y)
        }

        // After last event
        if timestamp >= events[events.count - 1].timestamp {
            let last = events[events.count - 1]
            return CGPoint(x: last.x, y: last.y)
        }

        // Binary search for surrounding events
        var low = 0
        var high = events.count - 1
        while low < high - 1 {
            let mid = (low + high) / 2
            if events[mid].timestamp <= timestamp {
                low = mid
            } else {
                high = mid
            }
        }

        let before = events[low]
        let after = events[high]
        let dt = after.timestamp - before.timestamp
        guard dt > 0 else {
            return CGPoint(x: before.x, y: before.y)
        }

        let t = (timestamp - before.timestamp) / dt
        let x = before.x + (after.x - before.x) * t
        let y = before.y + (after.y - before.y) * t
        return CGPoint(x: x, y: y)
    }

    /// Check if a click is active at the given timestamp.
    private func isClickActive(at timestamp: Double, events: [CursorEvent]) -> Bool {
        // Find the most recent event at or before timestamp
        var lastClick = false
        for event in events {
            if event.timestamp > timestamp { break }
            lastClick = event.isClick
        }
        return lastClick
    }

    /// Calculate cursor rotation based on movement direction.
    private func calculateRotation(at timestamp: Double, events: [CursorEvent], intensity: Double) -> Double {
        guard intensity > 0, events.count >= 2 else { return 0 }

        let lookback: Double = 0.05  // 50ms window
        let posBefore = interpolatedPosition(at: timestamp - lookback, events: events)
        let posNow = interpolatedPosition(at: timestamp, events: events)

        let dx = posNow.x - posBefore.x
        let dy = posNow.y - posBefore.y

        // Rotation proportional to horizontal movement, clamped
        let maxRotation = 0.3  // ~17 degrees max
        let rotation = (dx / 100.0) * intensity * maxRotation
        return max(-maxRotation, min(maxRotation, rotation))
    }

    /// Render a radial ripple effect at the click position.
    private func renderClickRipple(at point: CGPoint, timestamp: Double, events: [CursorEvent]) -> CIImage {
        // Find when the click started
        var clickStartTime = timestamp
        for event in events.reversed() {
            if event.timestamp > timestamp { continue }
            if event.clickPhase == .began {
                clickStartTime = event.timestamp
                break
            }
        }

        let elapsed = timestamp - clickStartTime
        let maxDuration: Double = 0.4
        let progress = min(elapsed / maxDuration, 1.0)

        // Ripple expands and fades
        let baseRadius: CGFloat = 20
        let radius = baseRadius + CGFloat(progress) * 30
        let alpha = CGFloat(1.0 - progress) * 0.5

        // Create a radial gradient for the ripple
        guard let radialFilter = CIFilter(name: "CIRadialGradient") else {
            return CIImage.empty()
        }

        let rippleColor = CIColor(red: 0.4, green: 0.6, blue: 1.0, alpha: alpha)
        let clearColor = CIColor(red: 0.4, green: 0.6, blue: 1.0, alpha: 0)

        radialFilter.setValue(CIVector(x: point.x, y: point.y), forKey: "inputCenter")
        radialFilter.setValue(radius * 0.3, forKey: "inputRadius0")
        radialFilter.setValue(radius, forKey: "inputRadius1")
        radialFilter.setValue(rippleColor, forKey: "inputColor0")
        radialFilter.setValue(clearColor, forKey: "inputColor1")

        return radialFilter.outputImage ?? CIImage.empty()
    }
}
