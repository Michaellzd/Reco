import SwiftUI

/// Right-side settings panel with tab switching.
/// Tabs: Background, Cursor, Camera, Audio (placeholder).
struct SettingsPanel: View {
    @Bindable var editorState: EditorState
    @State private var selectedTab: SettingsTab = .background

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar
            HStack(spacing: 0) {
                ForEach(SettingsTab.allCases) { tab in
                    tabButton(tab)
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 8)

            Divider()
                .padding(.top, 4)

            // Tab content
            switch selectedTab {
            case .background:
                BackgroundPanel(editorState: editorState)
            case .cursor:
                CursorPanel(editorState: editorState)
            case .camera:
                CameraPanel(editorState: editorState)
            case .audio:
                audioPlaceholder
            }
        }
        .frame(minWidth: 240)
    }

    // MARK: - Tab Button

    private func tabButton(_ tab: SettingsTab) -> some View {
        let isSelected = selectedTab == tab

        return Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: tab.iconName)
                    .font(.system(size: 16))
                Text(tab.label)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .foregroundStyle(isSelected ? .primary : .secondary)
    }

    // MARK: - Audio Placeholder

    private var audioPlaceholder: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "speaker.wave.2")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("Audio Settings")
                .font(.headline)
                .foregroundStyle(.secondary)

            // Volume slider placeholder
            VStack(alignment: .leading, spacing: 4) {
                Text("Volume")
                    .font(.caption)
                Slider(value: .constant(0.8), in: 0...1)
            }
            .padding(.horizontal, 24)

            Text("Full audio controls coming soon")
                .font(.caption)
                .foregroundStyle(.tertiary)

            Spacer()
        }
        .padding()
    }
}

// MARK: - Settings Tab Enum

enum SettingsTab: String, CaseIterable, Identifiable {
    case background
    case cursor
    case camera
    case audio

    var id: String { rawValue }

    var label: String {
        switch self {
        case .background: "BG"
        case .cursor: "Cursor"
        case .camera: "Camera"
        case .audio: "Audio"
        }
    }

    var iconName: String {
        switch self {
        case .background: "rectangle.inset.filled"
        case .cursor: "cursorarrow"
        case .camera: "camera"
        case .audio: "speaker.wave.2"
        }
    }
}
