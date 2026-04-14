import Foundation
import CoreGraphics

// MARK: - Cursor Data Types

/// A single cursor event in the recording timeline.
struct CursorEvent: Codable {
    /// Timestamp in seconds from start of recording
    var timestamp: Double
    /// X coordinate on screen
    var x: Double
    /// Y coordinate on screen
    var y: Double
    /// Whether the cursor was visible at this moment
    var visible: Bool
    /// Whether a click occurred at this moment
    var clicked: Bool
}

/// Complete cursor tracking data for a recording session.
struct CursorData: Codable {
    /// All cursor events in chronological order
    var events: [CursorEvent]
    /// Screen width used during recording
    var screenWidth: Double
    /// Screen height used during recording
    var screenHeight: Double
}

// MARK: - Errors

/// Errors that can occur when working with `.reco` project bundles.
enum ProjectBundleError: LocalizedError {
    case bundleNotFound(URL)
    case invalidBundle(String)
    case missingScreenTrack
    case corruptedMetadata(String)
    case corruptedSettings(String)

    var errorDescription: String? {
        switch self {
        case .bundleNotFound(let url):
            return "Project bundle not found at \(url.path)."
        case .invalidBundle(let reason):
            return "Invalid project bundle: \(reason)."
        case .missingScreenTrack:
            return "Required screen recording track (screen.mov) is missing from the bundle."
        case .corruptedMetadata(let detail):
            return "Bundle metadata is corrupted or unreadable: \(detail)."
        case .corruptedSettings(let detail):
            return "Bundle edit settings are corrupted or unreadable: \(detail)."
        }
    }
}

// MARK: - ProjectBundle

/// Represents an opened `.reco` project bundle on disk.
///
/// A `.reco` bundle is a plain directory containing media tracks, cursor data,
/// metadata, and edit settings. This struct provides read/write access to all
/// bundle contents.
struct ProjectBundle {

    // MARK: - Constants

    private enum FileName {
        static let screen = "screen.mov"
        static let camera = "camera.mov"
        static let micAudio = "audio-mic.caf"
        static let systemAudio = "audio-system.caf"
        static let cursor = "cursor.json"
        static let metadata = "metadata.json"
        static let project = "project.json"
    }

    // MARK: - Properties

    /// Root URL of the `.reco` bundle directory.
    let url: URL

    /// Recording metadata (date, duration, config, track availability).
    var metadata: ProjectMetadata

    /// Edit settings (background, cursor, camera, trim).
    var editSettings: EditSettings

    // MARK: - Computed Track URLs

    /// URL of the screen recording track, or `nil` if the file does not exist.
    var screenURL: URL? {
        existingFileURL(for: FileName.screen)
    }

    /// URL of the camera track, or `nil` if the file does not exist.
    var cameraURL: URL? {
        existingFileURL(for: FileName.camera)
    }

    /// URL of the microphone audio track, or `nil` if the file does not exist.
    var micAudioURL: URL? {
        existingFileURL(for: FileName.micAudio)
    }

    /// URL of the system audio track, or `nil` if the file does not exist.
    var systemAudioURL: URL? {
        existingFileURL(for: FileName.systemAudio)
    }

    /// URL of the cursor data file, or `nil` if the file does not exist.
    var cursorURL: URL? {
        existingFileURL(for: FileName.cursor)
    }

    // MARK: - Private Init

    private init(url: URL, metadata: ProjectMetadata, editSettings: EditSettings) {
        self.url = url
        self.metadata = metadata
        self.editSettings = editSettings
    }

    // MARK: - Lifecycle

    /// Creates a new `.reco` bundle directory with default metadata and settings.
    ///
    /// - Parameters:
    ///   - directory: Parent directory where the bundle will be created.
    ///   - name: Name for the bundle (`.reco` extension is appended automatically).
    /// - Returns: An opened `ProjectBundle` pointing at the new directory.
    static func create(at directory: URL, name: String) throws -> ProjectBundle {
        let bundleName = name.hasSuffix(".reco") ? name : "\(name).reco"
        let bundleURL = directory.appendingPathComponent(bundleName)

        let fm = FileManager.default
        try fm.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        let metadata = ProjectMetadata.makeDefault()
        let editSettings = EditSettings()

        var bundle = ProjectBundle(url: bundleURL, metadata: metadata, editSettings: editSettings)
        try bundle.saveMetadata()
        try bundle.saveEditSettings()

        return bundle
    }

    /// Opens an existing `.reco` bundle from disk.
    ///
    /// Reads `metadata.json` and `project.json`. If `project.json` is missing,
    /// default edit settings are used and persisted.
    ///
    /// - Parameter url: Path to the `.reco` directory.
    /// - Returns: An opened `ProjectBundle`.
    static func open(at url: URL) throws -> ProjectBundle {
        let fm = FileManager.default
        var isDir: ObjCBool = false

        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw ProjectBundleError.bundleNotFound(url)
        }

