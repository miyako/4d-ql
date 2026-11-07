import Foundation

/// Generic, format-independent description of a preview page.
///
/// Presenters turn an analyzer's typed model into a Report; renderers turn a
/// Report into output (HTML today). Improving the look means changing the
/// renderer; choosing what to show means changing a presenter. Neither
/// touches the parsers.
///
/// Every block has a bounded size, so a file with 500 tables previews in the
/// same space as one with 5: presenters fold the long tail into "Other".
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
    public enum Width { case full, half }
    public var title: String
    public var blocks: [Block]
    /// Consecutive half-width sections share a row.
    public var width: Width
    public init(_ title: String, _ blocks: [Block], width: Width = .full) {
        self.title = title
        self.blocks = blocks
        self.width = width
    }
}

public struct KeyValue {
    public var key: String
    public var value: String
    /// Monospaced value (identifiers, paths).
    public var mono: Bool
    public init(_ key: String, _ value: String, mono: Bool = false) {
        self.key = key
        self.value = value
        self.mono = mono
    }
}

/// One row of a bar list. The bar encodes `value`; `display` is its label.
public struct BarRow {
    public var label: String
    public var value: Double
    public var display: String
    /// Secondary column, e.g. the field count.
    public var extra: String
    /// Short marker after the label, e.g. a lock for encrypted tables.
    public var marker: String?
    /// Folded rows ("Other …") are drawn in neutral grey.
    public var muted: Bool
    public var tooltip: String?

    public init(label: String, value: Double, display: String, extra: String = "",
                marker: String? = nil, muted: Bool = false, tooltip: String? = nil) {
        self.label = label; self.value = value; self.display = display
        self.extra = extra; self.marker = marker; self.muted = muted; self.tooltip = tooltip
    }
}

/// One part of a whole. `slot` is a fixed categorical colour (1...8) so the
/// same category always gets the same colour; nil means "Other" (grey).
public struct Segment {
    public var label: String
    public var value: Double
    public var display: String
    public var slot: Int?
    public init(label: String, value: Double, display: String, slot: Int?) {
        self.label = label; self.value = value; self.display = display; self.slot = slot
    }
}

public indirect enum Block {
    case keyValues([KeyValue])
    /// A prominent identifier with an explanation, e.g. the database UUID.
    case identity(label: String, value: String, caption: String?)
    /// Part of a whole as a single bar, e.g. used vs allocated space.
    case meter(fraction: Double, label: String, caption: String?)
    case bars(rows: [BarRow], valueHeader: String, extraHeader: String)
    /// A 100% stacked bar with a legend that always names every segment.
    case composition([Segment])
    case table(Table)
    /// Collapsible group with a summary line.
    case disclosure(summary: String, detail: String?, blocks: [Block])
    case note(String, Badge.Tone)
    case text(String)
}

public struct Table {
    public enum Align { case leading, trailing }
    public var columns: [(String, Align)]
    public var rows: [[String]]
    /// Footer for rows that were left out ("and 12 more").
    public var more: String?
    public init(columns: [(String, Align)], rows: [[String]], more: String? = nil) {
        self.columns = columns
        self.rows = rows
        self.more = more
    }
}
