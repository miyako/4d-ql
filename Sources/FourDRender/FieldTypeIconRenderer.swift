import Foundation

enum FieldTypeIconRenderer {
    static func render(_ icon: FieldTypeIcon) -> String {
        let glyph: String
        switch icon {
        case .boolean:
            glyph = "<rect x=\"2\" y=\"2\" width=\"10\" height=\"10\" rx=\"2\"/><path d=\"m4 7 2 2 4-4\"/>"
        case .integer:
            glyph = "<path d=\"M5 2 3 12 M10 2 8 12 M2 5h10 M1 9h10\"/>"
        case .real:
            glyph = "<text x=\"7\" y=\"10\" text-anchor=\"middle\">1.2</text>"
        case .text:
            glyph = "<text x=\"7\" y=\"10\" text-anchor=\"middle\">Aa</text>"
        case .date:
            glyph = "<rect x=\"1.5\" y=\"3\" width=\"11\" height=\"9.5\" rx=\"1.5\"/><path d=\"M1.5 6h11 M4 1.5v3 M10 1.5v3 M4 9h2 M8 9h2\"/>"
        case .time:
            glyph = "<circle cx=\"7\" cy=\"7\" r=\"5.5\"/><path d=\"M7 3.5V7l3 1.5\"/>"
        case .picture:
            glyph = "<rect x=\"1\" y=\"2\" width=\"12\" height=\"10\" rx=\"1\"/><circle cx=\"4\" cy=\"5\" r=\"1\"/><path d=\"m2 11 4-4 2 2 2-3 2 5\"/>"
        case .uuid:
            glyph = "<circle cx=\"4\" cy=\"5\" r=\"2.5\"/><path d=\"m6 7 5 5 M8 9l2-2 M10 11l2-2\"/>"
        case .blob:
            glyph = "<ellipse cx=\"7\" cy=\"3\" rx=\"5\" ry=\"2\"/><path d=\"M2 3v8c0 2.5 10 2.5 10 0V3 M2 7c0 2.5 10 2.5 10 0\"/>"
        case .object:
            glyph = "<path d=\"M5 1H4c-1 0-1 1-1 2v2c0 1-1 2-2 2 1 0 2 1 2 2v2c0 1 0 2 1 2h1 M9 1h1c1 0 1 1 1 2v2c0 1 1 2 2 2-1 0-2 1-2 2v2c0 1 0 2-1 2H9\"/>"
        case .unknown:
            glyph = "<text x=\"7\" y=\"10\" text-anchor=\"middle\">?</text>"
        }
        return "<svg xmlns=\"http://www.w3.org/2000/svg\" class=\"type-icon type-icon-\(icon.rawValue)\" width=\"14\" height=\"14\" viewBox=\"0 0 14 14\" aria-hidden=\"true\" focusable=\"false\">\(glyph)</svg>"
    }

    static let css = """
    .type-icon{display:block;flex:none;fill:none;stroke:currentColor;stroke-width:1.2;stroke-linecap:round;stroke-linejoin:round}
    .type-icon text{fill:currentColor;stroke:none;font:700 9px -apple-system,BlinkMacSystemFont,"Helvetica Neue",sans-serif}
    .type-icon-text,.type-icon-uuid{color:var(--s1)}
    .type-icon-integer{color:var(--s2)}.type-icon-real{color:var(--s3)}
    .type-icon-date,.type-icon-time{color:var(--s4)}.type-icon-boolean{color:var(--s5)}
    .type-icon-picture{color:var(--s6)}.type-icon-blob{color:var(--s7)}
    .type-icon-object{color:var(--s8)}.type-icon-unknown{color:var(--muted)}
    """
}
