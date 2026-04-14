import SwiftUI

struct RecordingPanel: View {
    var appState: AppState
    @State private var showDiscardConfirmation = false

    var body: some View {
        VStack(spacing: 16) {
            // Timer display
            Text(formattedTime(appState.elapsedTime))
                .font(.system(.title2, design: .monospaced))
                .fontWeight(.medium)
                .foregroundStyle(.white)

            // Recording indicator
            HStack(spacing: 6) {
                Circle()
                    .fill(appState.isPaused ? .orange : .red)
                    .frame(width: 8, height: 8)
                Text(appState.isPaused ? "Paused" : "Recording")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()
                .background(Color.white.opacity(0.2))

            // Control buttons
            VStack(spacing: 12) {
                // Stop button
                Button {
                    Task {
                        try? await appState.stopRecording()
                    }
                } label: {
                    HStack {
                        Image(systemName: "stop.circle.fill")
                            .font(.title3)
                        Text("Stop")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.regular)

                // Pause / Resume button
                Button {
                    if appState.isPaused {
                        appState.resumeRecording()
                    } else {
                        appState.pauseRecording()
                    }
                } label: {
                    HStack {
                        Image(systemName: appState.isPaused ? "play.circle.fill" : "pause.circle.fill")
                            .font(.title3)
                        Text(appState.isPaused ? "Resume" : "Pause")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                // Delete button
                Button {
                    showDiscardConfirmation = true
                } label: {
                    HStack {
                        Image(systemName: "trash")
                            .font(.title3)
                        Text("Discard")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .alert("Discard Recording?", isPresented: $showDiscardConfirmation) {
                    Button("Cancel", role: .cancel) {}
                    Button("Discard", role: .destructive) {
                        appState.discardRecording()
                    }
                } message: {
                    Text("This will delete the current recording and return to setup.")
                }
            }
        }
        .padding(16)
        .frame(width: 180)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
    }

    // MARK: - Time Formatting

    private func formattedTime(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
