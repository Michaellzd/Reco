import SwiftUI
import AVFoundation

struct SetupView: View {
    @Bindable var appState: AppState
    var permissionManager: PermissionManager

    @State private var availableCameras: [AVCaptureDevice] = []
    @State private var availableMicrophones: [AVCaptureDevice] = []
    @State private var selectedCameraID: String = ""
    @State private var selectedMicrophoneID: String = ""
    @State private var showingAreaSelector: Bool = false
    @State private var isStarting: Bool = false
    @State private var errorMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                Divider()
                recordModeSection
                Divider()
                screenSelectionSection
                Divider()
                resolutionSection
                Divider()
                deviceSection
                Divider()
                startButton
            }
            .padding(24)
        }
        .frame(minWidth: 380, idealWidth: 400, minHeight: 500, idealHeight: 600)
        .onAppear {
            loadDevices()
            Task {
                await permissionManager.checkAllPermissions()
            }
        }
        .alert("Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Image(systemName: "record.circle")
                .font(.system(size: 28))
                .foregroundStyle(.red)
            Text("Reco")
                .font(.largeTitle)
                .fontWeight(.bold)
            Spacer()
            Button {
                // Settings placeholder
            } label: {
                Image(systemName: "gearshape")
                    .font(.title2)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Record Mode

    private var recordModeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Record Mode")
                .font(.headline)
                .foregroundStyle(.secondary)

            RecordModeSelector(selectedMode: $appState.recordingConfig.mode)
        }
    }

    // MARK: - Screen Selection

    private var screenSelectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Screen")
                .font(.headline)
                .foregroundStyle(.secondary)

            ScreenSelector(
                config: $appState.recordingConfig,
                showingAreaSelector: $showingAreaSelector
            )
        }
    }

    // MARK: - Resolution

    private var resolutionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Resolution")
                .font(.headline)
                .foregroundStyle(.secondary)

            Picker("Resolution", selection: $appState.recordingConfig.resolution) {
                Text("Original").tag(Resolution.original)
                Text("4K (2160p)").tag(Resolution.p2160)
                Text("1080p").tag(Resolution.p1080)
                Text("720p").tag(Resolution.p720)
            }
            .labelsHidden()
        }
    }

    // MARK: - Device Selection

    private var deviceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Devices")
                .font(.headline)
                .foregroundStyle(.secondary)

            // Camera
            HStack {
                Label("Camera", systemImage: "camera")
                    .frame(width: 120, alignment: .leading)
                Spacer()
                if permissionManager.cameraStatus == .denied {
                    deniedLabel(action: permissionManager.openCameraSettings)
                } else {
                    Toggle("", isOn: $appState.recordingConfig.cameraEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                    if appState.recordingConfig.cameraEnabled {
                        Picker("Camera", selection: $selectedCameraID) {
                            ForEach(availableCameras, id: \.uniqueID) { device in
                                Text(device.localizedName).tag(device.uniqueID)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 180)
                    }
                }
            }

            // Microphone
            HStack {
                Label("Microphone", systemImage: "mic")
                    .frame(width: 120, alignment: .leading)
                Spacer()
                if permissionManager.microphoneStatus == .denied {
                    deniedLabel(action: permissionManager.openMicrophoneSettings)
                } else {
                    Toggle("", isOn: $appState.recordingConfig.micEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                    if appState.recordingConfig.micEnabled {
                        Picker("Microphone", selection: $selectedMicrophoneID) {
                            ForEach(availableMicrophones, id: \.uniqueID) { device in
                                Text(device.localizedName).tag(device.uniqueID)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 180)
                    }
                }
            }

            // System Audio
            HStack {
                Label("System Audio", systemImage: "speaker.wave.2")
                    .frame(width: 120, alignment: .leading)
                Spacer()
                Toggle("", isOn: $appState.recordingConfig.systemAudioEnabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
            }
        }
    }

    // MARK: - Start Button

    private var startButton: some View {
        VStack(spacing: 8) {
            if permissionManager.screenRecordingStatus == .denied {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("Screen recording permission is required.")
                        .font(.caption)
                    Button("Open Settings") {
                        permissionManager.openSystemSettings()
                    }
                    .font(.caption)
                }
            }

            Button {
                startRecording()
            } label: {
                HStack {
                    Image(systemName: "record.circle")
                    Text("Start Recording")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)
            .disabled(isStarting || permissionManager.screenRecordingStatus == .denied)
        }
    }

    // MARK: - Helpers

    private func deniedLabel(action: @escaping () -> Void) -> some View {
        HStack {
            Text("Permission Denied")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Settings") { action() }
                .font(.caption)
        }
    }

    private func loadDevices() {
        let discoveryCamera = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
            mediaType: .video,
            position: .unspecified
        )
        availableCameras = discoveryCamera.devices
        if let first = availableCameras.first {
            selectedCameraID = first.uniqueID
        }

        let discoveryMic = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInMicrophone, .externalUnknown],
            mediaType: .audio,
            position: .unspecified
        )
        availableMicrophones = discoveryMic.devices
        if let first = availableMicrophones.first {
            selectedMicrophoneID = first.uniqueID
        }
    }

    private func startRecording() {
        isStarting = true
        Task {
            do {
                // Request permissions if needed
                if permissionManager.cameraStatus == .unknown && appState.recordingConfig.cameraEnabled {
                    await permissionManager.requestCameraPermission()
                }
                if permissionManager.microphoneStatus == .unknown && appState.recordingConfig.micEnabled {
                    await permissionManager.requestMicrophonePermission()
                }
                try await appState.startRecording()
            } catch {
                errorMessage = error.localizedDescription
            }
            isStarting = false
        }
    }
}
