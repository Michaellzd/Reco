import SwiftUI
import AppKit

struct ScreenSelector: View {
    @Binding var config: RecordingConfig
    @Binding var showingAreaSelector: Bool

    @State private var screens: [NSScreen] = NSScreen.screens

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Display picker
            Picker("Display", selection: $config.displayID) {
                ForEach(Array(screens.enumerated()), id: \.element.displayID) { index, screen in
                    Text(displayName(for: screen, index: index))
                        .tag(screen.displayID)
                }
            }
            .labelsHidden()

            // Full Screen / Custom Area toggle
            HStack(spacing: 8) {
                Button {
                    config.captureArea = .fullScreen
                } label: {
                    HStack {
                        Image(systemName: "rectangle.dashed")
                        Text("Full Screen")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(AreaButtonStyle(isSelected: config.captureArea == .fullScreen))

                Button {
                    showingAreaSelector = true
                    openAreaSelector()
                } label: {
                    HStack {
                        Image(systemName: "crop")
                        Text("Custom Area")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(AreaButtonStyle(isSelected: isCustomArea))
            }

            // Show selected area dimensions if custom
            if case .custom(let rect) = config.captureArea {
                Text("Selected: \(Int(rect.width)) × \(Int(rect.height)) at (\(Int(rect.origin.x)), \(Int(rect.origin.y)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var isCustomArea: Bool {
        if case .custom = config.captureArea { return true }
        return false
    }

    private func displayName(for screen: NSScreen, index: Int) -> String {
        let name = screen.localizedName
        if screens.count == 1 {
            return name
        }
        return "\(name) (\(index + 1))"
    }

    private func openAreaSelector() {
        guard let screen = screens.first(where: { $0.displayID == config.displayID })
                ?? NSScreen.main else { return }

        let selectorWindow = AreaSelectorWindow(screen: screen) { rect in
            if let rect {
                config.captureArea = .custom(rect)
            }
            showingAreaSelector = false
        }
        selectorWindow.makeKeyAndOrderFront(nil)
    }
}

// MARK: - Area Button Style

struct AreaButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

// MARK: - NSScreen Extension

extension NSScreen {
    var displayID: CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return deviceDescription[key] as? CGDirectDisplayID ?? 0
    }
}

// MARK: - Area Selector Window

/// A transparent full-screen window that lets the user drag-select a rectangle.
class AreaSelectorWindow: NSWindow {
    private var onComplete: (CGRect?) -> Void
    private var selectionView: AreaSelectorView?

    init(screen: NSScreen, onComplete: @escaping (CGRect?) -> Void) {
        self.onComplete = onComplete
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        self.setFrame(screen.frame, display: false)
        self.level = .screenSaver
        self.isOpaque = false
        self.backgroundColor = NSColor.black.withAlphaComponent(0.2)
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.isReleasedWhenClosed = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = AreaSelectorView(frame: screen.frame, window: self, onComplete: { [weak self] rect in
            self?.close()
            onComplete(rect)
        })
        self.contentView = view
        self.selectionView = view
    }
}

class AreaSelectorView: NSView {
    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?
    private var onComplete: (CGRect?) -> Void
    private weak var parentWindow: NSWindow?
    private var dimensionLabel: NSTextField?

    init(frame: NSRect, window: NSWindow, onComplete: @escaping (CGRect?) -> Void) {
        self.onComplete = onComplete
        self.parentWindow = window
        super.init(frame: frame)

        let label = NSTextField(labelWithString: "")
        label.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .medium)
        label.textColor = .white
        label.backgroundColor = NSColor.black.withAlphaComponent(0.7)
        label.isBezeled = false
        label.drawsBackground = true
        label.isHidden = true
        label.sizeToFit()
        addSubview(label)
        dimensionLabel = label

        // Add instruction text
        let instruction = NSTextField(labelWithString: "Drag to select area. Press Escape to cancel.")
        instruction.font = NSFont.systemFont(ofSize: 16, weight: .medium)
        instruction.textColor = .white
        instruction.backgroundColor = NSColor.black.withAlphaComponent(0.6)
        instruction.isBezeled = false
        instruction.drawsBackground = true
        instruction.alignment = .center
        instruction.sizeToFit()
        instruction.frame.origin = NSPoint(
            x: (frame.width - instruction.frame.width) / 2,
            y: frame.height - instruction.frame.height - 40
        )
        addSubview(instruction)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        startPoint = convert(event.locationInWindow, from: nil)
        currentPoint = startPoint
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        updateDimensionLabel()
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let start = startPoint, let end = currentPoint else {
            onComplete(nil)
            return
        }
        let rect = rectFromPoints(start, end)
        if rect.width > 10 && rect.height > 10 {
            onComplete(rect)
        } else {
            onComplete(nil)
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Escape
            onComplete(nil)
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let start = startPoint, let current = currentPoint else { return }
        let rect = rectFromPoints(start, current)

        // Draw selection rectangle
        NSColor.systemBlue.withAlphaComponent(0.15).setFill()
        NSBezierPath(rect: rect).fill()

        NSColor.systemBlue.setStroke()
        let path = NSBezierPath(rect: rect)
        path.lineWidth = 2
        path.stroke()
    }

    private func rectFromPoints(_ a: NSPoint, _ b: NSPoint) -> CGRect {
        CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(a.x - b.x),
            height: abs(a.y - b.y)
        )
    }

    private func updateDimensionLabel() {
        guard let start = startPoint, let current = currentPoint, let label = dimensionLabel else { return }
        let rect = rectFromPoints(start, current)
        label.stringValue = " \(Int(rect.width)) × \(Int(rect.height)) "
        label.sizeToFit()
        label.frame.origin = NSPoint(x: rect.midX - label.frame.width / 2, y: rect.maxY + 4)
        label.isHidden = false
    }
}
