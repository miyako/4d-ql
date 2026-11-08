import Foundation

public enum FormTheme: String, CaseIterable, Encodable {
    case classicLight, classicDark, glassLight, glassDark
    public var dark: Bool { self == .classicDark || self == .glassDark }
    public var glass: Bool { self == .glassLight || self == .glassDark }
    public var label: String {
        "\(glass ? "Liquid Glass" : "Classic") \(dark ? "dark" : "light")"
    }
}

struct FormStyleRule {
    var selectors: [String]
    var media: [String]
    var declarations: [(name: String, value: FormValue, important: Bool)]
}

struct FormStylesheet {
    var rules: [FormStyleRule] = []
    private let dependencies: FormDependencies

    init(dependencies: FormDependencies) { self.dependencies = dependencies }

    mutating func append(_ text: String, document: URL? = nil) throws {
        var parser = CSSBlocks(text, dependencies: dependencies)
        var added = try parser.parse()
        if let document {
            for index in added.indices {
                for declaration in added[index].declarations.indices {
                    let item = added[index].declarations[declaration]
                    if ["picture", "icon", "customBackgroundPicture"].contains(item.name), let path = item.value.string {
                        do { added[index].declarations[declaration].value = .string(try dependencies.rebase(path, from: document)) }
                        catch { dependencies.warn("Cannot rebase CSS picture \(path): \(error)") }
                    }
                }
            }
        }
        try appendRules(added)
    }

    mutating func append(contentsOf stylesheet: FormStylesheet) throws {
        try appendRules(stylesheet.rules)
    }

    private mutating func appendRules(_ added: [FormStyleRule]) throws {
        guard rules.count + added.count <= 5_000 else { throw FormError.limit("5,000 CSS rules exceeded.") }
        rules += added
    }

    func apply(_ object: FormValue, name: String, type: String, theme: FormTheme) -> FormValue {
        var result = object
        var winners: [String: (Bool, Int, Int, FormValue)] = [:]
        for (order, rule) in rules.enumerated() where rule.media.allSatisfy({ matchesMedia($0, theme: theme) }) {
            let specificity = rule.selectors.compactMap { selectorSpecificity($0, object: object, name: name, type: type) }.max()
            guard let specificity else { continue }
            for declaration in rule.declarations {
                let candidate = (declaration.important, specificity, order, declaration.value)
                if let previous = winners[declaration.name] {
                    if previous.0 && !candidate.0 { continue }
                    if previous.0 == candidate.0 && (previous.1 > candidate.1 || (previous.1 == candidate.1 && previous.2 > candidate.2)) { continue }
                }
                winners[declaration.name] = candidate
            }
        }
        for (property, winner) in winners where winner.0 || object[property] == nil {
            if !winner.0 && property == "height" && object["bottom"] != nil { continue }
            if !winner.0 && property == "width" && object["right"] != nil { continue }
            result[property] = winner.3
        }
        return result
    }

    private func matchesMedia(_ query: String, theme: FormTheme) -> Bool {
        let conditions = query.components(separatedBy: ",")
        return conditions.contains { alternative in
            guard let regex = Self.mediaRegex else { return false }
            let ns = alternative as NSString
            let matches = regex.matches(in: alternative, range: NSRange(location: 0, length: ns.length))
            guard !matches.isEmpty else {
                dependencies.warn("Unsupported CSS media query: \(query)")
                return false
            }
            var remainder = alternative
            for match in matches.reversed() {
                remainder = (remainder as NSString).replacingCharacters(in: match.range, with: "")
            }
            let words = remainder.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            guard words.allSatisfy({ $0 == "and" || $0 == "all" || $0 == "screen" }) else {
                dependencies.warn("Unsupported CSS media query: \(query)")
                return false
            }
            return matches.allSatisfy { match in
                let feature = ns.substring(with: match.range(at: 1))
                let value = ns.substring(with: match.range(at: 2))
                return feature == "prefers-color-scheme" ? value == (theme.dark ? "dark" : "light")
                    : value == (theme.glass ? "liquid-glass" : "mac-classic")
            }
        }
    }

