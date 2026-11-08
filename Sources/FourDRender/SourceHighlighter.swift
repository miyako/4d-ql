import Foundation

/// Lexical coloring only: incomplete or invalid documents still show their source.
enum SourceHighlighter {
    static func html(_ text: String, language: Block.CodeLanguage, escape: (String) -> String) -> String {
        if language == .plain { return escape(text) }
        let chars = Array(text.unicodeScalars)
        var cursor = 0
        var output = ""
        var inTag = false
        var expectingTagName = false

        func emit(to end: Int, kind: String? = nil) {
            let value = escape(String(String.UnicodeScalarView(chars[cursor..<end])))
            output += kind.map { "<span class=\"syntax-\($0)\">\(value)</span>" } ?? value
            cursor = end
        }

        func starts(_ prefix: String, at index: Int) -> Bool {
            let scalars = Array(prefix.unicodeScalars)
            return index + scalars.count <= chars.count && chars[index..<index + scalars.count].elementsEqual(scalars)
        }

        func through(_ delimiter: String, from index: Int) -> Int {
            var end = index
            while end < chars.count {
                if starts(delimiter, at: end) { return end + delimiter.unicodeScalars.count }
                end += 1
            }
            return chars.count
        }

        func quotedEnd(backslashEscapes: Bool) -> Int {
            let quote = chars[cursor]
            var end = cursor + 1
            while end < chars.count {
                if backslashEscapes && chars[end] == "\\" {
                    end = min(end + 2, chars.count)
                } else if chars[end] == quote {
                    return end + 1
                } else {
                    end += 1
                }
            }
            return end
        }

        func isName(_ char: Unicode.Scalar) -> Bool {
            CharacterSet.alphanumerics.contains(char) || char == "_" || char == ":" || char == "-" || char == "."
        }

        while cursor < chars.count {
            let char = chars[cursor]
            switch language {
            case .plain:
                emit(to: chars.count)
            case .json:
                if char == "\"" {
                    let end = quotedEnd(backslashEscapes: true)
                    var next = end
                    while next < chars.count && CharacterSet.whitespacesAndNewlines.contains(chars[next]) { next += 1 }
                    emit(to: end, kind: next < chars.count && chars[next] == ":" ? "key" : "string")
                } else if char == "-" || ("0"..."9").contains(char) {
                    var end = cursor + 1
                    while end < chars.count && ("0123456789.eE+-".unicodeScalars.contains(chars[end])) { end += 1 }
                    emit(to: end, kind: "number")
                } else if CharacterSet.letters.contains(char) {
                    var end = cursor + 1
                    while end < chars.count && CharacterSet.alphanumerics.contains(chars[end]) { end += 1 }
                    let word = String(String.UnicodeScalarView(chars[cursor..<end]))
                    emit(to: end, kind: ["true", "false", "null"].contains(word) ? "literal" : nil)
                } else {
                    emit(to: cursor + 1)
                }
            case .xml:
                if inTag && (char == "\"" || char == "'") {
                    emit(to: quotedEnd(backslashEscapes: false), kind: "string")
                } else if starts("<!--", at: cursor) {
                    emit(to: through("-->", from: cursor + 4), kind: "comment")
                } else if starts("<![CDATA[", at: cursor) {
                    emit(to: through("]]>", from: cursor + 9), kind: "string")
                } else if starts("<!", at: cursor) {
                    emit(to: through(">", from: cursor + 2), kind: "literal")
                } else if char == "<" {
                    let length = starts("</", at: cursor) || starts("<?", at: cursor) ? 2 : 1
                    emit(to: cursor + length, kind: "tag")
                    inTag = true
                    expectingTagName = true
                } else if inTag && (char == ">" || starts("/>", at: cursor) || starts("?>", at: cursor)) {
                    emit(to: cursor + (char == ">" ? 1 : 2), kind: "tag")
                    inTag = false
                    expectingTagName = false
                } else if inTag && isName(char) {
                    var end = cursor + 1
                    while end < chars.count && isName(chars[end]) { end += 1 }
                    emit(to: end, kind: expectingTagName ? "tag" : "attribute")
                    expectingTagName = false
                } else if char == "&" {
                    var end = cursor + 1
                    while end < chars.count && (isName(chars[end]) || chars[end] == "#") { end += 1 }
                    let terminated = end < chars.count && chars[end] == ";"
                    emit(to: terminated ? end + 1 : end, kind: terminated ? "entity" : nil)
                } else {
                    emit(to: cursor + 1)
                }
            }
        }
        return output
    }
}
