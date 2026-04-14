import Foundation
import AppKit
import ScreenCaptureKit

// MARK: - Cursor Data Models

struct CursorEvent: Codable {
    let timestamp: TimeInterval
    let x: Double
    let y: Double
    let visible: Bool
    let clicked: Bool
}

struct CursorData: Codable {
    var events: [CursorEvent] = []
    var screenWidth: Int
    var screenHeight: Int
}

// MARK: - CursorTracker

/// Tracks cursor position from SCStream frame metadata and click events via NSEvent monitors.
/// Accumulates events in memory and writes cursor.json on stop.
final class CursorTracker: @unchecked Sendable {

    private let queue = DispatchQueue(label: "com.reco.cursorTracker", qos: .utility)
    private var events: [CursorEvent] = []
    private var screenWidth: Int = 0
    private var screenHeight: Int = 0
    private var startTime: CMTime = .zero
    private var clickMonitor: Any?
    private var clickUpMonitor: Any?
    private var isClicked: Bool = false
    private var outputURL: URL?

    // MARK: - Lifecycle

    func start(screenWidth: Int, screenHeight: Int, startTime: CMTime, outputURL: URL) {
        queue.sync {
            self.events.removeAll()
            self.screenWidth = screenWidth
            self.screenHeight = screenHeight
            self.startTime = startTime
            self.outputURL = outputURL
            self.isClicked = false
        }
        startClickMonitoring()
    }

    func stop() {
        stopClickMonitoring()
        writeToDisk()
    }

    // MARK: - Frame Metadata Processing

    /// Called from ScreenRecorder's SCStreamOutput callback with frame info.
    /// Extracts cursor position from the sample buffer's attachments.
    func processSampleBuffer(_ sampleBuffer: CMSampleBuffer) {
        guard let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]] else {
            return
        }

        // Extract cursor info from ScreenCaptureKit frame metadata
        guard let attachments = attachmentsArray.first else { return }

        // Get presentation timestamp relative to recording start
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let timestamp = CMTimeGetSeconds(pts) - CMTimeGetSeconds(startTime)
        guard timestamp >= 0 else { return }

        // Get cursor position from NSEvent (ScreenCaptureKit doesn't expose cursor in attachments directly)
        let mouseLocation = NSEvent.mouseLocation
        let clicked = isClicked

        let event = CursorEvent(
            timestamp: timestamp,
            x: mouseLocation.x,
            y: Double(screenHeight) - mouseLocation.y, // Flip Y coordinate (AppKit uses bottom-left origin)
            visible: true,
            clicked: clicked
        )

        queue.async { [weak self] in
            self?.events.append(event)
        }
    }

    // MARK: - Click Monitoring

    private func startClickMonitoring() {
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.queue.async {
                self?.isClicked = true
            }
        }
        clickUpMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp]) { [weak self] _ in
            self?.queue.async {
                self?.isClicked = false
            }
        }
    }

    private func stopClickMonitoring() {
        if let monitor = clickMonitor {
            NSEvent.removeMonitor(monitor)
            clickMonitor = nil
        }
        if let monitor = clickUpMonitor {
            NSEvent.removeMonitor(monitor)
            clickUpMonitor = nil
        }
    }

    // MARK: - Persistence

    private func writeToDisk() {
        queue.sync {
            guard let outputURL = self.outputURL else { return }
            let cursorData = CursorData(
                events: self.events,
                screenWidth: self.screenWidth,
                screenHeight: self.screenHeight
            )
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(cursorData)
                try data.write(to: outputURL)
            } catch {
                print("[CursorTracker] Failed to write cursor.json: \(error)")
            }
        }
    }
}
