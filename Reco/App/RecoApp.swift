import SwiftUI

@main
struct RecoApp: App {
    @State private var appState = AppState()
    @State private var permissionManager = PermissionManager()
    @State private var panelController: RecordingPanelController?

    var body: some Scene {
        WindowGroup {
            Group {
                switch appState.phase {
                case .setup:
                    SetupView(appState: appState, permissionManager: permissionManager)

                case .recording:
                    // Minimal view while recording — the floating panel is the primary UI
                    VStack(spacing: 12) {
                        Image(systemName: "record.circle")
                            .font(.system(size: 48))
                            .foregroundStyle(.red)
                        Text("Recording in progress...")
                            .font(.headline)
                        Text("Use the floating panel to control your recording.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 400, height: 300)

                case .editing(let projectURL):
                    EditorView(projectURL: projectURL)
                }
            }
            .onChange(of: appState.phase) { oldPhase, newPhase in
                handlePhaseTransition(from: oldPhase, to: newPhase)
            }
        }
        .defaultSize(width: 1200, height: 800)
    }

    private func handlePhaseTransition(from oldPhase: AppPhase, to newPhase: AppPhase) {
        switch newPhase {
        case .recording:
            let controller = RecordingPanelController(appState: appState)
            controller.showPanel()
            panelController = controller
            // Pass the panel's window ID to AppState for capture exclusion
            appState.excludedWindowID = controller.windowID

        case .setup, .editing:
            panelController?.hidePanel()
            panelController = nil
            appState.excludedWindowID = nil
        }
    }
}
