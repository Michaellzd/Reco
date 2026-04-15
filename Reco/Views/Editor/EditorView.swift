import SwiftUI

/// Main editor layout: top bar, center split (video preview + settings panel), and bottom timeline.
/// Registers keyboard shortcuts for playback, stepping, and split.
struct EditorView: View {
    @State var editorState: EditorState
    private let onNewRecording: (() -> Void)?

    init(projectURL: URL, duration: TimeInterval = 0, onNewRecording: (() -> Void)? = nil) {
        _editorState = State(initialValue: EditorState(projectURL: projectURL, duration: duration))
        self.onNewRecording = onNewRecording
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar

            HSplitView {
                VideoPreview(editorState: editorState)
                    .frame(minWidth: 400)
                    .layoutPriority(1)

                SettingsPanel(editorState: editorState)
                    .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
            }
            TimelineView(editorState: editorState)
        }
        .frame(minWidth: 900, minHeight: 600)
        .background(Color.recoCanvas)
        .tint(.recoAccent)
        .focusable()
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
        .onKeyPress(.delete) {
            editorState.deleteSelectedSegment()
            return .handled
        }
        .onKeyPress(phases: [.down]) { keyPress in
            switch (keyPress.key, keyPress.modifiers) {
            case (.leftArrow, [.command]):
                editorState.jumpToStart()
                return .handled
            case (.rightArrow, [.command]):
                editorState.jumpToEnd()
                return .handled
            case (_, _) where keyPress.characters == "s":
                editorState.splitAtPlayhead()
                return .handled
            case (_, _) where keyPress.characters == "S" && keyPress.modifiers == [.command, .shift]:
                editorState.splitAtPlayhead()
                return .handled
            default:
                return .ignored
            }
        }
        .sheet(isPresented: $editorState.showExportSheet) {
            ExportView(editorState: editorState)
        }
    }

    // MARK: - Top Bar

    private var topBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 12) {
                RecoBrandMark(size: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Editor")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Text(editorState.projectURL.lastPathComponent)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .lineLimit(1)
                }
            }

            if let onNewRecording {
                Button("New Recording") {
                    onNewRecording()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Spacer()

            HStack(spacing: 4) {
                Text("FPS")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
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
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Capsule().fill(Color.white.opacity(0.84)))

            Button {
                editorState.editSettings.camera.hidden.toggle()
                editorState.settingsDidChange()
            } label: {
                Image(systemName: editorState.editSettings.camera.hidden ? "video.slash" : "video")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.84)))
            }
            .buttonStyle(.plain)
            .help("Toggle camera visibility")

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
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Color.white.opacity(0.78))
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
