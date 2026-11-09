import Foundation
import FourDFileKit

public struct SetPresenter: ReportPresenter {
    public init() {}
    public var kinds: [String] { ["4d.set"] }

    public func report(for model: AnalysisModel) -> Report? {
        guard let info = model as? SetFileInfo else { return nil }
        var report = Report(title: info.fileName, subtitle: "4D Saved Set")
        func count(_ value: Int) -> String { info.isComplete ? Fmt.n(value) : "At least \(Fmt.n(value))" }
        report.stats = [
            Stat("Records in set", count(info.selectedRecords)),
            Stat("Address span", Fmt.n(info.addressSpan)),
            Stat("Record ranges", count(info.rangeCount)),
        ]
        if !info.isComplete {
            report.badges = [Badge("Partial preview", .warning)]
            report.sections.append(Section("Analysis limit", [
                .note("Examined \(Fmt.n(info.scannedAddressSpan)) of \(Fmt.n(info.addressSpan)) record addresses before reaching the time budget. Counts are lower bounds, not estimates. Unexamined addresses have unknown membership, not zero membership.", .warning),
            ]))
        }
        if info.isComplete && info.selectedRecords == 0 {
            report.sections.append(Section("Membership", [.note("This set is empty.", .neutral)]))
        } else {
            var membership: [Block] = []
            let addressNote = "Record numbers are zero-based storage positions, not selection positions or field values. The address span is not the table's live record count."
            if info.scannedAddressSpan > 0 {
                membership.append(.meter(fraction: Double(info.selectedRecords) / Double(info.scannedAddressSpan),
                                         label: "\(Fmt.n(info.selectedRecords)) of \(Fmt.n(info.scannedAddressSpan)) \(info.isComplete ? "" : "examined ")record addresses",
                                         caption: addressNote))
            } else {
                membership.append(.note("No bitmap membership has been examined. " + addressNote, .neutral))
            }
            membership.append(.bars(rows: info.distribution.map { bin in
                let examined = max(0, min(bin.last + 1, info.scannedAddressSpan) - bin.first)
                return BarRow(label: "\(bin.first)-\(bin.last)", value: Double(bin.selected),
                              display: examined == 0 ? "Not examined" : Fmt.n(bin.selected),
                              extra: examined == 0 ? "Unknown"
                                : Fmt.percent(Double(bin.selected) / Double(examined))
                                    + (examined < bin.last - bin.first + 1 ? " of examined" : ""),
                              muted: examined == 0)
            }, valueHeader: info.isComplete ? "In set" : "Observed in set", extraHeader: "Coverage"))
            report.sections.append(Section("Membership", membership))
            let rows = info.ranges.map {
                [Fmt.n($0.first), Fmt.n($0.last) + ($0.isComplete ? "" : "+"),
                 ($0.isComplete ? "" : "At least ") + Fmt.n($0.last - $0.first + 1)]
            }
            var footer: [String] = []
            if info.rangeCount > rows.count {
                footer.append("Showing the first \(rows.count) of \(info.isComplete ? "" : "at least ")\(Fmt.n(info.rangeCount)) ranges.")
            }
            if !info.isComplete {
                footer.append("Only examined addresses are shown; '+' marks a range whose end is not yet known.")
            } else if !footer.isEmpty {
                footer.append("Counts and distribution include the entire set.")
            }
            report.sections.append(Section("Record numbers", [
                .table(Table(columns: [("First", .trailing), ("Last", .trailing), ("Records", .trailing)],
                             rows: rows,
                             more: footer.isEmpty ? nil : footer.joined(separator: " "))),
            ]))
        }
        report.sections.append(Section("", [
            .disclosure(summary: "Set details", detail: nil, blocks: [
                .keyValues([
                    KeyValue("File size", Fmt.bytes(Int64(info.fileSize))),
                    KeyValue("Payload byte order", info.byteOrder),
                    KeyValue("Saved current record", info.savedCurrentRecord.map { Fmt.n($0) } ?? "None"),
                    KeyValue("Empty pages", Fmt.n(info.emptyPages)),
                    KeyValue("Full pages", Fmt.n(info.fullPages)),
                    KeyValue("Bitmap pages", Fmt.n(info.bitmapPages)),
                    KeyValue("Bitmap pages examined", Fmt.n(info.scannedBitmapPages)),
                ]),
                .note("A saved set contains record membership, not record contents or a table name. Its addresses refer to the original data file and may be stale after records are deleted, reused or compacted.", .neutral),
            ]),
        ]))
        return report
    }
}
