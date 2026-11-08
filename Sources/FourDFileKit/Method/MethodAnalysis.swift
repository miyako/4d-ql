import Foundation

public struct MethodToken: Codable {
    public enum Kind: String, Codable {
        case plain, comment, processing, string, number, keyword
        case variable, command, constant, type, property, `operator`
    }

    public var text: String
    public var kind: Kind
}

public struct MethodFileInfo: AnalysisModel {
    public var kind: String { "4dm.source" }
    public var fileName: String
    public var fileSize: Int64
    public var lineCount: Int
    public var truncated: Bool
    public var tokens: [MethodToken]
    public var source: String { tokens.map(\.text).joined() }

    private enum CodingKeys: String, CodingKey {
        case kind, fileName, fileSize, lineCount, truncated, source, tokens
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(fileName, forKey: .fileName)
        try container.encode(fileSize, forKey: .fileSize)
        try container.encode(lineCount, forKey: .lineCount)
        try container.encode(truncated, forKey: .truncated)
        try container.encode(source, forKey: .source)
        try container.encode(tokens, forKey: .tokens)
    }
}

public enum MethodAnalysisError: Error, CustomStringConvertible {
    case invalidText

    public var description: String {
        "The method file is not valid UTF-8 text."
    }
}

public struct MethodFileAnalyzer: FileAnalyzer {
    public let identifier = "4dm"
    public let contentTypes = ["com.4d.4d.method"]
    public let filenameExtensions = ["4dm"]

    public init() {}

    // Source previews stay bounded even for generated methods or a misnamed binary.
    static let maximumBytes = 256 * 1024
    static let maximumLines = 1_000

    public func analyze(_ source: ByteSource, options: AnalysisOptions) throws -> AnalysisModel {
        var data = try source.readAvailable(at: 0, length: Self.maximumBytes)
        var truncated = source.size > Int64(data.count)
        var text = String(data: data, encoding: .utf8)
        if text == nil && truncated {
            // The byte cap can split one UTF-8 scalar (at most four bytes).
            for _ in 0..<3 where text == nil && !data.isEmpty {
                data.removeLast()
                text = String(data: data, encoding: .utf8)
            }
        }
        guard var text, !text.contains("\0") else { throw MethodAnalysisError.invalidText }
        while text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        text = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines = text.components(separatedBy: "\n")
        if lines.last == "" { lines.removeLast() }
        if lines.count > Self.maximumLines {
            lines = Array(lines.prefix(Self.maximumLines))
            text = lines.joined(separator: "\n")
            truncated = true
        }
        return MethodFileInfo(fileName: source.url.lastPathComponent, fileSize: source.size,
                              lineCount: lines.count, truncated: truncated,
                              tokens: try MethodLexer.tokens(in: text))
    }
}

