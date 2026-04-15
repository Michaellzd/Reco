import SwiftUI
import AVFoundation
import AppKit

struct SetupView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var appState: AppState
    var permissionManager: PermissionManager

    @State private var availableCameras: [AVCaptureDevice] = []
    @State private var availableMicrophones: [AVCaptureDevice] = []
    @State private var selectedCameraID: String = ""
    @State private var selectedMicrophoneID: String = ""
    @State private var showingAreaSelector: Bool = false
    @State private var isStarting: Bool = false
    @State private var errorMessage: String?
    @State private var microphoneMeterEnabled: Bool = false

    var body: some View {
        rootContent
        .tint(.recoAccent)
        .frame(minWidth: 960, idealWidth: 1240, minHeight: 760, idealHeight: 840)
        .onAppear {
            loadDevices()
            refreshPermissions()
            syncMicrophoneMeterState()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            refreshPermissions(forceScreenProbe: permissionManager.screenPermissionNeedsRestartHint)
        }
        .onChange(of: selectedCameraID) { _, newValue in
            appState.recordingConfig.cameraDeviceID = newValue.isEmpty ? nil : newValue
        }
        .onChange(of: selectedMicrophoneID) { _, newValue in
            appState.recordingConfig.microphoneDeviceID = newValue.isEmpty ? nil : newValue
        }
        .onChange(of: appState.recordingConfig.cameraEnabled) { _, isEnabled in
            guard isEnabled, permissionManager.cameraStatus == .unknown else { return }
            Task {
                await permissionManager.requestCameraPermission()
            }
        }
        .onChange(of: appState.recordingConfig.micEnabled) { _, isEnabled in
            if isEnabled && permissionManager.microphoneStatus == .unknown {
                Task {
                    await permissionManager.requestMicrophonePermission()
                }
            }
            syncMicrophoneMeterState()
        }
        .onChange(of: permissionManager.microphoneStatus) { _, status in
            microphoneMeterEnabled = appState.recordingConfig.micEnabled && status == .granted
        }
        .alert("Error", isPresented: errorAlertBinding) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var rootContent: some View {
        GeometryReader { geometry in
            ZStack {
                setupBackground
                setupContent(for: geometry)
            }
        }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func setupContent(for geometry: GeometryProxy) -> AnyView {
        if geometry.size.width < 1120 {
            return AnyView(compactSetupLayout)
        } else {
            return AnyView(regularSetupLayout(geometry: geometry))
        }
    }

    private var compactSetupLayout: AnyView {
        AnyView(
            ScrollView {
                VStack(spacing: 20) {
                    controlPanel
                    stagePanel
                }
                .padding(24)
            }
        )
    }

    private func regularSetupLayout(geometry: GeometryProxy) -> AnyView {
        AnyView(
            HStack(alignment: .top, spacing: 24) {
                ScrollView(.vertical, showsIndicators: true) {
                    controlPanel
                        .padding(.bottom, 8)
                }
                .frame(width: min(max(460, geometry.size.width * 0.42), 560))
                .scrollBounceBehavior(.basedOnSize)
                .scrollIndicators(.visible)

                stagePanel
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height - 64)
            }
            .padding(32)
        )
    }

    // MARK: - Layout

    private var setupBackground: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.recoCanvas,
                    Color(red: 0.95, green: 0.94, blue: 0.90)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.recoAccent.opacity(0.12))
                .frame(width: 380, height: 380)
                .blur(radius: 80)
                .offset(x: 360, y: -240)

            Circle()
                .fill(Color.black.opacity(0.05))
                .frame(width: 300, height: 300)
                .blur(radius: 70)
                .offset(x: -360, y: 260)
        }
    }

    private var controlPanel: AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                recordModeSection
                captureSection
                deviceSection
                permissionSection
                startButton
            }
            .padding(30)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(Color.white.opacity(0.84))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 20, x: 0, y: 14)
        )
    }

    private var stagePanel: AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Live Stage")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.72))
                            .textCase(.uppercase)

                        Text(stageTitle)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        Text(stageSubtitle)
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.74))
                    }

                    Spacer()

                    summaryChip(title: modeLabel)
                }

                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.14, green: 0.14, blue: 0.16),
                                    Color(red: 0.08, green: 0.08, blue: 0.09)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    if cameraPreviewEnabled {
                        stageCameraComposition
                            .padding(22)
                    } else {
                        stagePlaceholder
                            .padding(26)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Current Session")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.58))
                            .textCase(.uppercase)

                        HStack(spacing: 10) {
                            summaryChip(title: resolutionLabel)
                            summaryChip(title: currentDisplayName)
                            summaryChip(title: audioLabel)
                        }
                    }
                    .padding(26)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 520)

                HStack(spacing: 16) {
                    stageMetric(
                        label: "Camera",
                        value: appState.recordingConfig.cameraEnabled ? "Live" : "Off"
                    )
                    stageMetric(
                        label: "Mic",
                        value: appState.recordingConfig.micEnabled ? "On" : "Off"
                    )
                    stageMetric(
                        label: "Export",
                        value: "Editable"
                    )
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .fill(Color(red: 0.09, green: 0.09, blue: 0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .stroke(Color.white.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 30, x: 0, y: 18)
        )
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                HStack(spacing: 14) {
                    RecoBrandMark(size: 50)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Reco")
                            .font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(.black.opacity(0.9))

                        Text("Capture once. Polish after.")
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    // Settings placeholder
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color.white.opacity(0.74)))
                }
                .buttonStyle(.plain)
            }

            Text("A focused studio for screen recording with live camera framing, isolated tracks, and post-export control.")
                .font(.system(size: 15, weight: .regular, design: .rounded))
                .foregroundStyle(.secondary)
                .frame(maxWidth: 470, alignment: .leading)
        }
    }

    // MARK: - Sections

    private var recordModeSection: some View {
        sectionBlock(
            eyebrow: "Recording Setup",
            title: "Choose what leads the frame"
        ) {
            RecordModeSelector(selectedMode: $appState.recordingConfig.mode)
        }
    }

    private var captureSection: some View {
        sectionBlock(
            eyebrow: "Capture Area",
            title: "Select the display and framing"
        ) {
            VStack(alignment: .leading, spacing: 18) {
                ScreenSelector(
                    config: $appState.recordingConfig,
                    showingAreaSelector: $showingAreaSelector
                )

                VStack(alignment: .leading, spacing: 10) {
                    Text("Resolution")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Picker("Resolution", selection: $appState.recordingConfig.resolution) {
                        Text("Original").tag(Resolution.original)
                        Text("4K (2160p)").tag(Resolution.p2160)
                        Text("1080p").tag(Resolution.p1080)
                        Text("720p").tag(Resolution.p720)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
        }
    }

    private var deviceSection: some View {
        sectionBlock(
            eyebrow: "Devices",
            title: "Bring in camera and audio sources"
        ) {
            VStack(spacing: 14) {
                deviceRow(title: "Camera", icon: "video") {
                    if permissionManager.cameraStatus == .denied {
                        deniedLabel(action: permissionManager.openCameraSettings)
                    } else {
                        HStack(spacing: 12) {
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
                                .frame(maxWidth: 220)
                            }
                        }
                    }
                }

                deviceRow(title: "Microphone", icon: "mic") {
                    if permissionManager.microphoneStatus == .denied {
                        deniedLabel(action: permissionManager.openMicrophoneSettings)
                    } else {
                        VStack(alignment: .trailing, spacing: 10) {
                            HStack(spacing: 12) {
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
                                    .frame(maxWidth: 220)
                                }
                            }

                            if appState.recordingConfig.micEnabled {
                                MicrophoneLevelMeter(
                                    enabled: microphoneMeterEnabled,
                                    deviceID: appState.recordingConfig.microphoneDeviceID
                                )

                                Text("Speak into the mic to confirm Reco is receiving input before you record.")
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                        }
                    }
                }

                deviceRow(title: "System Audio", icon: "speaker.wave.2") {
                    Toggle("", isOn: $appState.recordingConfig.systemAudioEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
            }
        }
    }

    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Permissions")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 10) {
                permissionPill(title: "Screen", status: permissionManager.screenRecordingStatus)
                permissionPill(title: "Camera", status: permissionManager.cameraStatus)
                permissionPill(title: "Mic", status: permissionManager.microphoneStatus)
            }
        }
    }

    // MARK: - Stage Helpers

    private var cameraPreviewEnabled: Bool {
        appState.recordingConfig.cameraEnabled && permissionManager.cameraStatus == .granted
    }

    private var stageTitle: String {
        appState.recordingConfig.mode == .portraitAndScreen
            ? "Frame yourself beside the screen"
            : "Capture the screen with minimal chrome"
    }

    private var stageSubtitle: String {
        if cameraPreviewEnabled {
            return "Your selected camera is live. This stage mirrors the tone of the final composition."
        }
        if appState.recordingConfig.cameraEnabled && permissionManager.cameraStatus != .granted {
            return "Camera is enabled, but preview is waiting on permission."
        }
        return "Turn on Camera to see a live preview here before you record."
    }

    private var stageCameraComposition: some View {
        ZStack(alignment: .topLeading) {
            CameraPreviewSurface(
                enabled: true,
                deviceID: appState.recordingConfig.cameraDeviceID,
                cornerRadius: 30
            )

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.28), lineWidth: 1)
                .padding(44)

            VStack(alignment: .leading, spacing: 8) {
                Text("Camera Live")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.68))
                    .textCase(.uppercase)

                Text(appState.recordingConfig.mode == .portraitAndScreen ? "Portrait + Screen" : "Camera Monitoring")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(26)

            if appState.recordingConfig.mode == .portraitAndScreen {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.black.opacity(0.36))
                    .frame(width: 220, height: 140)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    )
                    .overlay(
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Portrait Overlay")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white.opacity(0.65))
                            Text("Shown in export as a movable layer.")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(.white)
                        }
                        .padding(16),
                        alignment: .bottomLeading
                    )
                    .padding(28)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
    }

    private var stagePlaceholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.08),
                            Color.white.opacity(0.03)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.18), lineWidth: 1)
                .padding(34)

            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 16) {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 260, height: 156)
                        .overlay(
                            RoundedRectangle(cornerRadius: 28, style: .continuous)
                                .stroke(Color.white.opacity(0.16), lineWidth: 1)
                        )
                        .overlay(
                            Image(systemName: "display")
                                .font(.system(size: 44, weight: .light))
                                .foregroundStyle(.white.opacity(0.6))
                        )

                    if appState.recordingConfig.mode == .portraitAndScreen {
                        Circle()
                            .fill(Color.recoAccent.opacity(0.78))
                            .frame(width: 146, height: 146)
                            .overlay(RecoBrandMark(size: 54).foregroundStyle(.white))
                            .overlay(
                                Circle().stroke(Color.white.opacity(0.18), lineWidth: 1)
                            )
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(cameraPromptTitle)
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text(cameraPromptMessage)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                        .frame(maxWidth: 460, alignment: .leading)
                }
            }
            .padding(36)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }

    private var cameraPromptTitle: String {
        if appState.recordingConfig.cameraEnabled && permissionManager.cameraStatus != .granted {
            return "Enable camera permission to bring yourself into the frame"
        }
        return appState.recordingConfig.mode == .portraitAndScreen
            ? "Turn on camera to preview your portrait before recording"
            : "Screen-only mode keeps the stage clean and focused"
    }

    private var cameraPromptMessage: String {
        if appState.recordingConfig.cameraEnabled && permissionManager.cameraStatus == .denied {
            return "Reco can record with camera once macOS grants permission. Open Settings and allow camera access, then come back here."
        }
        if appState.recordingConfig.mode == .portraitAndScreen {
            return "Your camera feed appears live in this stage so you can check framing, lighting, and device selection before you start."
        }
        return "You can still enable microphone and system audio, then style the final export later in the editor."
    }

    private var modeLabel: String {
        switch appState.recordingConfig.mode {
        case .portraitAndScreen:
            return "Portrait + Screen"
        case .screenOnly:
            return "Screen Only"
        }
    }

    private var resolutionLabel: String {
        switch appState.recordingConfig.resolution {
        case .original:
            return "Original"
        case .p2160:
            return "4K"
        case .p1080:
            return "1080p"
        case .p720:
            return "720p"
        }
    }

    private var currentDisplayName: String {
        NSScreen.screens.first(where: { $0.displayID == appState.recordingConfig.displayID })?.localizedName ?? "Display"
    }

    private var audioLabel: String {
        if appState.recordingConfig.micEnabled && appState.recordingConfig.systemAudioEnabled {
            return "Mic + System"
        }
        if appState.recordingConfig.micEnabled {
            return "Mic Only"
        }
        if appState.recordingConfig.systemAudioEnabled {
            return "System Audio"
        }
        return "Silent"
    }

    // MARK: - Start Button

    private var startButton: some View {
        VStack(alignment: .leading, spacing: 12) {
            if permissionManager.screenRecordingStatus == .denied {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Screen recording permission is required before Reco can start.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 10) {
                        Button("Open Settings") {
                            permissionManager.openSystemSettings()
                        }
                        .font(.system(size: 13, weight: .semibold, design: .rounded))

                        Button("Check Again") {
                            refreshPermissions(forceScreenProbe: true)
                        }
                        .font(.system(size: 13, weight: .semibold, design: .rounded))

                        if permissionManager.screenPermissionNeedsRestartHint {
                            Button("Relaunch App") {
                                permissionManager.relaunchApp()
                            }
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                        }
                    }

                    if permissionManager.screenPermissionNeedsRestartHint {
                        Text("On newer macOS versions, screen recording permission may require quitting and reopening Reco after you enable it.")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.orange.opacity(0.08))
                )
            }

            Button {
                startRecording()
            } label: {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(isStarting ? "Preparing…" : "Start Recording")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                        Text("Reco records separate tracks so you can polish the result later.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.82))
                    }

                    Spacer()

                    Image(systemName: "arrow.up.right.circle.fill")
                        .font(.system(size: 24, weight: .semibold))
                }
                .padding(18)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color.recoAccent)
                )
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(isStarting || permissionManager.screenRecordingStatus == .denied)
            .opacity(isStarting || permissionManager.screenRecordingStatus == .denied ? 0.6 : 1)
        }
    }

    // MARK: - Helpers

    private func sectionBlock<Content: View>(
        eyebrow: String,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(eyebrow)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            Text(title)
                .font(.system(size: 23, weight: .semibold, design: .rounded))
                .foregroundStyle(.black.opacity(0.88))

            content()
        }
    }

    private func deviceRow<Content: View>(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 16) {
            Label(title, systemImage: icon)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.black.opacity(0.8))
                .frame(width: 130, alignment: .leading)

            Spacer()

            content()
        }
        .padding(.vertical, 4)
    }

    private func permissionPill(title: String, status: PermissionStatus) -> some View {
        let palette = permissionPalette(for: status)

        return HStack(spacing: 8) {
            Circle()
                .fill(palette.dot)
                .frame(width: 8, height: 8)

            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))

            Text(palette.label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(palette.fill)
        )
    }

    private func permissionPalette(for status: PermissionStatus) -> (dot: Color, fill: Color, label: String) {
        switch status {
        case .granted:
            return (.green, Color.green.opacity(0.12), "Ready")
        case .denied:
            return (.orange, Color.orange.opacity(0.14), "Action needed")
        case .restricted:
            return (.gray, Color.gray.opacity(0.14), "Restricted")
        case .unknown:
            return (.secondary, Color.black.opacity(0.05), "Pending")
        }
    }

    private func summaryChip(title: String) -> some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.10))
            )
    }

    private func stageMetric(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.52))
                .textCase(.uppercase)

            Text(value)
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private func deniedLabel(action: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Text("Permission denied")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Button("Settings") { action() }
                .font(.system(size: 12, weight: .semibold, design: .rounded))
        }
    }

    private func loadDevices() {
        let discoveryCamera = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        )
        availableCameras = discoveryCamera.devices

        if let stored = appState.recordingConfig.cameraDeviceID,
           availableCameras.contains(where: { $0.uniqueID == stored }) {
            selectedCameraID = stored
        } else if let first = availableCameras.first {
            selectedCameraID = first.uniqueID
            appState.recordingConfig.cameraDeviceID = first.uniqueID
        }

        let discoveryMic = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        availableMicrophones = discoveryMic.devices

        if let stored = appState.recordingConfig.microphoneDeviceID,
           availableMicrophones.contains(where: { $0.uniqueID == stored }) {
            selectedMicrophoneID = stored
        } else if let first = availableMicrophones.first {
            selectedMicrophoneID = first.uniqueID
            appState.recordingConfig.microphoneDeviceID = first.uniqueID
        }
    }

    private func startRecording() {
        isStarting = true
        Task {
            do {
                await permissionManager.checkAllPermissions(forceScreenProbe: true)

                if permissionManager.screenRecordingStatus != .granted {
                    await permissionManager.requestScreenRecordingPermission()
                    await permissionManager.checkScreenRecordingPermission(forceProbe: true)
                }
                if permissionManager.cameraStatus == .unknown && appState.recordingConfig.cameraEnabled {
                    await permissionManager.requestCameraPermission()
                }
                if permissionManager.microphoneStatus == .unknown && appState.recordingConfig.micEnabled {
                    await permissionManager.requestMicrophonePermission()
                }

                guard permissionManager.screenRecordingStatus == .granted else {
                    errorMessage = "Screen recording permission is still not available. If you just enabled it in System Settings, relaunch Reco and try again."
                    isStarting = false
                    return
                }
                try await appState.startRecording()
            } catch {
                errorMessage = error.localizedDescription
            }
            isStarting = false
        }
    }

    private func refreshPermissions(forceScreenProbe: Bool = false) {
        Task {
            await permissionManager.checkAllPermissions(forceScreenProbe: forceScreenProbe)
            await MainActor.run {
                syncMicrophoneMeterState()
            }
        }
    }

    @MainActor
    private func syncMicrophoneMeterState() {
        microphoneMeterEnabled = appState.recordingConfig.micEnabled && permissionManager.microphoneStatus == .granted
    }
}

