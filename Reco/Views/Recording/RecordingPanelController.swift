import AppKit
import SwiftUI

/// Manages the floating NSPanel that hosts the recording controls.
/// The panel does not steal focus and floats above all windows.
final class RecordingPanelController {
    private var panel: NSPanel?
    private let appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    /// The CGWindowID of the panel, used to exclude it from screen capture.
    var windowID: CGWindowID? {
        guard let panel else { return nil }
        return CGWindowID(panel.windowNumber)
    }

    /// Shows the recording panel on screen.
    func showPanel() {
        guard panel == nil else { return }

        let hostingView = NSHostingView(rootView: RecordingPanel(appState: appState))
        hostingView.frame = NSRect(x: 0, y: 0, width: 180, height: 300)

        let newPanel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 180, height: 300),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )

        newPanel.level = .floating
        newPanel.isFloatingPanel = true
        newPanel.hidesOnDeactivate = false
        newPanel.isOpaque = false
        newPanel.backgroundColor = .clear
        newPanel.hasShadow = true
        newPanel.isMovableByWindowBackground = true
        newPanel.isReleasedWhenClosed = false
        newPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Title bar configuration
        newPanel.titleVisibility = .hidden
        newPanel.titlebarAppearsTransparent = true

        newPanel.contentView = hostingView

        // Position in top-right corner of main screen
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let x = screenFrame.maxX - 180 - 20
            let y = screenFrame.maxY - 300 - 20
            newPanel.setFrameOrigin(NSPoint(x: x, y: y))
        }

        newPanel.orderFrontRegardless()
        panel = newPanel
    }

    /// Hides and releases the recording panel.
    func hidePanel() {
        panel?.close()
        panel = nil
    }
}
