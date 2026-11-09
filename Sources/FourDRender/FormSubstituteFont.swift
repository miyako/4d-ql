import Foundation
#if canImport(AppKit)
import AppKit
import CoreText
#endif

/// Selawik stands in for Segoe UI when Windows appearances are previewed on a
/// host without Segoe UI, such as Quick Look on macOS. Segoe UI cannot be
/// redistributed; Selawik is Microsoft's open-source, metric-compatible
/// fallback whose Latin advance widths and OS/2 Windows metrics match Segoe UI.
/// Text is measured with the embedded TrueType files and drawn with the
/// embedded WOFF2 files, so measurement and drawing use the same outlines.
enum FormSubstituteFont {
    static let family = "Selawik"
    static let replaces = "Segoe UI"
    /// Segoe UI's usWinAscent, usWinDescent and cap height per em (2210, 514 and
    /// 1434 of 2048), which DirectWrite uses on Windows. Selawik's OS/2 table
    /// matches; its hhea table, which CoreText reads, is shorter.
    static let ascent = 2210.0 / 2048
    static let descent = 514.0 / 2048
    static let capHeight = 1434.0 / 2048

    /// Whether Windows form text is substituted on this host.
    static let isNeeded = !FormFontFace.installed(replaces, size: 12)

    /// `@font-face` rules for the embedded web fonts (needs `font-src data:`).
    static var css: String {
        "@font-face{font-family:Selawik;font-style:normal;font-weight:400;src:url(data:font/woff2;base64,\(regularWOFF2)) format(\"woff2\")}"
            + "@font-face{font-family:Selawik;font-style:normal;font-weight:700;src:url(data:font/woff2;base64,\(boldWOFF2)) format(\"woff2\")}"
    }

    #if canImport(AppKit)
    private static let descriptors: [CTFontDescriptor?] = [regularTrueType, boldTrueType].map {
        Data(base64Encoded: $0).flatMap { CTFontManagerCreateFontDescriptorFromData($0 as CFData) }
    }

    static func font(size: Double, bold: Bool) -> NSFont? {
        guard let descriptor = descriptors[bold ? 1 : 0] else { return nil }
        return CTFontCreateWithFontDescriptor(descriptor, CGFloat(size), nil) as NSFont
    }
    #endif
}
