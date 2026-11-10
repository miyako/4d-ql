import Foundation
import FourDFileKit
#if canImport(AppKit)
import AppKit
import CoreText
#elseif os(Windows)
import CFourDWindows
#endif

/// Platform font service for form text. CoreText/AppKit measure on macOS and
/// DirectWrite on Windows; the wrapping, clipping and baseline algorithms in
/// `FormTextLayout` and `FormPreviewRenderer` are shared.
struct FormFontFace {
    let size: Double
    let ascent: Double
    let descent: Double
    let capHeight: Double
    /// The platform's default line advance for this face.
    let lineHeight: Double
    /// The platform's default first-baseline offset for this face.
    let baselineOffset: Double
    #if canImport(AppKit)
    let font: NSFont
    #elseif os(Windows)
    private let handle: FormDirectWriteFont
    #endif

    /// Whether a named family is installed for measurement.
    static func installed(_ family: String, size: Double) -> Bool {
        #if canImport(AppKit)
        return NSFont(name: family, size: size) != nil
        #elseif os(Windows)
        return family.withCString(encodedAs: UTF16.self) { fdw_font_family_exists($0) } != 0
        #else
        return false
        #endif
    }

    init(size: Double, properties: FormValue, primary: String) {
        let bold = properties["fontWeight"]?.string == "bold"
            || properties["fontWeight"] == nil && properties["fontTheme"]?.string == "main"
        let italic = properties["fontStyle"]?.string == "italic"
        let family = properties["fontFamily"]?.string.flatMap { $0.hasPrefix("%") ? nil : $0 }
        self.size = size
        #if canImport(AppKit)
        let named = family.flatMap { NSFont(name: $0, size: size) } ?? NSFont(name: primary, size: size)
        if named == nil, primary == FormSubstituteFont.replaces, FormSubstituteFont.isNeeded,
           let substitute = FormSubstituteFont.font(size: size, bold: bold) {
            // Mirror the DirectWrite line metrics used for Segoe UI on Windows.
            font = substitute
            let lineAscent = size * FormSubstituteFont.ascent
            let lineDescent = size * FormSubstituteFont.descent
            ascent = lineAscent
            descent = lineDescent
            capHeight = size * FormSubstituteFont.capHeight
            lineHeight = lineAscent.rounded() + lineDescent.rounded()
            baselineOffset = lineAscent.rounded()
        } else {
            let base = named ?? NSFont.systemFont(ofSize: size)
            var traits = base.fontDescriptor.symbolicTraits
            if bold { traits.insert(.bold) }
            if italic { traits.insert(.italic) }
            font = NSFont(descriptor: base.fontDescriptor.withSymbolicTraits(traits), size: size) ?? base
            ascent = Double(font.ascender)
            descent = Double(-font.descender)
            capHeight = Double(font.capHeight)
            lineHeight = Double(NSLayoutManager().defaultLineHeight(for: font))
            baselineOffset = Double(NSLayoutManager().defaultBaselineOffset(for: font))
        }
        #elseif os(Windows)
        handle = FormDirectWriteFont.cached(family: family, primary: primary, size: size, bold: bold, italic: italic)
        ascent = handle.metrics.ascent
        descent = handle.metrics.descent
        capHeight = handle.metrics.capHeight
        // Chromium and GDI round each component before summing the default line advance.
        lineHeight = (handle.metrics.ascent).rounded() + (handle.metrics.descent).rounded() + (handle.metrics.lineGap).rounded()
        baselineOffset = (handle.metrics.ascent).rounded()
        #else
        ascent = size * 0.8
        descent = size * 0.2
        capHeight = size * 0.7
        lineHeight = size * 1.2
        baselineOffset = size * 0.8
        #endif
    }

    func width(_ text: String) -> Double {
        #if canImport(AppKit)
        return (text as NSString).size(withAttributes: [.font: font]).width
        #elseif os(Windows)
        return handle.width(text)
        #else
        return Double(text.count) * size * 0.5
        #endif
    }