enum MethodLexer {
    // Categories follow language-4dm-zed / tree-sitter-fourd. This is lexical
    // highlighting, not semantic command resolution or a syntax validator.
    private static let name = #"[\p{L}\p{N}_]+"#
    private static let protectedRules: [(MethodToken.Kind, String)] = [
        (.processing, #"(?m:^//[ \t]*%attributes[^\r\n]*)"#),
        (.comment, #"//(?:[^\r\n]*\\[ \t]*(?:\r\n|\r|\n))*[^\r\n]*|(?s:/\*.*?(?:\*/|\z))"#),
        (.string, #""(?:[^"\\\r\n]|\\[^\r\n])*(?:"|(?=[\r\n]|\z))"#),
        (.number, #"\?[0-9]{1,3}:[0-9]{1,2}:[0-9]{1,2}\?|![0-9]{1,4}(?<dateSep>[-/.])[0-9]{1,4}\k<dateSep>[0-9]{1,4}!"#),
        (.number, #"(?<![\p{L}\p{N}_])(?:0[xX][0-9a-fA-F]+|[0-9]+(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?)(?![\p{L}\p{N}_])"#),
        (.variable, #"\$\{|\$"# + name + #"|<>"# + name),
        (.property, #"\[[\p{L}\p{N}_ ]+(?::[0-9]+)?\][\p{L}\p{N}_]+(?:[ \t]+[\p{L}\p{N}_]+)*(?::[0-9]+)?"#),
        (.type, #"\[[\p{L}\p{N}_ ]+(?::[0-9]+)?\]"#),
    ]

    private static let wordRules: [(MethodToken.Kind, String)] = [
        (.keyword, #"(?i:(?<![\p{L}\p{N}_.$])(?:#DECLARE|Class[ \t]+(?:extends|constructor)|End[ \t]+(?:if|case|while|for|try|use|sql)|Case[ \t]+of|For[ \t]+each|Begin[ \t]+SQL|If|Else|While|Repeat|Until|For|Try|Catch|Use|var|property|Function|return|break|continue|throw|defer|shared|session|singleton|exposed|local|server|onHTTPGet)\b)"#),
        (.type, #"(?<![\p{L}\p{N}_.$])(?:Text|Integer|Real|Boolean|Date|Time|Picture|Blob|Object|Collection|Variant|Pointer|4D|cs)(?![\p{L}\p{N}_])"#),
        (.constant, #"(?<![\p{L}\p{N}_.$])(?:True|False|Null|OK|Error|Document)(?![\p{L}\p{N}_])"#),
        (.command, #"(?<![\p{L}\p{N}_.$])[A-Z][A-Z0-9_]*(?:[ \t]+[A-Z][A-Z0-9_]*|[ \t]+[0-9]+[A-Z][A-Z0-9_]*)+(?![\p{L}\p{N}_])"#),
        (.command, name + #"(?=[ \t]*\()"#),
        (.operator, #":=|\+=|-=|\*=|/=|<=|>=|&&|\|\||\^\||<<|>>|\?\?|\?\+|\?-|->|\.\.\.|[=<>#+*/%\\^&|?-]"#),
        // Consume unknown identifiers whole, rather than highlighting substrings.
        (.plain, name),
    ]

    // Consume each word run once, with an optional token suffix. Requiring a
    // suffix would retry every remaining word at each position (quadratic on
    // long untokenized lines). Unsuffixed runs use the ordinary lexical rules.
    private static let rules = protectedRules + [
        (MethodToken.Kind.plain, name + #"(?:[ \t]+"# + name +
         #")*(?:(?<commandSuffix>:C[0-9]+\b)|(?<constantSuffix>:K[0-9]+:[0-9]+\b))?"#),
    ] + wordRules

    private static func expression(for rules: [(MethodToken.Kind, String)]) throws -> NSRegularExpression {
        try NSRegularExpression(pattern: rules.enumerated().map {
            "(?<t\($0.offset)>\($0.element.1))"
        }.joined(separator: "|"))
    }

    private static let mainExpression = Result { try expression(for: rules) }
    private static let wordExpression = Result { try expression(for: wordRules) }

    static func tokens(in text: String) throws -> [MethodToken] {
        let words = try wordExpression.get()
        return tokenize(text, regex: try mainExpression.get(), rules: rules, words: words)
    }

    private static func tokenize(_ text: String, regex: NSRegularExpression,
                                 rules: [(MethodToken.Kind, String)],
                                 words: NSRegularExpression? = nil,
                                 range: NSRange? = nil) -> [MethodToken] {
        let source = text as NSString
        let range = range ?? NSRange(location: 0, length: source.length)
        var tokens: [MethodToken] = []
        var end = range.location
        regex.enumerateMatches(in: text, options: .withTransparentBounds, range: range) { match, _, _ in
            guard let match else { return }
            if match.range.location > end {
                tokens.append(MethodToken(text: source.substring(with: NSRange(location: end, length: match.range.location - end)),
                                          kind: .plain))
            }
            for (index, rule) in rules.enumerated() where match.range(withName: "t\(index)").location != NSNotFound {
                let tokenText = source.substring(with: match.range)
                if let words, index == protectedRules.count {
                    if match.range(withName: "commandSuffix").location != NSNotFound {
                        tokens.append(MethodToken(text: tokenText, kind: .command))
                    } else if match.range(withName: "constantSuffix").location != NSNotFound {
                        tokens.append(MethodToken(text: tokenText, kind: .constant))
                    } else {
                        tokens += tokenize(text, regex: words, rules: wordRules, range: match.range)
                    }
                } else {
                    tokens.append(MethodToken(text: tokenText, kind: rule.0))
                }
                break
            }
            end = NSMaxRange(match.range)
        }
        if end < NSMaxRange(range) {
            tokens.append(MethodToken(text: source.substring(with: NSRange(location: end, length: NSMaxRange(range) - end)),
                                      kind: .plain))
        }
        return tokens
    }
}