struct RecoBrandMark: View {
    var size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.recoAccent, lineWidth: max(3, size * 0.12))
                .frame(width: size, height: size)

            Circle()
                .fill(Color.recoAccent)
                .frame(width: size * 0.34, height: size * 0.34)
        }
        .frame(width: size, height: size)
    }
}

struct CameraPreviewSurface: View {
    let enabled: Bool
    let deviceID: String?
    var cornerRadius: CGFloat = 28

    @StateObject private var controller = CameraPreviewController()

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.black.opacity(0.92))

            if enabled {
                CameraPreviewRepresentable(session: controller.session)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    .overlay(
                        LinearGradient(
                            colors: [
                                Color.clear,
                                Color.black.opacity(0.24)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                    )
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "video.slash.fill")
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                    Text("Camera preview appears here")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
        }
        .onAppear {
            updateSession()
        }
        .onDisappear {
            controller.stop()
        }
        .onChange(of: enabled) { _, _ in
            updateSession()
        }
        .onChange(of: deviceID) { _, _ in
            updateSession()
        }
    }

    private func updateSession() {
        if enabled {
            controller.start(deviceID: deviceID)
        } else {
            controller.stop()
        }
    }
}

final class CameraPreviewController: ObservableObject {
    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.reco.cameraPreview.session", qos: .userInitiated)
    private var currentInput: AVCaptureDeviceInput?
    private var currentDeviceID: String?