    /// Typographic bounds of one visible line.
    func line(_ text: String) -> (ascent: Double, descent: Double, width: Double) {
        #if canImport(AppKit)
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [.font: font]))
        var lineAscent: CGFloat = 0
        var lineDescent: CGFloat = 0
        var leading: CGFloat = 0
        let advance = CTLineGetTypographicBounds(line, &lineAscent, &lineDescent, &leading)
        return (max(Double(lineAscent), ascent), max(Double(lineDescent), descent), advance)
        #else
        return (ascent, descent, width(text))
        #endif
    }

    /// Returns a function suggesting the UTF-16 length of the line starting at an offset.
    func lineBreaker(for source: NSString) -> (_ offset: Int, _ width: Double) -> Int {
        #if canImport(AppKit)
        let typesetter = CTTypesetterCreateWithAttributedString(NSAttributedString(string: source as String, attributes: [.font: font]))
        return { offset, width in CTTypesetterSuggestLineBreak(typesetter, offset, width) }
        #elseif os(Windows)
        let units = Array((source as String).utf16)
        let handle = self.handle
        return { offset, width in handle.lineBreak(units, offset: offset, width: width) }
        #else
        return { offset, width in
            Self.approximateLineBreak(source, offset: offset, width: width, advance: size * 0.5)
        }
        #endif
    }

    /// Matches the fallback's uniform advances without discarding paragraph or grapheme boundaries.
    static func approximateLineBreak(_ source: NSString, offset: Int, width: Double, advance: Double) -> Int {
        var cursor = offset
        var usedWidth = 0.0
        var wordBoundary = offset
        while cursor < source.length {
            let range = source.rangeOfComposedCharacterSequence(at: cursor)
            let character = source.substring(with: range)
            if character == "\n" || character == "\r" || character == "\r\n" {
                if character == "\r", NSMaxRange(range) < source.length,
                   source.character(at: NSMaxRange(range)) == 0x0A {
                    return NSMaxRange(range) + 1 - offset
                }
                return NSMaxRange(range) - offset
            }
            if usedWidth + advance > max(0, width) {
                return (wordBoundary > offset ? wordBoundary : cursor) - offset
            }
            usedWidth += advance
            cursor = NSMaxRange(range)
            if character.trimmingCharacters(in: .whitespaces).isEmpty {
                wordBoundary = cursor
            }
        }
        return cursor - offset
    }
}

#if os(Windows)
/// A cached DirectWrite text format; formats are immutable and shared across renders.
final class FormDirectWriteFont: @unchecked Sendable {
    let pointer: OpaquePointer?
    let metrics: FDWFontMetrics

    private init(pointer: OpaquePointer?, size: Double) {
        self.pointer = pointer
        var metrics = FDWFontMetrics(ascent: size * 0.8, descent: size * 0.2, lineGap: 0, capHeight: size * 0.7, xHeight: size * 0.5)
        if let pointer { fdw_font_metrics(pointer, &metrics) }
        self.metrics = metrics
    }

    deinit { if let pointer { fdw_font_release(pointer) } }

    /// Lock-guarded font cache; a class keeps the declaration valid for Swift 5.9 parsers.
    private final class Cache: @unchecked Sendable {
        let lock = NSLock()
        var fonts: [String: FormDirectWriteFont] = [:]
    }
    private static let cache = Cache()

    static func cached(family: String?, primary: String, size: Double, bold: Bool, italic: Bool) -> FormDirectWriteFont {
        let key = "\(family ?? "")|\(primary)|\(size)|\(bold)|\(italic)"
        cache.lock.lock()
        defer { cache.lock.unlock() }
        if let font = cache.fonts[key] { return font }
        func create(_ name: String) -> OpaquePointer? {
            name.withCString(encodedAs: UTF16.self) { fdw_font_create($0, size, bold ? 1 : 0, italic ? 1 : 0) }
        }
        let pointer = family.flatMap(create) ?? create(primary) ?? create("Segoe UI") ?? create("Arial")
        let font = FormDirectWriteFont(pointer: pointer, size: size)
        if cache.fonts.count > 512 { cache.fonts.removeAll() }
        cache.fonts[key] = font
        return font
    }

    func width(_ text: String) -> Double {
        guard let pointer else { return Double(text.utf16.count) * metrics.ascent * 0.6 }
        let units = Array(text.utf16)
        return units.withUnsafeBufferPointer { fdw_text_width(pointer, $0.baseAddress, UInt32($0.count)) }
    }

    func lineBreak(_ units: [UInt16], offset: Int, width: Double) -> Int {
        guard let pointer, offset < units.count else { return max(0, units.count - offset) }
        return units.withUnsafeBufferPointer {
            Int(fdw_suggest_line_break(pointer, $0.baseAddress! + offset, UInt32($0.count - offset), max(0, width)))
        }
    }
}
#endif