    private func selectorSpecificity(_ selector: String, object: FormValue, name: String, type: String) -> Int? {
        guard let regex = Self.selectorRegex,
              let match = regex.firstMatch(in: selector, range: NSRange(selector.startIndex..., in: selector)) else {
            dependencies.warn("Unsupported CSS selector: \(selector)")
            return nil
        }
        let ns = selector as NSString
        let element = match.range(at: 1).location == NSNotFound ? "" : ns.substring(with: match.range(at: 1))
        guard element.isEmpty || element == "*" || element == type else { return nil }
        var score = element.isEmpty || element == "*" ? 0 : 1
        let tokens = ns.substring(with: match.range(at: 2))
        guard let parts = Self.selectorParts else { return nil }
        for token in parts.matches(in: tokens, range: NSRange(tokens.startIndex..., in: tokens)) {
            let item = (tokens as NSString).substring(with: token.range)
            if item.hasPrefix("#") {
                guard String(item.dropFirst()) == name else { return nil }
                score += 10_000
            } else if item.hasPrefix(".") {
                guard (object["class"]?.string ?? "").split(whereSeparator: \.isWhitespace).contains(Substring(item.dropFirst())) else { return nil }
                score += 100
            } else {
                guard let attr = Self.attributeRegex,
                      let m = attr.firstMatch(in: item, range: NSRange(item.startIndex..., in: item)) else { return nil }
                let a = item as NSString
                guard let value = object[a.substring(with: m.range(at: 1))] else { return nil }
                if m.range(at: 2).location != NSNotFound {
                    let operation = a.substring(with: m.range(at: 2))
                    let expected = CSSBlocks.unquote(a.substring(with: m.range(at: 3)).trimmingCharacters(in: .whitespaces))
                    let actual = value.string ?? value.double.map { String(format: "%g", $0) } ?? value.bool.map { $0 ? "true" : "false" } ?? ""
                    switch operation {
                    case "=": guard actual == expected else { return nil }
                    case "~=": guard actual.split(whereSeparator: \.isWhitespace).contains(Substring(expected)) else { return nil }
                    case "|=": guard actual.hasPrefix(expected) else { return nil }
                    default: return nil
                    }
                }
                score += 100
            }
        }
        return score
    }

