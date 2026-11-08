import Foundation

/// Generic, format-independent description of a preview page.
///
/// Presenters turn an analyzer's typed model into a Report; renderers turn a
/// Report into output (HTML today). Improving the look means changing the
/// renderer; choosing what to show means changing a presenter. Neither
/// touches the parsers.
///
/// Summary blocks have a bounded size, so a file with 500 tables previews in
/// the same space as one with 5: presenters fold the long tail into "Other".
/// Source text preserves the complete contents in a scrollable block.
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
    public var icons: [FieldTypeIcon]
    public init(label: String, value: Double, display: String, slot: Int?, icons: [FieldTypeIcon] = []) {
        self.label = label; self.value = value; self.display = display; self.slot = slot
        self.icons = icons
    }
}

public enum FieldTypeIcon: String, CaseIterable {
    case boolean, integer, real, text, date, time, picture, uuid, blob, object, unknown
}

public indirect enum Block {
    public enum CodeLanguage { case plain, xml, json }

    case keyValues([KeyValue])
    /// A prominent identifier with an explanation, e.g. the database UUID.
    case identity(label: String, value: String, caption: String?)
    /// Part of a whole as a single bar, e.g. used vs allocated space.
    case meter(fraction: Double, label: String, caption: String?)
    case bars(rows: [BarRow], valueHeader: String, extraHeader: String)
    /// A 100% stacked bar with a legend that always names every segment.
    case composition([Segment])
    case table(Table)
    case queryConditions([QueryCondition])
    case orderedCards([OrderedCard])
    /// A bounded, format-independent table/field relationship diagram.
    case structureDiagram(StructureDiagram)
    /// Collapsible group with a summary line.
    case disclosure(summary: String, detail: String?, blocks: [Block])
    case note(String, Badge.Tone)
    case text(String)
    /// Source text with its whitespace preserved.
    case sourceCode(String, language: CodeLanguage = .plain)
    case code([CodeSpan])
}

public struct OrderedCard {
    public enum Icon: String {
        case text = "Aa", integer = "123", real = "1.2", boolean = "✓"
        case date = "▦", time = "◷", picture = "▧", blob = "01"
        case object = "{}", collection = "[]"
    }
    public var title: String
    public var subtitle: String
    public var details: [KeyValue]
    public var icon: Icon?

    public init(title: String, subtitle: String, details: [KeyValue], icon: Icon? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.details = details
        self.icon = icon
    }
}

public struct QueryCondition {
    public var connector: String
    public var field: String
    public var operation: String
    public var code: String
    public var operands: [KeyValue]

    public init(connector: String, field: String, operation: String, code: String, operands: [KeyValue]) {
        self.connector = connector
        self.field = field
        self.operation = operation
        self.code = code
        self.operands = operands
    }
}

public struct CodeSpan {
    public enum Style: String {
        case plain, comment, processing, string, number, keyword
        case variable, command, constant, type, property, `operator`
    }
    public var text: String
    public var style: Style

    public init(_ text: String, style: Style = .plain) {
        self.text = text
        self.style = style
    }
}

public struct StructureDiagram {
    public var nodes: [DiagramNode]
    public var edges: [DiagramEdge]
    public var omittedTables: Int
    public var omittedRelations: Int

    public init(nodes: [DiagramNode], edges: [DiagramEdge],
                omittedTables: Int = 0, omittedRelations: Int = 0) {
        self.nodes = nodes
        self.edges = edges
        self.omittedTables = omittedTables
        self.omittedRelations = omittedRelations
    }
}

public struct DiagramNode {
    public var id: String
    public var title: String
    public var fields: [DiagramField]
    public var position: DiagramPosition?
    public var omittedFields: Int
    public var hidden: Bool

    public init(id: String, title: String, fields: [DiagramField],
                position: DiagramPosition? = nil, omittedFields: Int = 0, hidden: Bool = false) {
        self.id = id
        self.title = title
        self.fields = fields
        self.position = position
        self.omittedFields = omittedFields
        self.hidden = hidden
    }
}

public struct DiagramField {
    public var id: String
    public var name: String
    public var type: String
    public var primaryKey: Bool
    public var hidden: Bool
    public var indexed: Bool

    public init(id: String, name: String, type: String,
                primaryKey: Bool = false, hidden: Bool = false, indexed: Bool = false) {
        self.id = id
        self.name = name
        self.type = type
        self.primaryKey = primaryKey
        self.hidden = hidden
        self.indexed = indexed
    }
}

public struct DiagramEdge {
    public var sourceNode: String
    public var sourceField: String
    public var destinationNode: String
    public var destinationField: String
    public var label: String

    public init(sourceNode: String, sourceField: String, destinationNode: String,
                destinationField: String, label: String) {
        self.sourceNode = sourceNode
        self.sourceField = sourceField
        self.destinationNode = destinationNode
        self.destinationField = destinationField
        self.label = label
    }
}

/// Saved diagram coordinates; the renderer validates and normalizes these.
public struct DiagramPosition {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
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
