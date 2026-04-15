import SwiftUI
import AppKit

/// Background settings tab with sub-tabs: Wallpaper, Gradient, Color, Custom.
/// Below the sub-tabs: shadow, corner radius, and screen size sliders.
struct BackgroundPanel: View {
    @Bindable var editorState: EditorState

    private var bg: Binding<BackgroundConfig> {
        Binding(
            get: { editorState.editSettings.background },
            set: {
                editorState.editSettings.background = $0
                editorState.settingsDidChange()
            }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Sub-tab selector
                Picker("", selection: bg.type) {
                    Text("Wallpaper").tag(BackgroundType.wallpaper)
                    Text("Gradient").tag(BackgroundType.gradient)
                    Text("Color").tag(BackgroundType.solidColor)
                    Text("Custom").tag(BackgroundType.customImage)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                // Active sub-tab content
                switch editorState.editSettings.background.type {
                case .wallpaper:
                    wallpaperTab
                case .gradient:
                    gradientTab
                case .solidColor:
                    colorTab
                case .customImage:
                    customImageTab
                }

                Divider()

                // Always-visible sliders
                sliderSection
            }
            .padding()
        }
    }

    // MARK: - Wallpaper Tab

    private var wallpaperTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Wallpaper")
                .font(.headline)

            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 80, maximum: 100), spacing: 8)
            ], spacing: 8) {
                ForEach(wallpaperOptions, id: \.self) { name in
                    wallpaperThumbnail(name: name)
                }
            }
        }
    }

    private func wallpaperThumbnail(name: String) -> some View {
        let isSelected = editorState.editSettings.background.wallpaperName == name

        return RoundedRectangle(cornerRadius: 8)
            .fill(wallpaperColor(for: name))
            .aspectRatio(16 / 9, contentMode: .fit)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
            )
            .overlay(
                Text(name.capitalized)
                    .font(.caption2)
                    .foregroundStyle(.white)
            )
            .onTapGesture {
                editorState.editSettings.background.wallpaperName = name
                editorState.editSettings.background.type = .wallpaper
                editorState.settingsDidChange()
            }
    }

    private var wallpaperOptions: [String] {
        ["ocean", "sunset", "forest", "mountain", "aurora", "desert", "cosmos", "meadow"]
    }

    private func wallpaperColor(for name: String) -> LinearGradient {
        let colors: [Color] = switch name {
        case "ocean": [.blue, .cyan]
        case "sunset": [.orange, .pink]
        case "forest": [.green, .mint]
        case "mountain": [.gray, .blue]
        case "aurora": [.purple, .green]
        case "desert": [.orange, .yellow]
        case "cosmos": [.indigo, .purple]
        case "meadow": [.green, .yellow]
        default: [.gray, .secondary]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: - Gradient Tab

    private var gradientTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Gradient")
                .font(.headline)

            HStack(spacing: 16) {
                VStack(alignment: .leading) {
                    Text("Start Color").font(.caption)
                    ColorPicker("", selection: gradientStartColor)
                        .labelsHidden()
                }
                VStack(alignment: .leading) {
                    Text("End Color").font(.caption)
                    ColorPicker("", selection: gradientEndColor)
                        .labelsHidden()
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Angle").font(.caption)
                    Spacer()
                    Text("\(Int(editorState.editSettings.background.gradientAngle))\u{00B0}")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: bg.gradientAngle, in: 0...360, step: 1)
            }

            // Preview swatch
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(hex: editorState.editSettings.background.gradientColors.first ?? "#000000"),
                            Color(hex: editorState.editSettings.background.gradientColors.last ?? "#333333")
                        ],
                        startPoint: gradientStartPoint,
                        endPoint: gradientEndPoint
                    )
                )
                .frame(height: 60)
        }
    }

    private var gradientStartColor: Binding<Color> {
        Binding(
            get: {
                Color(hex: editorState.editSettings.background.gradientColors.first ?? "#000000")
            },
            set: { newColor in
                editorState.editSettings.background.gradientColors[0] = newColor.toHex()
                editorState.settingsDidChange()
            }
        )
    }

    private var gradientEndColor: Binding<Color> {
        Binding(
            get: {
                Color(hex: editorState.editSettings.background.gradientColors.last ?? "#333333")
            },
            set: { newColor in
                if editorState.editSettings.background.gradientColors.count > 1 {
                    editorState.editSettings.background.gradientColors[1] = newColor.toHex()
                }
                editorState.settingsDidChange()
            }
        )
    }

    private var gradientStartPoint: UnitPoint {
        let angle = editorState.editSettings.background.gradientAngle
        let radians = angle * .pi / 180
        return UnitPoint(x: 0.5 - cos(radians) * 0.5, y: 0.5 - sin(radians) * 0.5)
    }

    private var gradientEndPoint: UnitPoint {
        let angle = editorState.editSettings.background.gradientAngle
        let radians = angle * .pi / 180
        return UnitPoint(x: 0.5 + cos(radians) * 0.5, y: 0.5 + sin(radians) * 0.5)
    }

    // MARK: - Color Tab

    private var colorTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Solid Color")
                .font(.headline)

            ColorPicker("Background Color", selection: solidColorBinding)
        }
    }

    private var solidColorBinding: Binding<Color> {
        Binding(
            get: {
                Color(hex: editorState.editSettings.background.solidColor)
            },
            set: { newColor in
                editorState.editSettings.background.solidColor = newColor.toHex()
                editorState.settingsDidChange()
            }
        )
    }

    // MARK: - Custom Image Tab

    private var customImageTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Custom Image")
                .font(.headline)

            if let path = editorState.editSettings.background.customImagePath {
                // Show selected image info
                HStack {
                    Image(systemName: "photo")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading) {
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                            .font(.caption)
                            .lineLimit(1)
                        Text(path)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Button("Remove") {
                        editorState.editSettings.background.customImagePath = nil
                        editorState.settingsDidChange()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Button("Choose Image...") {
                chooseCustomImage()
            }
        }
    }

    private func chooseCustomImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            editorState.editSettings.background.customImagePath = url.path
            editorState.editSettings.background.type = .customImage
            editorState.settingsDidChange()
        }
    }

    // MARK: - Always-Visible Sliders

    private var sliderSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            resettableSlider(
                label: "Shadow Size",
                value: bg.shadowSize,
                range: 0...100,
                defaultValue: 30
            )
            resettableSlider(
                label: "Shadow Opacity",
                value: bg.shadowOpacity,
                range: 0...100,
                defaultValue: 60
            )
            resettableSlider(
                label: "Shadow Blur",
                value: bg.shadowBlur,
                range: 0...100,
                defaultValue: 40
            )
            resettableSlider(
                label: "Corner Radius",
                value: bg.cornerRadius,
                range: 0...50,
                defaultValue: 12
            )
            resettableSlider(
                label: "Screen Size",
                value: bg.screenScale,
                range: 50...100,
                defaultValue: 85,
                suffix: "%"
            )
        }
    }

    private func resettableSlider(
        label: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        defaultValue: Double,
        suffix: String = ""
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.caption)
                Spacer()
                Text("\(Int(value.wrappedValue))\(suffix)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if abs(value.wrappedValue - defaultValue) > 0.01 {
                    Button("Reset") {
                        value.wrappedValue = defaultValue
                        editorState.settingsDidChange()
                    }
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                }
            }
            Slider(value: value, in: range, step: 1)
        }
    }
}

// MARK: - Color Hex Helpers

extension Color {
    init(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")

        var rgb: UInt64 = 0
        Scanner(string: hexSanitized).scanHexInt64(&rgb)

        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0

        self.init(red: r, green: g, blue: b)
    }

    func toHex() -> String {
        guard let components = NSColor(self).usingColorSpace(.sRGB) else {
            return "#000000"
        }
        let r = Int(components.redComponent * 255)
        let g = Int(components.greenComponent * 255)
        let b = Int(components.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
