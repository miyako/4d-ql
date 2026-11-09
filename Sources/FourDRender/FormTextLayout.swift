import Foundation
import FourDFileKit

struct FormTextLayout {
    // An explicit text face keeps platform measurement and browser SVG widths aligned.
    static let fallbackFamily = "SF Pro Text, -apple-system, Helvetica Neue, sans-serif"
    struct Line {
        let text: String
        let ascent: Double
        let descent: Double
        let width: Double
        let endsParagraph: Bool
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

    static func font(size: Double, properties: FormValue, platform: FormPlatform = .macOS) -> FormFontFace {
        FormFontFace(size: size, properties: properties, primary: FormPlatformStyle(platform).primaryFamily)
    }

    init(text: String, width: Double, size: Double, properties: FormValue, maxLines: Int, platform: FormPlatform = .macOS) {
        let font = Self.font(size: size, properties: properties, platform: platform)
        let fontLineHeight = font.lineHeight
        let normalized = Self.bounded(text)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let singleLine = properties["multiline"]?.string == "no" || maxLines <= 1
        let noWrap = properties["wordwrap"]?.string == "none"
        let source = (singleLine ? normalized.components(separatedBy: "\n").first ?? "" : normalized) as NSString
        var result: [Line] = []
        var offset = 0
        let limit = max(1, min(100, maxLines))

        func append(_ range: NSRange, endsParagraph: Bool? = nil) {
            let visible = source.substring(with: range).replacingOccurrences(of: "\n", with: "")
            let bounds = font.line(visible)
            result.append(Line(text: visible, ascent: bounds.ascent, descent: bounds.descent, width: bounds.width,
                               endsParagraph: endsParagraph ?? (NSMaxRange(range) == source.length
                                   || source.substring(with: range).contains("\n"))))
        }

        if singleLine || source.length == 0 {
            append(NSRange(location: 0, length: source.length))
        } else if noWrap {
            for paragraph in normalized.components(separatedBy: "\n").prefix(limit) {
                let length = (paragraph as NSString).length
                append(NSRange(location: offset, length: length), endsParagraph: true)
                offset += length+1
            }
        } else {
            let suggest = font.lineBreaker(for: source)
            while offset < source.length && result.count < limit {
                let suggested = suggest(offset, max(0, width))
                // A glyph wider than the box still needs one complete grapheme to make progress.
                var count = suggested > 0 ? suggested : source.rangeOfComposedCharacterSequence(at: offset).length
                if offset + count < source.length {
                    // Never end a line inside a composed character sequence.
                    count = NSMaxRange(source.rangeOfComposedCharacterSequence(at: offset + count - 1)) - offset
                }
                let range = NSRange(location: offset, length: min(count, source.length - offset))
                append(range)
                offset += range.length
            }
            if offset == source.length && normalized.hasSuffix("\n") && result.count < limit {
                append(NSRange(location: source.length, length: 0))
            }
        }
        lines = result
        lineHeight = max(fontLineHeight, ceil(result.map { $0.ascent + $0.descent }.max() ?? fontLineHeight))
    }
}
