import Foundation
import CoreImage

/// Per-frame compositing engine using CoreImage.
/// Layers: Background -> Screen (scaled, rounded, shadowed) -> Cursor -> Camera
final class FrameRenderer {

    // MARK: - Properties

    /// Reuse CIContext across all frames for performance.
    /// Uses GPU rendering by default.
    let ciContext: CIContext

    private let backgroundRenderer: BackgroundRenderer

    // MARK: - Init

    init() {
        self.ciContext = CIContext(options: [
            .useSoftwareRenderer: false,
            .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
            .outputColorSpace: CGColorSpaceCreateDeviceRGB()
        ])
        self.backgroundRenderer = BackgroundRenderer()
    }

    // MARK: - Public API

    /// Composite a single frame with all layers.
    ///
    /// - Parameters:
    ///   - screenFrame: The raw screen recording frame
    ///   - cursorOverlay: Optional cursor overlay (already positioned)
    ///   - cameraFrame: Optional camera overlay (already positioned and masked)
    ///   - settings: Edit settings controlling background, scaling, etc.
    ///   - outputSize: The final output frame size
    /// - Returns: The fully composited CIImage
    func renderFrame(
        screenFrame: CIImage,
        cursorOverlay: CIImage?,
        cameraFrame: CIImage?,
        settings: EditSettings,
        outputSize: CGSize
    ) -> CIImage {
        let outputRect = CGRect(origin: .zero, size: outputSize)

        // Layer 0: Background
        var result = backgroundRenderer.renderBackground(
            config: settings.background,
            size: outputSize
        )

        // Layer 1: Screen frame (scaled, rounded corners, shadow)
        let screenLayer = renderScreenLayer(
            screenFrame: screenFrame,
            config: settings.background,
            outputSize: outputSize
        )
        result = compositeOver(foreground: screenLayer, background: result)
            .cropped(to: outputRect)

        // Layer 2: Cursor overlay
        if let cursor = cursorOverlay {
            result = compositeOver(foreground: cursor, background: result)
                .cropped(to: outputRect)
        }

        // Layer 3: Camera overlay
        if let camera = cameraFrame {
            result = compositeOver(foreground: camera, background: result)
                .cropped(to: outputRect)
        }

        return result
    }

    /// Render a CGImage from a CIImage for preview display.
    func renderToCGImage(_ ciImage: CIImage, size: CGSize) -> CGImage? {
        let rect = CGRect(origin: .zero, size: size)
        return ciContext.createCGImage(ciImage, from: rect)
    }

    /// Calculate the screen frame rect within the output (for cursor coordinate mapping).
    func screenRect(
        screenSize: CGSize,
        config: BackgroundConfig,
        outputSize: CGSize
    ) -> CGRect {
        let scale = CGFloat(config.screenScale / 100.0)
        let scaledWidth = outputSize.width * scale
        let scaledHeight: CGFloat

        // Maintain aspect ratio of the original screen
        if screenSize.width > 0 && screenSize.height > 0 {
            let aspectRatio = screenSize.height / screenSize.width
            scaledHeight = scaledWidth * aspectRatio
        } else {
            scaledHeight = outputSize.height * scale
        }

        let x = (outputSize.width - scaledWidth) / 2
        let y = (outputSize.height - scaledHeight) / 2

        return CGRect(x: x, y: y, width: scaledWidth, height: scaledHeight)
    }

    // MARK: - Private

    /// Render the screen layer: scale, round corners, add shadow.
    private func renderScreenLayer(
        screenFrame: CIImage,
        config: BackgroundConfig,
        outputSize: CGSize
    ) -> CIImage {
        let screenSize = screenFrame.extent.size
        let targetRect = screenRect(
            screenSize: screenSize,
            config: config,
            outputSize: outputSize
        )

        // Scale screen frame to target size
        let scaleX = targetRect.width / screenSize.width
        let scaleY = targetRect.height / screenSize.height
        var scaled = screenFrame.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

        // Move to origin for processing
        scaled = scaled.transformed(
            by: CGAffineTransform(
                translationX: -scaled.extent.origin.x,
                y: -scaled.extent.origin.y
            )
        )

        let scaledRect = CGRect(origin: .zero, size: targetRect.size)

        // Apply corner radius
        let cornerRadius = CGFloat(config.cornerRadius)
        if cornerRadius > 0 {
            scaled = applyCornerRadius(image: scaled, rect: scaledRect, radius: cornerRadius)
        }

        // Apply drop shadow
        if config.shadowOpacity > 0 && config.shadowSize > 0 {
            scaled = applyShadow(
                image: scaled,
                rect: scaledRect,
                shadowSize: CGFloat(config.shadowSize),
                shadowOpacity: config.shadowOpacity / 100.0,
                shadowBlur: CGFloat(config.shadowBlur)
            )
        }

        // Position at center of output
        let positioned = scaled.transformed(
            by: CGAffineTransform(translationX: targetRect.origin.x, y: targetRect.origin.y)
        )

        return positioned
    }

    /// Apply corner radius using a rounded rectangle mask.
    private func applyCornerRadius(image: CIImage, rect: CGRect, radius: CGFloat) -> CIImage {
        guard let generator = CIFilter(name: "CIRoundedRectangleGenerator") else {
            return image.cropped(to: rect)
        }

        generator.setValue(CIVector(
            x: rect.origin.x,
            y: rect.origin.y,
            z: rect.width,
            w: rect.height
        ), forKey: "inputExtent")
        generator.setValue(radius, forKey: "inputRadius")
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

        return blendFilter.outputImage ?? image.cropped(to: rect)
    }

    /// Apply a drop shadow beneath the image.
    private func applyShadow(
        image: CIImage,
        rect: CGRect,
        shadowSize: CGFloat,
        shadowOpacity: Double,
        shadowBlur: CGFloat
    ) -> CIImage {
        // Create a shadow by blurring a black silhouette of the image
        let alpha = CIColor(red: 0, green: 0, blue: 0, alpha: CGFloat(shadowOpacity))

        // Create black silhouette
        guard let colorMatrix = CIFilter(name: "CIColorMatrix") else {
            return image
        }

        // Make everything black but keep alpha
        colorMatrix.setValue(image, forKey: kCIInputImageKey)
        colorMatrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputRVector")
        colorMatrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputGVector")
        colorMatrix.setValue(CIVector(x: 0, y: 0, z: 0, w: 0), forKey: "inputBVector")
        colorMatrix.setValue(CIVector(x: 0, y: 0, z: 0, w: CGFloat(shadowOpacity)), forKey: "inputAVector")

        guard let silhouette = colorMatrix.outputImage else { return image }

        // Blur the silhouette
        guard let blurFilter = CIFilter(name: "CIGaussianBlur") else {
            return image
        }

        blurFilter.setValue(silhouette, forKey: kCIInputImageKey)
        blurFilter.setValue(shadowBlur, forKey: kCIInputRadiusKey)

        guard let shadow = blurFilter.outputImage else { return image }

        // Offset shadow slightly downward
        let offsetShadow = shadow.transformed(
            by: CGAffineTransform(translationX: 0, y: -shadowSize * 0.3)
        )

        // Composite: shadow behind image
        return compositeOver(foreground: image, background: offsetShadow)
    }

    /// Source-over compositing.
    private func compositeOver(foreground: CIImage, background: CIImage) -> CIImage {
        guard let filter = CIFilter(name: "CISourceOverCompositing") else {
            return foreground
        }
        filter.setValue(foreground, forKey: kCIInputImageKey)
        filter.setValue(background, forKey: kCIInputBackgroundImageKey)
        return filter.outputImage ?? foreground
    }
}
