import SwiftUI

/// Main editor layout: top bar, center split (video preview + settings panel), and bottom timeline.
/// Registers keyboard shortcuts for playback, stepping, and split.
struct EditorView: View {
    @State var editorState: EditorState

    init(projectURL: URL, duration: TimeInterval = 57 * 60 + 31) {
        _editorState = State(initialValue: EditorState(projectURL: projectURL, duration: duration))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar
            topBar

            Divider()

            // Center: HSplitView with preview (left ~70%) and settings (right ~30%)
            HSplitView {
                VideoPreview(editorState: editorState)
                    .frame(minWidth: 400)
                    .layoutPriority(1)

                SettingsPanel(editorState: editorState)
                    .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
            }

            Divider()

            // Bottom: Timeline
            TimelineView(editorState: editorState)
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        // Keyboard shortcuts
        .onKeyPress(.space) {
            editorState.togglePlayback()
            return .handled
        }
        .onKeyPress(.leftArrow) {
            editorState.stepBackward()
            return .handled
        }
        .onKeyPress(.rightArrow) {
            editorState.stepForward()
            return .handled
        }
        .onKeyPress(.leftArrow, modifiers: .command) {
            editorState.jumpToStart()
            return .handled
        }
        .onKeyPress(.rightArrow, modifiers: .command) {
            editorState.jumpToEnd()
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "s")) {
            editorState.splitAtPlayhead()
            return .handled
        }
        .onKeyPress(characters: CharacterSet(charactersIn: "S"), modifiers: [.command, .shift]) {
            editorState.splitAtPlayhead()
            return .handled
        }
        .onKeyPress(.delete) {
            editorState.deleteSelectedSegment()
            return .handled
        }
        .sheet(isPresented: $editorState.showExportSheet) {
            ExportView(editorState: editorState)
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 12) {
            // Filename
            Text(editorState.projectURL.lastPathComponent)
                .font(.headline)
                .lineLimit(1)

            Spacer()

            // FPS selector
            HStack(spacing: 4) {
                Text("FPS")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: Binding(
                    get: { editorState.editSettings.fps },
                    set: {
                        editorState.editSettings.fps = $0
                        editorState.settingsDidChange()
                    }
                )) {
                    Text("30").tag(30)
                    Text("60").tag(60)
                }
                .pickerStyle(.menu)
                .fixedSize()
                .labelsHidden()
            }

            // Camera toggle shortcut
            Button {
                editorState.editSettings.camera.hidden.toggle()
                editorState.settingsDidChange()
            } label: {
                Image(systemName: editorState.editSettings.camera.hidden ? "video.slash" : "video")
                    .font(.body)
            }
            .buttonStyle(.plain)
            .help("Toggle camera visibility")

            // Export button
            Button {
                editorState.showExportSheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Export")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Editor View") {
    EditorView(
        projectURL: URL(fileURLWithPath: "/tmp/test.reco"),
        duration: 120
    )
}
#endif
