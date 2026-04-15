import Foundation
import CoreImage
import CoreMedia
import AVFoundation

/// Renders the camera overlay for the compositor pipeline.
/// Handles shape masking, sizing, and positioning according to the 9-point grid.
final class CameraRenderer {

    // MARK: - Properties

    private var assetReader: AVAssetReader?
    private var videoTrackOutput: AVAssetReaderTrackOutput?
    private var lastFrame: CIImage?
    private var lastFrameTime: CMTime = .zero
    private var isReaderReady = false

    // MARK: - Public API

    /// Prepare the camera reader for the given camera.mov file.
    func prepare(cameraURL: URL) throws {
        let asset = AVAsset(url: cameraURL)
        let reader = try AVAssetReader(asset: asset)

        let videoTracks = asset.tracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else {
            throw CameraRendererError.noVideoTrack
        }

        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false

        reader.add(output)

        self.assetReader = reader
        self.videoTrackOutput = output
        self.isReaderReady = false
    }

    /// Read a camera frame at the given timestamp.
    /// For sequential export, frames are read in order.
    /// For preview (random access), creates a new reader seeking to the time.
    func readFrame(at time: CMTime, from cameraURL: URL) -> CIImage? {
        // For random-access preview: create a one-shot reader
        let asset = AVAsset(url: cameraURL)
        guard let reader = try? AVAssetReader(asset: asset) else { return nil }

        let videoTracks = asset.tracks(withMediaType: .video)
        guard let videoTrack = videoTracks.first else { return nil }

        let outputSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let output = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: outputSettings)
        output.alwaysCopiesSampleData = false

        reader.timeRange = CMTimeRange(start: time, duration: CMTime(value: 1, timescale: 30))
        reader.add(output)

        guard reader.startReading() else { return nil }

