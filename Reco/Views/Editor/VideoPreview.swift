import SwiftUI
import CoreGraphics

/// Displays the composited preview frame, scaled to fit the preview area.
/// Updates when the user scrubs the timeline or changes settings.
struct VideoPreview: View {
    var editorState: EditorState

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.black

                if let image = editorState.previewImage {
                    Image(decorative: image, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(
                            maxWidth: geometry.size.width,
                            maxHeight: geometry.size.height
                        )
                } else {
                    // Loading / placeholder state
                    VStack(spacing: 12) {
                        Image(systemName: "film")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("Loading preview...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Time overlay (bottom-left)
                VStack {
                    Spacer()
                    HStack {
                        Text(formatTime(editorState.currentTime))
                            .font(.caption.monospacedDigit())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        Spacer()
                    }
                    .padding(8)
                }

                // Play indicator overlay
                if editorState.isPlaying {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "play.fill")
                                .font(.caption)
                                .padding(6)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                            .padding(8)
                        }
                        Spacer()
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .task {
            await editorState.updatePreview()
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
