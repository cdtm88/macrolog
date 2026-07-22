import UIKit
import ImageIO

/// Prepares captured or library-selected images for transmission:
/// - normalises EXIF orientation so the model always receives an upright image
///   regardless of device orientation at capture (EST-08);
/// - downscales and JPEG-compresses so no request payload exceeds ~2MB after
///   base64 expansion (PERF-04).
enum ImageProcessing {

    /// Target ceiling for the *base64-encoded* payload. Base64 inflates bytes by
    /// ~4/3, so we keep the raw JPEG comfortably under 1.4MB.
    private static let maxBase64Bytes = 2 * 1024 * 1024
    private static let maxRawBytes = Int(Double(maxBase64Bytes) * 0.72) // ≈1.44MB

    /// Longest-edge cap. Vision quality plateaus well before this, and it keeps
    /// the payload small.
    private static let maxDimension: CGFloat = 1024

    struct Prepared {
        let base64: String
        let mediaType: String // always "image/jpeg"
    }

    /// Returns a base64 JPEG that is upright and under the size ceiling, or nil
    /// if the image cannot be rendered.
    static func prepare(_ image: UIImage) -> Prepared? {
        // `redraw` bakes any orientation flag into the pixels (EXIF normalisation).
        let upright = redraw(downscaled(image))

        // Step compression down until we're under the raw ceiling.
        var quality: CGFloat = 0.8
        var data = upright.jpegData(compressionQuality: quality)
        while let d = data, d.count > maxRawBytes, quality > 0.3 {
            quality -= 0.1
            data = upright.jpegData(compressionQuality: quality)
        }
        guard let finalData = data else { return nil }
        return Prepared(base64: finalData.base64EncodedString(), mediaType: "image/jpeg")
    }

    private static func downscaled(_ image: UIImage) -> UIImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    /// Draws the image into a fresh context, collapsing its `imageOrientation`
    /// into the pixel data so the transmitted bytes are always upright.
    private static func redraw(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}
