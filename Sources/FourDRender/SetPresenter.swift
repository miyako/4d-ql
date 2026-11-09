import Foundation
import FourDFileKit

public struct SetPresenter: ReportPresenter {
    public init() {}
    public var kinds: [String] { ["4d.set"] }

    public func report(for model: AnalysisModel) -> Report? {
        guard let info = model as? SetFileInfo else { return nil }
        var report = Report(title: info.fileName, subtitle: "4D Saved Set")
        report.stats = [
            Stat("Records in set", Fmt.n(info.selectedRecords)),
            Stat("Address span", Fmt.n(info.addressSpan)),
            Stat("Record ranges", Fmt.n(info.rangeCount)),
        ]
        if info.selectedRecords == 0 {
            report.sections.append(Section("Membership", [.note("This set is empty.", .neutral)]))
        } else {
            report.sections.append(Section("Membership", [
                .meter(fraction: Double(info.selectedRecords) / Double(info.addressSpan),
                       label: "\(Fmt.n(info.selectedRecords)) of \(Fmt.n(info.addressSpan)) record addresses",
                       caption: "Record numbers are zero-based storage positions, not selection positions or field values. The address span is not the table's live record count."),
                .bars(rows: info.distribution.map {
                    BarRow(label: "\($0.first)-\($0.last)", value: Double($0.selected),
                           display: Fmt.n($0.selected),
                           extra: Fmt.percent(Double($0.selected) / Double($0.last - $0.first + 1)))
                }, valueHeader: "In set", extraHeader: "Coverage"),
            ]))
            let rows = info.ranges.map { [Fmt.n($0.first), Fmt.n($0.last), Fmt.n($0.last - $0.first + 1)] }
            report.sections.append(Section("Record numbers", [
                .table(Table(columns: [("First", .trailing), ("Last", .trailing), ("Records", .trailing)],
                             rows: rows,
                             more: info.rangeCount > rows.count
                                ? "Showing the first \(rows.count) of \(Fmt.n(info.rangeCount)) ranges. Counts and distribution include the entire set."
                                : nil)),
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
                ]),
                .note("A saved set contains record membership, not record contents or a table name. Its addresses refer to the original data file and may be stale after records are deleted, reused or compacted.", .neutral),
            ]),
        ]))
        return report
    }
}
