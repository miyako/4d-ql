#if canImport(CoreText)
import CoreText
#endif
import Foundation
import FourDFileKit

/// Text widths for catalog diagrams, measured with the face the browser draws:
/// Helvetica Neue on macOS; Chromium substitutes Arial for Helvetica on Windows.
enum DiagramTypography {
    #if canImport(CoreText)
    private static let regular = CTFontCreateWithName("HelveticaNeue" as CFString, 12, nil)
    private static let boldFont = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, 12, nil)
    private static let italicFont = CTFontCreateWithName("HelveticaNeue-Italic" as CFString, 12, nil)
    private static let boldItalicFont = CTFontCreateWithName("HelveticaNeue-BoldItalic" as CFString, 12, nil)

    static func width(_ text: String, bold: Bool = false, italic: Bool = false) -> Double {
        let font = bold && italic ? boldItalicFont : bold ? boldFont : italic ? italicFont : regular
        let attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
        ])
        return ceil(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(attributed), nil, nil, nil))
    }
    #else
    static func width(_ text: String, bold: Bool = false, italic: Bool = false) -> Double {
        var properties = FormValue.object([])
        properties["fontFamily"] = .string("Arial")
        properties["fontWeight"] = .string(bold ? "bold" : "normal")
        if italic { properties["fontStyle"] = .string("italic") }
        return ceil(FormFontFace(size: 12, properties: properties, primary: "Arial").width(text))
    }
    #endif
}