        if let sampleBuffer = output.copyNextSampleBuffer(),
           let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) {
            return CIImage(cvPixelBuffer: pixelBuffer)
        }

        return nil
    }

    /// Read the next sequential frame during export.
    func readNextFrame() -> (image: CIImage, time: CMTime)? {
        guard let reader = assetReader, let output = videoTrackOutput else { return nil }

        if !isReaderReady {
            guard reader.startReading() else { return nil }
            isReaderReady = true
        }

        guard reader.status == .reading,
              let sampleBuffer = output.copyNextSampleBuffer(),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }

        let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        let image = CIImage(cvPixelBuffer: pixelBuffer)
        lastFrame = image
        lastFrameTime = time
        return (image, time)
    }

    /// Render the camera overlay composited at the correct position/shape.
    func renderCameraOverlay(
        cameraFrame: CIImage,
        config: CameraConfig,
        outputSize: CGSize
    ) -> CIImage? {
        guard !config.hidden, config.shape != .hidden else { return nil }

        // Calculate camera overlay size
        let cameraSize = calculateCameraSize(config: config, outputSize: outputSize)

        // Scale camera frame to target size (aspect-fill)
        let scaled = scaleToFill(image: cameraFrame, targetSize: cameraSize)

        // Apply shape mask
        let masked = applyShapeMask(image: scaled, config: config, size: cameraSize)

        // Position according to 9-point grid
        let position = calculatePosition(config: config, cameraSize: cameraSize, outputSize: outputSize)

        let positioned = masked.transformed(
            by: CGAffineTransform(translationX: position.x, y: position.y)
        )

        return positioned.cropped(to: CGRect(origin: .zero, size: outputSize))
    }

    /// Reset the reader state.
    func reset() {
        assetReader?.cancelReading()
        assetReader = nil
        videoTrackOutput = nil
        lastFrame = nil
        isReaderReady = false
    }

    // MARK: - Private Helpers

    private func calculateCameraSize(config: CameraConfig, outputSize: CGSize) -> CGSize {
        let sizePercent = config.size / 100.0
        let baseSize = min(outputSize.width, outputSize.height) * CGFloat(sizePercent)

        switch config.shape {
        case .circle, .squareRounded, .square:
            return CGSize(width: baseSize, height: baseSize)
        case .roundedRect:
            return CGSize(width: baseSize, height: baseSize * 1.33)
        case .roundedRectWide:
            return CGSize(width: baseSize * 1.5, height: baseSize)
        case .hidden:
            return .zero
        }
    }

    private func scaleToFill(image: CIImage, targetSize: CGSize) -> CIImage {
        let extent = image.extent
        guard extent.width > 0, extent.height > 0 else { return image }

        let scaleX = targetSize.width / extent.width
        let scaleY = targetSize.height / extent.height
        let scale = max(scaleX, scaleY)

        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // Center crop
        let offsetX = (scaled.extent.width - targetSize.width) / 2
        let offsetY = (scaled.extent.height - targetSize.height) / 2

        return scaled
            .transformed(by: CGAffineTransform(
                translationX: -scaled.extent.origin.x - offsetX,
                y: -scaled.extent.origin.y - offsetY
            ))
            .cropped(to: CGRect(origin: .zero, size: targetSize))
    }

    private func applyShapeMask(image: CIImage, config: CameraConfig, size: CGSize) -> CIImage {
        let rect = CGRect(origin: .zero, size: size)

        switch config.shape {
        case .circle:
            return applyCircleMask(image: image, rect: rect)
        case .roundedRect, .roundedRectWide, .squareRounded:
            let radius = CGFloat(config.cornerRadius)
            return applyRoundedRectMask(image: image, rect: rect, cornerRadius: radius)
        case .square:
            // No mask needed, but crop to exact rect
            return image.cropped(to: rect)
        case .hidden:
            return CIImage.empty()
        }
    }

    private func applyCircleMask(image: CIImage, rect: CGRect) -> CIImage {
        let radius = min(rect.width, rect.height) / 2
        let center = CIVector(x: rect.midX, y: rect.midY)

        // Create a radial gradient as mask (white center, transparent edge)
        guard let radialFilter = CIFilter(name: "CIRadialGradient") else {
            return image.cropped(to: rect)
        }

        radialFilter.setValue(center, forKey: "inputCenter")
        radialFilter.setValue(radius - 1, forKey: "inputRadius0")
        radialFilter.setValue(radius, forKey: "inputRadius1")
        radialFilter.setValue(CIColor.white, forKey: "inputColor0")
        radialFilter.setValue(CIColor.clear, forKey: "inputColor1")

        guard let mask = radialFilter.outputImage?.cropped(to: rect) else {
            return image.cropped(to: rect)
        }

        // Use CIBlendWithMask to apply the circle mask
        guard let blendFilter = CIFilter(name: "CIBlendWithMask") else {
            return image.cropped(to: rect)
        }

        blendFilter.setValue(image, forKey: kCIInputImageKey)
        blendFilter.setValue(CIImage.empty(), forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(mask, forKey: kCIInputMaskImageKey)

        return blendFilter.outputImage?.cropped(to: rect) ?? image.cropped(to: rect)
    }

    private func applyRoundedRectMask(image: CIImage, rect: CGRect, cornerRadius: CGFloat) -> CIImage {
        guard let generator = CIFilter(name: "CIRoundedRectangleGenerator") else {
            // Fallback: no mask
            return image.cropped(to: rect)
        }

        generator.setValue(CIVector(
            x: rect.origin.x,
            y: rect.origin.y,
            z: rect.width,
            w: rect.height
        ), forKey: "inputExtent")
        generator.setValue(cornerRadius, forKey: "inputRadius")
        generator.setValue(CIColor.white, forKey: "inputColor")

        guard let mask = generator.outputImage else {
            return image.cropped(to: rect)
        }

        guard let blendFilter = CIFilter(name: "CIBlendWithMask") else {
            return image.cropped(to: rect)
        }

        blendFilter.setValue(image, forKey: kCIInputImageKey)
        blendFilter.setValue(CIImage.empty(), forKey: kCIInputBackgroundImageKey)
        blendFilter.setValue(mask, forKey: kCIInputMaskImageKey)

        return blendFilter.outputImage?.cropped(to: rect) ?? image.cropped(to: rect)
    }

    private func calculatePosition(config: CameraConfig, cameraSize: CGSize, outputSize: CGSize) -> CGPoint {
        let padding: CGFloat = 20

        let x: CGFloat
        let y: CGFloat

        switch config.position {
        case .topLeft:
            x = padding
            y = outputSize.height - cameraSize.height - padding
        case .topCenter:
            x = (outputSize.width - cameraSize.width) / 2
            y = outputSize.height - cameraSize.height - padding
        case .topRight:
            x = outputSize.width - cameraSize.width - padding
            y = outputSize.height - cameraSize.height - padding
        case .middleLeft:
            x = padding
            y = (outputSize.height - cameraSize.height) / 2
        case .middleCenter:
            x = (outputSize.width - cameraSize.width) / 2
            y = (outputSize.height - cameraSize.height) / 2
        case .middleRight:
            x = outputSize.width - cameraSize.width - padding
            y = (outputSize.height - cameraSize.height) / 2
        case .bottomLeft:
            x = padding
            y = padding
        case .bottomCenter:
            x = (outputSize.width - cameraSize.width) / 2
            y = padding
        case .bottomRight:
            x = outputSize.width - cameraSize.width - padding
            y = padding
        }

        return CGPoint(x: x, y: y)
    }
}

// MARK: - Errors

enum CameraRendererError: Error, LocalizedError {
    case noVideoTrack

    var errorDescription: String? {
        switch self {
        case .noVideoTrack:
            return "Camera video file contains no video track."
        }
    }
}