    func start(deviceID: String?) {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning, self.currentDeviceID == deviceID {
                return
            }

            let device = self.findCamera(with: deviceID)
            self.session.beginConfiguration()
            if self.session.canSetSessionPreset(.hd1920x1080) {
                self.session.sessionPreset = .hd1920x1080
            } else {
                self.session.sessionPreset = .high
            }

            if let currentInput = self.currentInput {
                self.session.removeInput(currentInput)
                self.currentInput = nil
            }

            guard let device,
                  let input = try? AVCaptureDeviceInput(device: device),
                  self.session.canAddInput(input) else {
                self.session.commitConfiguration()
                if self.session.isRunning {
                    self.session.stopRunning()
                }
                return
            }

            self.session.addInput(input)
            self.currentInput = input
            self.currentDeviceID = deviceID
            self.session.commitConfiguration()

            if !self.session.isRunning {
                self.session.startRunning()
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    private func findCamera(with deviceID: String?) -> AVCaptureDevice? {
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external],
            mediaType: .video,
            position: .unspecified
        ).devices

        if let deviceID {
            return devices.first(where: { $0.uniqueID == deviceID }) ?? AVCaptureDevice.default(for: .video)
        }

        return AVCaptureDevice.default(for: .video)
    }
}

struct CameraPreviewRepresentable: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> CameraPreviewContainerView {
        let view = CameraPreviewContainerView()
        view.previewLayer.session = session
        return view
    }

    func updateNSView(_ nsView: CameraPreviewContainerView, context: Context) {
        nsView.previewLayer.session = session
        if let connection = nsView.previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
    }
}

