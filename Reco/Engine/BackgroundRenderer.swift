import Foundation
import CoreImage
import AppKit

/// Renders background layers for the compositor pipeline.
/// Supports solid color, gradient, wallpaper, and custom image backgrounds.
/// Caches the rendered background across frames for performance.
final class BackgroundRenderer {

    // MARK: - Cached State

    private var cachedBackground: CIImage?
    private var cachedConfig: BackgroundConfig?
    private var cachedSize: CGSize?

    // MARK: - Public API

    /// Returns a `CIImage` background for the given size and config.
    /// Caches the result so repeated calls with the same config/size are free.
    func renderBackground(config: BackgroundConfig, size: CGSize) -> CIImage {
        // Return cached if config and size haven't changed
        if let cached = cachedBackground,
           let prevConfig = cachedConfig,
           let prevSize = cachedSize,
           prevSize == size,
           configsEqual(prevConfig, config) {
            return cached
        }

        let image: CIImage
        switch config.type {
        case .solidColor:
            image = renderSolidColor(hex: config.solidColor, size: size)
        case .gradient:
            image = renderGradient(
                colors: config.gradientColors,
                angle: config.gradientAngle,
                size: size
            )
        case .wallpaper:
            image = renderWallpaper(name: config.wallpaperName, size: size)
        case .customImage:
            image = renderCustomImage(path: config.customImagePath, size: size)
        }

        cachedBackground = image
        cachedConfig = config
        cachedSize = size
        return image
    }

    /// Invalidates the cache, forcing re-render on next call.
    func invalidateCache() {
        cachedBackground = nil
        cachedConfig = nil
        cachedSize = nil
    }

    // MARK: - Private Renderers

    private func renderSolidColor(hex: String, size: CGSize) -> CIImage {
        let color = CIColor(cgColor: cgColor(fromHex: hex))
        return CIImage(color: color).cropped(to: CGRect(origin: .zero, size: size))
    }

    private func renderGradient(colors: [String], angle: Double, size: CGSize) -> CIImage {
        let color0 = colors.count > 0 ? CIColor(cgColor: cgColor(fromHex: colors[0])) : CIColor.black
        let color1 = colors.count > 1 ? CIColor(cgColor: cgColor(fromHex: colors[1])) : CIColor.white

        // Convert angle (degrees) to start/end points on the rect
        let radians = angle * .pi / 180.0
        let centerX = size.width / 2
        let centerY = size.height / 2
        let diagonal = sqrt(size.width * size.width + size.height * size.height) / 2

        let startX = centerX - cos(radians) * diagonal
        let startY = centerY - sin(radians) * diagonal
        let endX = centerX + cos(radians) * diagonal
        let endY = centerY + sin(radians) * diagonal

        guard let filter = CIFilter(name: "CILinearGradient") else {
            return renderSolidColor(hex: "#000000", size: size)
        }

        filter.setValue(CIVector(x: startX, y: startY), forKey: "inputPoint0")
        filter.setValue(CIVector(x: endX, y: endY), forKey: "inputPoint1")
        filter.setValue(color0, forKey: "inputColor0")
        filter.setValue(color1, forKey: "inputColor1")

        guard let output = filter.outputImage else {
            return renderSolidColor(hex: "#000000", size: size)
        }

        return output.cropped(to: CGRect(origin: .zero, size: size))
    }

    private func renderWallpaper(name: String?, size: CGSize) -> CIImage {
        guard let wallpaperName = name else {
            return renderSolidColor(hex: "#000000", size: size)
        }

        // Try loading from bundled Resources/Wallpapers/
        if let url = Bundle.main.url(
            forResource: wallpaperName,
            withExtension: nil,
            subdirectory: "Wallpapers"
        ), let image = CIImage(contentsOf: url) {
            return scaleToFill(image: image, size: size)
        }

        // Try common extensions
        for ext in ["jpg", "jpeg", "png", "heic"] {
            if let url = Bundle.main.url(
                forResource: wallpaperName,
                withExtension: ext,
                subdirectory: "Wallpapers"
            ), let image = CIImage(contentsOf: url) {
                return scaleToFill(image: image, size: size)
            }
        }

        return renderSolidColor(hex: "#000000", size: size)
    }

    private func renderCustomImage(path: String?, size: CGSize) -> CIImage {
        guard let imagePath = path else {
            return renderSolidColor(hex: "#000000", size: size)
        }

        let url = URL(fileURLWithPath: imagePath)
        guard let image = CIImage(contentsOf: url) else {
            return renderSolidColor(hex: "#000000", size: size)
        }

        return scaleToFill(image: image, size: size)
    }

    // MARK: - Helpers

    /// Scale an image to fill the target size (aspect-fill, centered).
    private func scaleToFill(image: CIImage, size: CGSize) -> CIImage {
        let imageExtent = image.extent
        guard imageExtent.width > 0, imageExtent.height > 0 else {
            return renderSolidColor(hex: "#000000", size: size)
        }

        let scaleX = size.width / imageExtent.width
        let scaleY = size.height / imageExtent.height
        let scale = max(scaleX, scaleY)

        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let offsetX = (scaled.extent.width - size.width) / 2
        let offsetY = (scaled.extent.height - size.height) / 2

        return scaled
            .transformed(by: CGAffineTransform(translationX: -scaled.extent.origin.x - offsetX,
                                                y: -scaled.extent.origin.y - offsetY))
            .cropped(to: CGRect(origin: .zero, size: size))
    }

    /// Parse a hex color string to CGColor.
    private func cgColor(fromHex hex: String) -> CGColor {
        var hexStr = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if hexStr.hasPrefix("#") { hexStr.removeFirst() }

        var rgb: UInt64 = 0
        Scanner(string: hexStr).scanHexInt64(&rgb)

        let r = CGFloat((rgb >> 16) & 0xFF) / 255.0
        let g = CGFloat((rgb >> 8) & 0xFF) / 255.0
        let b = CGFloat(rgb & 0xFF) / 255.0

        return CGColor(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }

    /// Simple equality check for BackgroundConfig (since it's Codable but not Equatable).
    private func configsEqual(_ a: BackgroundConfig, _ b: BackgroundConfig) -> Bool {
        a.type == b.type
            && a.wallpaperName == b.wallpaperName
            && a.gradientColors == b.gradientColors
            && a.gradientAngle == b.gradientAngle
            && a.solidColor == b.solidColor
            && a.customImagePath == b.customImagePath
            && a.screenScale == b.screenScale
            && a.shadowSize == b.shadowSize
            && a.shadowOpacity == b.shadowOpacity
            && a.shadowBlur == b.shadowBlur
            && a.cornerRadius == b.cornerRadius
    }
}
