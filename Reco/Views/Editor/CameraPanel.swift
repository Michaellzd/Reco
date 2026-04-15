import SwiftUI

/// Camera settings tab: hide toggle, size slider, follow zoom toggle,
/// corner radius, shape selector, and 3x3 position grid.
struct CameraPanel: View {
    @Bindable var editorState: EditorState

    private var camera: Binding<CameraConfig> {
        Binding(
            get: { editorState.editSettings.camera },
            set: {
                editorState.editSettings.camera = $0
                editorState.settingsDidChange()
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Hide Camera toggle
                Toggle("Hide Camera", isOn: camera.hidden)
                    .toggleStyle(.switch)

                // Camera Size slider
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Camera Size")
                            .font(.caption)
                        Spacer()
                        Text("\(Int(editorState.editSettings.camera.size))%")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if abs(editorState.editSettings.camera.size - 30) > 0.01 {
                            Button("Reset") {
                                editorState.editSettings.camera.size = 30
                                editorState.settingsDidChange()
                            }
                            .font(.caption2)
                            .buttonStyle(.plain)
                            .foregroundStyle(.accentColor)
                        }
                    }
                    Slider(value: camera.size, in: 10...50, step: 1)
                }
                .disabled(editorState.editSettings.camera.hidden)

                // Follow Video Zoom toggle
                Toggle("Follow Video Zoom", isOn: camera.followVideoZoom)
                    .toggleStyle(.switch)
                    .disabled(editorState.editSettings.camera.hidden)

                // Corner Radius slider
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Corner Radius")
                            .font(.caption)
                        Spacer()
                        Text("\(Int(editorState.editSettings.camera.cornerRadius))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if abs(editorState.editSettings.camera.cornerRadius - 20) > 0.01 {
                            Button("Reset") {
                                editorState.editSettings.camera.cornerRadius = 20
                                editorState.settingsDidChange()
                            }
                            .font(.caption2)
                            .buttonStyle(.plain)
                            .foregroundStyle(.accentColor)
                        }
                    }
                    Slider(value: camera.cornerRadius, in: 0...50, step: 1)
                }
                .disabled(editorState.editSettings.camera.hidden)

                // Camera Shape selector
                VStack(alignment: .leading, spacing: 8) {
                    Text("Shape")
                        .font(.caption)

                    HStack(spacing: 8) {
                        ForEach(CameraShape.allCases, id: \.self) { shape in
                            shapeButton(shape)
                        }
                    }
                }
                .disabled(editorState.editSettings.camera.hidden)

                // Camera Position grid (3x3)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Position")
                        .font(.caption)

                    positionGrid
                }
                .disabled(editorState.editSettings.camera.hidden)

                Spacer()
            }
            .padding()
        }
    }

    // MARK: - Shape Button

    private func shapeButton(_ shape: CameraShape) -> some View {
        let isSelected = editorState.editSettings.camera.shape == shape

        return Button {
            editorState.editSettings.camera.shape = shape
            editorState.settingsDidChange()
        } label: {
            VStack(spacing: 4) {
                shapeIcon(shape)
                    .frame(width: 32, height: 32)
                Text(shapeLabel(shape))
                    .font(.caption2)
            }
            .padding(6)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func shapeIcon(_ shape: CameraShape) -> some View {
        switch shape {
        case .circle:
            Circle()
                .fill(Color.secondary.opacity(0.3))
                .overlay(Circle().stroke(Color.secondary, lineWidth: 1))
        case .roundedRect:
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.3))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary, lineWidth: 1))
        case .roundedRectWide:
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.3))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary, lineWidth: 1))
                .aspectRatio(4 / 3, contentMode: .fit)
        case .squareRounded:
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.3))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary, lineWidth: 1))
        case .square:
            Rectangle()
                .fill(Color.secondary.opacity(0.3))
                .overlay(Rectangle().stroke(Color.secondary, lineWidth: 1))
        case .hidden:
            Image(systemName: "xmark")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    private func shapeLabel(_ shape: CameraShape) -> String {
        switch shape {
        case .circle: "Circle"
        case .roundedRect: "Rounded"
        case .roundedRectWide: "Wide"
        case .squareRounded: "Sq Round"
        case .square: "Square"
        case .hidden: "Hidden"
        }
    }

    // MARK: - Position Grid (3x3)

    private var positionGrid: some View {
        let positions: [[CameraPosition]] = [
            [.topLeft, .topCenter, .topRight],
            [.middleLeft, .middleCenter, .middleRight],
            [.bottomLeft, .bottomCenter, .bottomRight],
        ]

        return VStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { col in
                        let position = positions[row][col]
                        positionDot(position)
                    }
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func positionDot(_ position: CameraPosition) -> some View {
        let isSelected = editorState.editSettings.camera.position == position

        return Button {
            editorState.editSettings.camera.position = position
            editorState.settingsDidChange()
        } label: {
            Circle()
                .fill(isSelected ? Color.accentColor : Color.secondary.opacity(0.3))
                .frame(width: 24, height: 24)
                .overlay(
                    Circle()
                        .stroke(isSelected ? Color.accentColor : Color.secondary, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }
}
