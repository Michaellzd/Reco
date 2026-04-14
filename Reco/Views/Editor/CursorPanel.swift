import SwiftUI

/// Cursor settings tab: hide toggle, size slider, cursor style selector,
/// and rotation intensity slider.
struct CursorPanel: View {
    @Bindable var editorState: EditorState

    private var cursor: Binding<CursorConfig> {
        Binding(
            get: { editorState.editSettings.cursor },
            set: {
                editorState.editSettings.cursor = $0
                editorState.settingsDidChange()
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Hide Cursor toggle
                Toggle("Hide Cursor", isOn: cursor.hidden)
                    .toggleStyle(.switch)

                // Cursor Size slider
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Cursor Size")
                            .font(.caption)
                        Spacer()
                        Text(String(format: "%.1fx", editorState.editSettings.cursor.size))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if abs(editorState.editSettings.cursor.size - 2.0) > 0.01 {
                            Button("Reset") {
                                editorState.editSettings.cursor.size = 2.0
                                editorState.settingsDidChange()
                            }
                            .font(.caption2)
                            .buttonStyle(.plain)
                            .foregroundStyle(.accentColor)
                        }
                    }
                    Slider(value: cursor.size, in: 1.0...5.0, step: 0.1)
                }
                .disabled(editorState.editSettings.cursor.hidden)

                // Cursor Style selector
                VStack(alignment: .leading, spacing: 8) {
                    Text("Cursor Style")
                        .font(.caption)

                    Picker("", selection: cursor.style) {
                        Text("None").tag(CursorStyle.none)
                        Text("Touch").tag(CursorStyle.touch)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
                .disabled(editorState.editSettings.cursor.hidden)

                // Rotation Intensity slider
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Rotation Intensity")
                            .font(.caption)
                        Spacer()
                        Text("\(Int(editorState.editSettings.cursor.rotationIntensity))\u{00B0}")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if editorState.editSettings.cursor.rotationIntensity > 0 {
                            Button("Reset") {
                                editorState.editSettings.cursor.rotationIntensity = 0
                                editorState.settingsDidChange()
                            }
                            .font(.caption2)
                            .buttonStyle(.plain)
                            .foregroundStyle(.accentColor)
                        }
                    }
                    Slider(value: cursor.rotationIntensity, in: 0...45, step: 1)
                }
                .disabled(editorState.editSettings.cursor.hidden)

                Spacer()
            }
            .padding()
        }
    }
}