final class CameraPreviewContainerView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.masksToBounds = true
        layer?.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        layer?.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
        if let connection = previewLayer.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
    }
}

struct MicrophoneLevelMeter: View {
    let enabled: Bool
    let deviceID: String?

    @StateObject private var monitor = MicrophoneLevelMonitor()

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 8) {
                Text("Input level")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)

                if enabled {
                    Text(monitor.level > 0.12 ? "Voice detected" : "Listening")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(monitor.level > 0.12 ? .green : .secondary)
                }
            }

            HStack(spacing: 4) {
                ForEach(0..<14, id: \.self) { index in
                    Capsule()
                        .fill(barColor(for: index))
                        .frame(width: 6, height: CGFloat(8 + index * 2))
                }
            }
            .frame(height: 38, alignment: .bottom)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.04))
        )
        .onAppear {
            updateMonitor()
        }
        .onDisappear {
            monitor.stop()
        }
        .onChange(of: enabled) { _, _ in
            updateMonitor()
        }
        .onChange(of: deviceID) { _, _ in
            updateMonitor()
        }
    }

    private func updateMonitor() {
        if enabled {
            monitor.start(deviceID: deviceID)
        } else {
            monitor.stop()
        }
    }

    private func barColor(for index: Int) -> Color {
        let threshold = Double(index + 1) / 14.0
        if !enabled {
            return Color.secondary.opacity(0.12)
        }
        if monitor.level >= threshold {
            if index > 10 {
                return Color.recoAccent
            }
            if index > 6 {
                return Color.orange
            }
            return Color.green
        }
        return Color.secondary.opacity(0.18)
    }
}

