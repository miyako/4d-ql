import AppKit
import CoreText
import FourDFileKit

struct FormTextLayout {
    // An explicit text face keeps CoreText measurement and WebKit SVG widths aligned.
    static let fallbackFamily = "SF Pro Text, -apple-system, Helvetica Neue, sans-serif"
    struct Line {
        let text: String
        let ascent: Double
        let descent: Double
        let width: Double
    }

    let lines: [Line]
    let lineHeight: Double

    static func bounded(_ text: String) -> String {
        let source = text as NSString
        guard source.length > 4_096 else { return text }
        let last = source.rangeOfComposedCharacterSequence(at: 4_095)
        let end = NSMaxRange(last) > 4_096 ? last.location : 4_096
        return source.substring(to: end)
    }

    static func font(size: Double, properties: FormValue) -> NSFont {
        let family = properties["fontFamily"]?.string
        let base = family.flatMap { $0.hasPrefix("%") ? nil : NSFont(name: $0, size: size) }
            ?? NSFont(name: "SF Pro Text", size: size) ?? NSFont.systemFont(ofSize: size)
        var traits = base.fontDescriptor.symbolicTraits
        if properties["fontWeight"]?.string == "bold"
            || properties["fontWeight"] == nil && properties["fontTheme"]?.string == "main" { traits.insert(.bold) }
        if properties["fontStyle"]?.string == "italic" { traits.insert(.italic) }
        return NSFont(descriptor: base.fontDescriptor.withSymbolicTraits(traits), size: size) ?? base
    }

    init(text: String, width: Double, size: Double, properties: FormValue, maxLines: Int) {
        let font = Self.font(size: size, properties: properties)
        let fontLineHeight = ceil(Double(font.ascender - font.descender + font.leading))
        let normalized = Self.bounded(text)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let noWrap = properties["multiline"]?.string == "no"
            || properties["wordwrap"]?.string == "none" || maxLines <= 1
        let source = (noWrap ? normalized.components(separatedBy: "\n").first ?? "" : normalized) as NSString
        let attributed = NSAttributedString(string: source as String, attributes: [.font: font])
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        var result: [Line] = []
        var offset = 0
        let limit = max(1, min(100, maxLines))

        func append(_ range: NSRange) {
            let visible = source.substring(with: range).replacingOccurrences(of: "\n", with: "")
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: visible, attributes: [.font: font]))
            var ascent: CGFloat = 0
            var descent: CGFloat = 0
            var leading: CGFloat = 0
            let advance = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            result.append(Line(text: visible, ascent: max(Double(ascent), Double(font.ascender)),
                               descent: max(Double(descent), Double(-font.descender)), width: advance))
        }

        if noWrap || source.length == 0 {
            append(NSRange(location: 0, length: source.length))
        } else {
            while offset < source.length && result.count < limit {
                let suggested = CTTypesetterSuggestLineBreak(typesetter, offset, max(0, width))
                // A glyph wider than the box still needs one complete grapheme to make progress.
                let count = suggested > 0 ? suggested : source.rangeOfComposedCharacterSequence(at: offset).length
                let range = NSRange(location: offset, length: min(count, source.length - offset))
                append(range)
                offset += range.length
            }
            if offset == source.length && normalized.hasSuffix("\n") && result.count < limit {
                append(NSRange(location: source.length, length: 0))
            }
        }
        lines = result
        lineHeight = max(size * 1.2, fontLineHeight, ceil(result.map { $0.ascent + $0.descent }.max() ?? fontLineHeight))
    }
}
