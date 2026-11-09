import Foundation
#if canImport(ImageIO)
import ImageIO
import UniformTypeIdentifiers
#elseif os(Windows)
import CFourDWindows
#endif

/// Passive raster conversion for form pictures: decode the first frame, apply
/// orientation, downsample to 2,048 pixels and re-encode as PNG. ImageIO is the
/// macOS backend and Windows Imaging Component the Windows backend; both apply
/// the same 32-megapixel source and 4 MiB output limits.
enum FormRasterImage {
    static let maxSourcePixels = 32_000_000.0
    static let maxPixelSize = 2_048
    static let maxEncodedBytes = 4 * 1024 * 1024

    static func convert(_ data: Data) throws -> (png: Data, width: Double, height: Double) {
        #if canImport(ImageIO)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue > 0, height.doubleValue > 0,
              width.doubleValue * height.doubleValue <= maxSourcePixels,
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
              ] as CFDictionary) else { throw FormError.dependency("Unsupported image or image exceeds 32 megapixels.") }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw FormError.dependency("Cannot create preview image.")
        }
        CGImageDestinationAddImage(destination, thumbnail, nil)
        guard CGImageDestinationFinalize(destination) else { throw FormError.dependency("Cannot encode preview image.") }
        guard output.length <= maxEncodedBytes else { throw FormError.limit("Converted image exceeds 4 MiB.") }
        return (output as Data, width.doubleValue, height.doubleValue)
        #elseif os(Windows)
        var png: UnsafeMutablePointer<UInt8>?
        var length = 0
        var width: UInt32 = 0
        var height: UInt32 = 0
        let status = data.withUnsafeBytes { bytes in
            fdw_image_to_png(bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count, UInt32(maxPixelSize),
                             maxSourcePixels, &png, &length, &width, &height)
        }
        defer { fdw_free(png) }
        switch status {
        case 0: break
        case 3: throw FormError.dependency("Cannot encode preview image.")
        default: throw FormError.dependency("Unsupported image or image exceeds 32 megapixels.")
        }
        guard length <= maxEncodedBytes else { throw FormError.limit("Converted image exceeds 4 MiB.") }
        guard let png else { throw FormError.dependency("Cannot encode preview image.") }
        return (Data(bytes: png, count: length), Double(width), Double(height))
        #else
        throw FormError.dependency("Raster pictures are not supported on this platform.")
        #endif
    }
}
