import Foundation
import CoreGraphics
import CoreMedia

protocol CompositorProtocol {
    /// Render a single composite frame at the given time for preview
    func renderPreviewFrame(
        projectURL: URL,
        settings: EditSettings,
        at time: CMTime
    ) async throws -> CGImage

    /// Export the full composited video
    func export(
        projectURL: URL,
        settings: EditSettings,
        outputURL: URL,
        format: ExportFormat,
        resolution: ExportResolution,
        progress: @escaping (Double) -> Void
    ) async throws
}
