import Foundation

/// Generic, format-independent description of a preview page.
///
/// Presenters turn an analyzer's typed model into a Report; renderers turn a
/// Report into output (HTML today). Improving the look means changing the
/// renderer; showing more information means changing a presenter. Neither
/// touches the parsers.
public struct Report {
    public var title: String
    public var subtitle: String?
    public var badges: [Badge] = []
    public var stats: [Stat] = []
    public var sections: [Section] = []

    public init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }
}

public struct Badge {
    public enum Tone { case neutral, good, warning, danger }
    public var text: String
    public var tone: Tone
    public init(_ text: String, _ tone: Tone = .neutral) { self.text = text; self.tone = tone }
}

/// A headline number ("12 tables").
public struct Stat {
    public var label: String
    public var value: String
    public init(_ label: String, _ value: String) { self.label = label; self.value = value }
}

public struct Section {
    public var title: String
    public var blocks: [Block]
    public init(_ title: String, _ blocks: [Block]) { self.title = title; self.blocks = blocks }
}

public indirect enum Block {
    case keyValues([(String, String)])
    case table(Table)
    /// Horizontal bars, values relative to the largest.
    case bars([(label: String, value: Double, display: String)])
    /// Collapsible group with a summary line.
    case disclosure(summary: String, detail: String?, blocks: [Block])
    case note(String, Badge.Tone)
    case text(String)
}

public struct Table {
    public enum Align { case leading, trailing }
    public var columns: [(String, Align)]
    public var rows: [[String]]
    public init(columns: [(String, Align)], rows: [[String]]) { self.columns = columns; self.rows = rows }
}
