import CoreText
import Foundation

enum DiagramTypography {
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
}
