import SwiftUI
import CoreGraphics

/// Displays the composited preview frame, scaled to fit the preview area.
/// Updates when the user scrubs the timeline or changes settings.
struct VideoPreview: View {
    var editorState: EditorState

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.96, green: 0.95, blue: 0.92),
                                Color(red: 0.90, green: 0.89, blue: 0.85)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.black.opacity(0.06))
                    .padding(18)

                if let image = editorState.previewImage {
                    Image(decorative: image, scale: 1.0)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(
                            maxWidth: geometry.size.width - 56,
                            maxHeight: geometry.size.height - 56
                        )
                        .shadow(color: .black.opacity(0.18), radius: 24, x: 0, y: 12)
                } else {
                    VStack(spacing: 12) {
                        RecoBrandMark(size: 42)
                        Text("Rendering preview")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.black.opacity(0.82))
                        Text("Reco is preparing the current frame from your recording bundle.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                VStack {
                    HStack {
                        Text("Rendered Preview")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.black.opacity(0.54))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Capsule().fill(Color.white.opacity(0.72)))
                        Spacer()
                    }
                    .padding(18)
                    Spacer()
                }

                VStack {
                    Spacer()
                    HStack {
                        Text(formatTime(editorState.currentTime))
                            .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                        Spacer()
                    }
                    .padding(18)
                }

                if editorState.isPlaying {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "play.fill")
                                .font(.system(size: 12, weight: .bold))
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                            .padding(18)
                        }
                        Spacer()
                    }
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .task {
            editorState.schedulePreviewUpdate(delay: .zero)
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
