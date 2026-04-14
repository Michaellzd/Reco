import SwiftUI
import AppKit

/// Modal export sheet with format, resolution, FPS options,
/// output path picker, progress bar, and completion actions.
struct ExportView: View {
    @Bindable var editorState: EditorState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedFormat: ExportFormat = .mp4
    @State private var selectedResolution: ExportResolution = .original
    @State private var selectedFPS: Int = 60
    @State private var outputURL: URL?
    @State private var exportError: String?

    var body: some View {
        VStack(spacing: 20) {
            // Title
            Text("Export Video")
                .font(.title2)
                .fontWeight(.semibold)

            if editorState.exportComplete {
                completionView
            } else if editorState.isExporting {
                progressView
            } else {
                settingsView
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    // MARK: - Settings View

    private var settingsView: some View {
        VStack(spacing: 16) {
            // Output Format
            VStack(alignment: .leading, spacing: 4) {
                Text("Format")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: $selectedFormat) {
                    ForEach(ExportFormat.allCases) { format in
                        Text(format.rawValue).tag(format)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            // Resolution
            VStack(alignment: .leading, spacing: 4) {
                Text("Resolution")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: $selectedResolution) {
                    ForEach(ExportResolution.allCases) { res in
                        Text(res.rawValue).tag(res)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            // FPS
            VStack(alignment: .leading, spacing: 4) {
                Text("Frame Rate")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: $selectedFPS) {
                    Text("30 FPS").tag(30)
                    Text("60 FPS").tag(60)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            // Output Path
            VStack(alignment: .leading, spacing: 4) {
                Text("Output Location")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    if let url = outputURL {
                        Text(url.path)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("No location selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Choose...") {
                        chooseOutputLocation()
                    }
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Error message
            if let error = exportError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()

            // Action buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Export") {
                    startExport()
                }
                .buttonStyle(.borderedProminent)
                .disabled(outputURL == nil)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    // MARK: - Progress View

    private var progressView: some View {
        VStack(spacing: 16) {
            ProgressView(value: editorState.exportProgress) {
                Text("Exporting...")
                    .font(.headline)
            } currentValueLabel: {
                Text("\(Int(editorState.exportProgress * 100))%")
                    .font(.caption.monospacedDigit())
            }

            Button("Cancel") {
                editorState.cancelExport()
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Completion View

    private var completionView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Export Complete!")
                .font(.headline)

            if let url = outputURL {
                Text(url.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                Button("Done") {
                    editorState.isExporting = false
                    editorState.exportComplete = false
                    dismiss()
                }
                .buttonStyle(.bordered)

                if let url = outputURL {
                    Button("Open in Finder") {
                        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
                        editorState.isExporting = false
                        editorState.exportComplete = false
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    // MARK: - Actions

    private func chooseOutputLocation() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.nameFieldStringValue = "Reco Export"
        panel.canCreateDirectories = true

        switch selectedFormat {
        case .mp4: panel.allowedContentTypes = [.mpeg4Movie]
        case .hevc: panel.allowedContentTypes = [.mpeg4Movie]
        case .proRes: panel.allowedContentTypes = [.quickTimeMovie]
        }

        if panel.runModal() == .OK {
            outputURL = panel.url
        }
    }

    private func startExport() {
        guard let url = outputURL else {
            exportError = "Please choose an output location."
            return
        }
        exportError = nil

        editorState.exportTask = Task {
            do {
                try await editorState.export(
                    format: selectedFormat,
                    resolution: selectedResolution,
                    fps: selectedFPS,
                    outputURL: url
                )
            } catch is CancellationError {
                // Export was cancelled, no error needed
            } catch {
                await MainActor.run {
                    exportError = error.localizedDescription
                    editorState.isExporting = false
                }
            }
        }
    }
}
