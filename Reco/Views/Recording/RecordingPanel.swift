import SwiftUI

struct RecordingPanel: View {
    var appState: AppState
    @State private var showDiscardConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                HStack(spacing: 10) {
                    RecoBrandMark(size: 28)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Reco")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text(appState.isPaused ? "Recording paused" : "Recording live")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.68))
                    }
                }

                Spacer()

                Text(appState.isPaused ? "Paused" : "Live")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(appState.isPaused ? Color.orange : Color.recoAccent)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill((appState.isPaused ? Color.orange : Color.recoAccent).opacity(0.16))
                    )
            }

            if appState.recordingConfig.cameraEnabled {
                CameraPreviewSurface(
                    enabled: !appState.isPaused,
                    deviceID: appState.recordingConfig.cameraDeviceID,
                    cornerRadius: 24
                )
                .frame(height: 148)
                .overlay(alignment: .topLeading) {
                    Text("Camera")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.82))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.black.opacity(0.26)))
                        .padding(12)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(formattedTime(appState.elapsedTime))
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                Text("The floating panel stays outside the captured output.")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.64))
            }

            VStack(spacing: 10) {
                actionButton(
                    title: "Stop",
                    icon: "stop.fill",
                    fill: Color.recoAccent,
                    textColor: .white
                ) {
                    Task {
                        try? await appState.stopRecording()
                    }
                }

                HStack(spacing: 10) {
                    actionButton(
                        title: appState.isPaused ? "Resume" : "Pause",
                        icon: appState.isPaused ? "play.fill" : "pause.fill",
                        fill: Color.white.opacity(0.10),
                        textColor: .white
                    ) {
                        if appState.isPaused {
                            appState.resumeRecording()
                        } else {
                            appState.pauseRecording()
                        }
                    }

                    actionButton(
                        title: "Discard",
                        icon: "trash",
                        fill: Color.white.opacity(0.10),
                        textColor: .white
                    ) {
                        showDiscardConfirmation = true
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 252)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(red: 0.10, green: 0.10, blue: 0.11).opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.24), radius: 20, x: 0, y: 12)
        .alert("Discard Recording?", isPresented: $showDiscardConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Discard", role: .destructive) {
                appState.discardRecording()
            }
        } message: {
            Text("This will delete the current recording and return to setup.")
        }
    }

    private func actionButton(
        title: String,
        icon: String,
        fill: Color,
        textColor: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(fill)
            )
            .foregroundStyle(textColor)
        }
        .buttonStyle(.plain)
    }

    private func formattedTime(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
