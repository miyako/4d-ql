import Foundation

/// A deliberately small, static subset of Excel/SpreadJS number formats.
enum SpreadsheetNumberFormat {
    static func text(_ number: Double, format: String?, oaDate: Bool = false) -> String? {
        guard number.isFinite else { return nil }
        let format = oaDate && (format == nil || format?.lowercased() == "general") ? "yyyy-mm-dd hh:mm:ss" : format
        guard let format, !format.isEmpty, format.lowercased() != "general" else {
            return String(format: "%.15g", locale: Locale(identifier: "en_US_POSIX"), number)
        }
        let sections = split(format, separator: ";")
        let section = sections[min(number < 0 && sections.count > 1 ? 1 : number == 0 && sections.count > 2 ? 2 : 0, sections.count - 1)]
        let unquoted = section.replacingOccurrences(of: #""[^"]*""#, with: "", options: .regularExpression).lowercased()
        if unquoted.contains("y") || unquoted.contains("d") || unquoted.contains("h") || unquoted.contains("s") {
            return date(number, format: section, oaDate: oaDate)
        }
        guard !section.contains("["), !section.contains("*"), !section.contains("_"),
              !section.contains("?"), !section.contains("/"), !section.lowercased().contains("e+") else {
            return nil
        }
        guard let first = section.firstIndex(where: { $0 == "0" || $0 == "#" }),
              let last = section.lastIndex(where: { $0 == "0" || $0 == "#" }) else { return nil }
        let pattern = String(section[first...last])
        guard pattern.allSatisfy({ "0#.,".contains($0) }) else { return nil }
        let fractional = pattern.split(separator: ".", omittingEmptySubsequences: false)
        guard fractional.count <= 2 else { return nil }
        let decimals = fractional.count == 2 ? String(fractional[1]) : ""
        guard decimals.count <= 15 else { return nil }
        let percent = section.contains("%")
        guard section.filter({ $0 == "%" }).count <= 1,
              !section[section.index(after: last)...].contains(",") else { return nil }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = pattern.contains(",")
        formatter.minimumFractionDigits = decimals.filter { $0 == "0" }.count
        formatter.maximumFractionDigits = decimals.count
        formatter.minimumIntegerDigits = min(15, fractional[0].filter { $0 == "0" }.count)
        let magnitude = sections.count > 1 && number < 0 ? abs(number) : number
        guard let value = formatter.string(from: NSNumber(value: magnitude * (percent ? 100 : 1))) else { return nil }
        func literal(_ text: Substring) -> String? {
            let result = String(text).replacingOccurrences(of: "\"", with: "").replacingOccurrences(of: "\\", with: "")
            guard !result.contains("@"), !result.contains("#"), !result.contains("0") else { return nil }
            return result
        }
        guard let prefix = literal(section[..<first]), let suffix = literal(section[section.index(after: last)...]) else { return nil }
        return prefix + value + suffix
    }

    private static func date(_ serial: Double, format: String, oaDate: Bool) -> String? {
        guard serial >= 0, serial < 2_958_466, !format.contains("[") else { return nil }
        let lower = format.lowercased()
        let allowed = CharacterSet(charactersIn: "ymdhsatp/:.- ,\"\\0123456789")
        guard lower.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        let hasAMPM = lower.contains("am/pm")
        var result = ""
        var index = lower.startIndex
        var quoted = false
        while index < lower.endIndex {
            let c = lower[index]
            if c == "\"" { quoted.toggle(); result += "'"; index = lower.index(after: index); continue }
            if quoted { result.append(c); index = lower.index(after: index); continue }
            if lower[index...].hasPrefix("am/pm") {
                result += "a"; index = lower.index(index, offsetBy: 5); continue
            }
            if c == "\\" {
                index = lower.index(after: index)
                guard index < lower.endIndex else { return nil }
                result += "'\(lower[index])'"
                index = lower.index(after: index)
                continue
            }
            if "ymdhs".contains(c) {
                var end = lower.index(after: index)
                while end < lower.endIndex, lower[end] == c { end = lower.index(after: end) }
                let count = lower.distance(from: index, to: end)
                let prefix = lower[..<index]
                let minute = c == "m" && (prefix.contains("h") || lower[end...].hasPrefix(":s"))
                let symbol: Character = c == "m" ? (minute ? "m" : "M") : c == "h" && !hasAMPM ? "H" : c
                if c == "d", count >= 3 { result += count == 3 ? "EEE" : "EEEE" }
                else { result += String(repeating: String(symbol), count: min(count, 5)) }
                index = end
            } else {
                result.append(c)
                index = lower.index(after: index)
            }
        }
        guard !quoted else { return nil }
        // Excel deliberately retains the nonexistent 1900-02-29 at serial 60.
        if !oaDate, Int(serial) == 60, lower.contains("y") || lower.contains("d") { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = result
        let epoch = -2_209_075_200.0 // 1899-12-31 UTC.
        return formatter.string(from: Date(timeIntervalSince1970: epoch + (serial - (oaDate || serial >= 60 ? 1 : 0)) * 86_400))
    }

    private static func split(_ text: String, separator: Character) -> [String] {
        var result = [""]
        var quoted = false
        var escaped = false
        for character in text {
            if character == separator && !quoted && !escaped { result.append("") }
            else { result[result.count - 1].append(character) }
            if character == "\"" && !escaped { quoted.toggle() }
            if character == "\\" && !escaped { escaped = true } else { escaped = false }
        }
        return result
    }
}