final class MicrophoneLevelMonitor: NSObject, ObservableObject {
    @Published var level: Double = 0

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "com.reco.microphoneLevelMonitor", qos: .userInitiated)
    private var audioOutput: AVCaptureAudioDataOutput?
    private var input: AVCaptureDeviceInput?
    private var currentDeviceID: String?

    func start(deviceID: String?) {
        queue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning, self.currentDeviceID == deviceID {
                return
            }

            self.configureSession(deviceID: deviceID)
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            DispatchQueue.main.async {
                self.level = 0
            }
        }
    }

    private func configureSession(deviceID: String?) {
        let device = findMicrophone(with: deviceID)

        session.beginConfiguration()

        if let input {
            session.removeInput(input)
            self.input = nil
        }
        if let audioOutput {
            session.removeOutput(audioOutput)
            self.audioOutput = nil
        }

        guard let device,
              let newInput = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(newInput) else {
            session.commitConfiguration()
            if session.isRunning {
                session.stopRunning()
            }
            DispatchQueue.main.async {
                self.level = 0
            }
            return
        }

        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: queue)

        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            return
        }

        session.addInput(newInput)
        session.addOutput(output)
        session.commitConfiguration()

        input = newInput
        audioOutput = output
        currentDeviceID = deviceID

        if !session.isRunning {
            session.startRunning()
        }
    }

    private func findMicrophone(with deviceID: String?) -> AVCaptureDevice? {
        let devices = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        ).devices

        if let deviceID {
            return devices.first(where: { $0.uniqueID == deviceID }) ?? AVCaptureDevice.default(for: .audio)
        }

        return AVCaptureDevice.default(for: .audio)
    }
}

extension MicrophoneLevelMonitor: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return }

        var length = 0
        var dataPointer: UnsafeMutablePointer<Int8>?
        CMBlockBufferGetDataPointer(blockBuffer, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &dataPointer)

        guard let dataPointer, length > 0 else { return }

        let sampleCount = length / MemoryLayout<Int16>.size
        let bufferPointer = UnsafeBufferPointer(
            start: UnsafeRawPointer(dataPointer).assumingMemoryBound(to: Int16.self),
            count: sampleCount
        )

        guard sampleCount > 0 else { return }

        var sumSquares: Double = 0
        for sample in bufferPointer {
            let normalized = Double(sample) / Double(Int16.max)
            sumSquares += normalized * normalized
        }

        let rms = sqrt(sumSquares / Double(sampleCount))
        let normalizedLevel = min(max(rms * 10.0, 0), 1)

        DispatchQueue.main.async {
            self.level = self.level * 0.72 + normalizedLevel * 0.28
        }
    }
}

extension Color {
    static let recoAccent = Color(red: 0.95, green: 0.35, blue: 0.29)
    static let recoCanvas = Color(red: 0.98, green: 0.97, blue: 0.94)
}