    private static let selectorRegex = try? NSRegularExpression(pattern: #"^(\*|[A-Za-z_][\w-]*)?((?:[.#][\w-]+|\[\s*[\w-]+(?:\s*(?:=|~=|\|=)\s*(?:"[^"]*"|'[^']*'|[^\]\s]+))?\s*\])*)$"#)
    private static let selectorParts = try? NSRegularExpression(pattern: #"[.#][\w-]+|\[[^\]]+\]"#)
    private static let attributeRegex = try? NSRegularExpression(pattern: #"^\[\s*([\w-]+)(?:\s*(=|~=|\|=)\s*(.*?))?\s*\]$"#)
    private static let mediaRegex = try? NSRegularExpression(pattern: #"\(\s*(prefers-color-scheme|form-theme)\s*:\s*([a-z-]+)\s*\)"#)
}

private struct CSSBlocks {
    private let characters: [Character]
    private var position = 0
    private let dependencies: FormDependencies
    private var ruleCount = 0
    private var declarationCount = 0

    init(_ text: String, dependencies: FormDependencies) {
        characters = Array(text)
        self.dependencies = dependencies
    }

    mutating func parse(media: [String] = [], depth: Int = 0) throws -> [FormStyleRule] {
        guard depth <= 16 else { throw FormError.limit("CSS media nesting exceeds 16.") }
        var rules: [FormStyleRule] = []
        while position < characters.count {
            skip()
            if position == characters.count { break }
            if characters[position] == "}" { position += 1; return rules }
            let (header, delimiter) = try scan(until: ["{", ";", "}"])
            guard delimiter == "{" else {
                dependencies.warn("Unsupported or malformed CSS statement: \(header)")
                continue
            }
            let trimmed = header.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.hasPrefix("@media") {
                rules += try parse(media: media + [String(trimmed.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)], depth: depth + 1)
            } else if trimmed.hasPrefix("@") {
                dependencies.warn("Unsupported CSS at-rule: \(trimmed)")
                _ = try parse(media: media + ["unsupported"], depth: depth + 1)
            } else {
                ruleCount += 1
                guard ruleCount <= 5_000 else { throw FormError.limit("5,000 CSS rules exceeded.") }
                var declarations: [(String, FormValue, Bool)] = []
                var closed = false
                while position < characters.count {
                    skip()
                    if position < characters.count, characters[position] == "}" { position += 1; closed = true; break }
                    let (statement, end) = try scan(until: [";", "}"])
                    declarationCount += 1
                    guard declarationCount <= 20_000 else { throw FormError.limit("20,000 CSS declarations exceeded.") }
                    if let colon = statement.firstIndex(of: ":") {
                        let original = String(statement[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
                        let aliases = ["border-style": "borderStyle", "background-color": "fill", "color": "stroke",
                                       "font-family": "fontFamily", "font-size": "fontSize", "font-style": "fontStyle",
                                       "font-weight": "fontWeight", "text-align": "textAlign", "text-decoration": "textDecoration",
                                       "vertical-align": "verticalAlign", "padding-top": "paddingTop", "padding-bottom": "paddingBottom",
                                       "padding-left": "paddingLeft", "padding-right": "paddingRight"]
                        let name = aliases[original] ?? original
                        var raw = String(statement[statement.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
                        let importantRange = raw.range(of: #"!\s*important\s*$"#, options: [.regularExpression, .caseInsensitive])
                        let important = importantRange != nil
                        if let importantRange { raw.removeSubrange(importantRange); raw = raw.trimmingCharacters(in: .whitespacesAndNewlines) }
                        if !["type", "class", "method", "events", "event", "choiceList", "excludedList", "labels", "list", "requiredList", "colorScheme"].contains(name) {
                            declarations.append((name, Self.value(raw, name: name), important))
                        } else {
                            dependencies.warn("CSS cannot set \(name).")
                        }
                    } else if !statement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        dependencies.warn("Malformed CSS declaration: \(statement)")
                    }
                    if end == "}" { closed = true; break }
                }
                if !closed { dependencies.warn("Unclosed CSS declaration block.") }
                rules.append(FormStyleRule(selectors: Self.selectorList(trimmed).map {
                    $0.trimmingCharacters(in: .whitespacesAndNewlines)
                }, media: media, declarations: declarations))
            }
        }
        if depth > 0 { dependencies.warn("Unclosed CSS media block.") }
        return rules
    }

    private mutating func skip() {
        while position < characters.count {
            if characters[position].isWhitespace { position += 1 }
            else if position + 1 < characters.count, characters[position] == "/", characters[position + 1] == "*" {
                position += 2
                while position + 1 < characters.count, !(characters[position] == "*" && characters[position + 1] == "/") { position += 1 }
                position = min(characters.count, position + 2)
            } else { break }
        }
    }

    private mutating func scan(until delimiters: Set<Character>) throws -> (String, Character?) {
        var text = ""
        var quote: Character?
        var escaped = false
        var parentheses = 0
        var brackets = 0
        while position < characters.count {
            let c = characters[position]
            if quote == nil, c == "/", position + 1 < characters.count, characters[position + 1] == "*" {
                skip()
                text += " "
                continue
            }
            position += 1
            if escaped { escaped = false; text.append(c); continue }
            if c == "\\", quote != nil { escaped = true; text.append(c); continue }
            if let active = quote {
                if c == active { quote = nil }
            } else if c == "\"" || c == "'" { quote = c }
            else if c == "(" { parentheses += 1 }
            else if c == ")" { parentheses -= 1 }
            else if c == "[" { brackets += 1 }
            else if c == "]" { brackets -= 1 }
            else if parentheses == 0, brackets == 0, delimiters.contains(c) { return (text, c) }
            text.append(c)
        }
        if quote != nil || parentheses != 0 || brackets != 0 { dependencies.warn("Unterminated CSS value.") }
        return (text, nil)
    }

    static func unquote(_ text: String) -> String {
        if text.count >= 2, (text.first == "\"" && text.last == "\"" || text.first == "'" && text.last == "'") {
            return String(text.dropFirst().dropLast()).replacingOccurrences(of: #"\""#, with: "\"").replacingOccurrences(of: #"\'"#, with: "'")
        }
        return text
    }

    private static func selectorList(_ text: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var quote: Character?
        var escaped = false
        var brackets = 0
        for character in text {
            if escaped { current.append(character); escaped = false; continue }
            if character == "\\" { current.append(character); escaped = true; continue }
            if let active = quote {
                if character == active { quote = nil }
            } else if character == "\"" || character == "'" { quote = character }
            else if character == "[" { brackets += 1 }
            else if character == "]" { brackets -= 1 }
            else if character == ",", brackets == 0 { parts.append(current); current = ""; continue }
            current.append(character)
        }
        parts.append(current)
        return parts
    }

    private static func value(_ text: String, name: String) -> FormValue {
        if text.hasPrefix("url("), text.hasSuffix(")") {
            return .string(unquote(String(text.dropFirst(4).dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        if text == "true" { return .bool(true) }
        if text == "false" { return .bool(false) }
        if let integer = Int64(text) { return .integer(integer) }
        if let number = Double(text), number.isFinite { return .number(number) }
        if text.hasSuffix("px"), let number = Double(text.dropLast(2)), number.isFinite,
           ["left", "top", "width", "height", "right", "bottom", "fontSize"].contains(name) { return .number(number) }
        return .string(unquote(text))
    }
}