        // Read metadata
        let metadataURL = url.appendingPathComponent(FileName.metadata)
        let metadata: ProjectMetadata
        do {
            let data = try Data(contentsOf: metadataURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            metadata = try decoder.decode(ProjectMetadata.self, from: data)
        } catch let error as DecodingError {
            throw ProjectBundleError.corruptedMetadata(error.localizedDescription)
        } catch {
            throw ProjectBundleError.corruptedMetadata(error.localizedDescription)
        }

        // Read edit settings (use defaults if file is missing)
        let settingsURL = url.appendingPathComponent(FileName.project)
        let editSettings: EditSettings
        if fm.fileExists(atPath: settingsURL.path) {
            do {
                let data = try Data(contentsOf: settingsURL)
                editSettings = try JSONDecoder().decode(EditSettings.self, from: data)
            } catch let error as DecodingError {
                throw ProjectBundleError.corruptedSettings(error.localizedDescription)
            } catch {
                throw ProjectBundleError.corruptedSettings(error.localizedDescription)
            }
        } else {
            editSettings = EditSettings()
        }

        return ProjectBundle(url: url, metadata: metadata, editSettings: editSettings)
    }

    // MARK: - Persistence

    /// Writes current edit settings to `project.json` inside the bundle.
    func saveEditSettings() throws {
        let settingsURL = url.appendingPathComponent(FileName.project)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(editSettings)
        try data.write(to: settingsURL, options: .atomic)
    }

    /// Writes current metadata to `metadata.json` inside the bundle.
    func saveMetadata() throws {
        let metadataURL = url.appendingPathComponent(FileName.metadata)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(metadata)
        try data.write(to: metadataURL, options: .atomic)
    }

    // MARK: - Validation

    /// Validates that the bundle contains all required files.
    ///
    /// The screen recording track (`screen.mov`) is always required.
    /// Optional tracks are checked against metadata flags.
    func validate() throws {
        let fm = FileManager.default
        var isDir: ObjCBool = false

        // Bundle directory must exist
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw ProjectBundleError.bundleNotFound(url)
        }

        // screen.mov is required
        let screenPath = url.appendingPathComponent(FileName.screen).path
        guard fm.fileExists(atPath: screenPath) else {
            throw ProjectBundleError.missingScreenTrack
        }

        // metadata.json must exist
        let metadataPath = url.appendingPathComponent(FileName.metadata).path
        guard fm.fileExists(atPath: metadataPath) else {
            throw ProjectBundleError.invalidBundle("metadata.json is missing")
        }

        // Verify optional tracks match metadata claims
        if metadata.hasCamera {
            let cameraPath = url.appendingPathComponent(FileName.camera).path
            if !fm.fileExists(atPath: cameraPath) {
                throw ProjectBundleError.invalidBundle("metadata claims camera track exists but camera.mov is missing")
            }
        }

        if metadata.hasMicAudio {
            let micPath = url.appendingPathComponent(FileName.micAudio).path
            if !fm.fileExists(atPath: micPath) {
                throw ProjectBundleError.invalidBundle("metadata claims mic audio exists but audio-mic.caf is missing")
            }
        }

        if metadata.hasSystemAudio {
            let sysPath = url.appendingPathComponent(FileName.systemAudio).path
            if !fm.fileExists(atPath: sysPath) {
                throw ProjectBundleError.invalidBundle("metadata claims system audio exists but audio-system.caf is missing")
            }
        }

        if metadata.hasCursorData {
            let cursorPath = url.appendingPathComponent(FileName.cursor).path
            if !fm.fileExists(atPath: cursorPath) {
                throw ProjectBundleError.invalidBundle("metadata claims cursor data exists but cursor.json is missing")
            }
        }
    }

    // MARK: - Cursor Data

    /// Loads and parses cursor tracking data from `cursor.json`.
    ///
    /// - Returns: Parsed `CursorData` containing all cursor events.
    func loadCursorData() throws -> CursorData {
        let cursorFileURL = url.appendingPathComponent(FileName.cursor)
        let fm = FileManager.default

        guard fm.fileExists(atPath: cursorFileURL.path) else {
            throw ProjectBundleError.invalidBundle("cursor.json does not exist in the bundle")
        }

        do {
            let data = try Data(contentsOf: cursorFileURL)
            return try JSONDecoder().decode(CursorData.self, from: data)
        } catch let error as DecodingError {
            throw ProjectBundleError.corruptedMetadata("cursor.json is malformed: \(error.localizedDescription)")
        } catch {
            throw ProjectBundleError.corruptedMetadata("Failed to read cursor.json: \(error.localizedDescription)")
        }
    }

    // MARK: - Background Image Import

    /// Copies an image file into the bundle for use as a custom background.
    ///
    /// The image is stored at the root of the bundle directory. If a file with
    /// the same name already exists, it is overwritten.
    ///
    /// - Parameter sourceURL: Path to the source image file.
    /// - Returns: The relative path of the image within the bundle (e.g., `"background.png"`).
    @discardableResult
    func importBackgroundImage(from sourceURL: URL) throws -> String {
        let fm = FileManager.default

        guard fm.fileExists(atPath: sourceURL.path) else {
            throw ProjectBundleError.invalidBundle("Source image file does not exist at \(sourceURL.path)")
        }

        let ext = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension
        let destinationName = "background.\(ext)"
        let destinationURL = url.appendingPathComponent(destinationName)

        // Remove existing file if present
        if fm.fileExists(atPath: destinationURL.path) {
            try fm.removeItem(at: destinationURL)
        }

        try fm.copyItem(at: sourceURL, to: destinationURL)

        return destinationName
    }

    // MARK: - Helpers

    /// Returns the URL for a file inside the bundle if it exists on disk, otherwise `nil`.
    private func existingFileURL(for fileName: String) -> URL? {
        let fileURL = url.appendingPathComponent(fileName)
        return FileManager.default.fileExists(atPath: fileURL.path) ? fileURL : nil
    }
}
