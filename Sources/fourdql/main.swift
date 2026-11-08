import Foundation
import FourDFileKit
import FourDRender

// fourdql — inspect 4D files with the same code the Quick Look extension uses.
//
//   fourdql [--json | --html] [--thorough] <file>...
//
//   (default)   short text summary
//   --json      the analyzer's typed model (useful when working on parsers)
//   --html      the exact page Quick Look shows (useful when working on presentation)
//   --thorough  no record/time limits

var mode = "text"
var options = AnalysisOptions.preview
var paths: [String] = []
for arg in CommandLine.arguments.dropFirst() {
    switch arg {
    case "--json": mode = "json"
    case "--html": mode = "html"
    case "--thorough": options = .thorough
    case "--content-types":
        // Used by scripts/build.sh to fill QLSupportedContentTypes.
        AnalyzerRegistry.default.allContentTypes.forEach { print($0) }
        exit(0)
    case "-h", "--help":
        print("usage: fourdql [--json | --html] [--thorough] <file>...")
        exit(0)
    default: paths.append(arg)
    }
}
guard !paths.isEmpty else {
    FileHandle.standardError.write("usage: fourdql [--json | --html] [--thorough] <file>...\n".data(using: .utf8)!)
    exit(2)
}

let pipeline = PreviewPipeline()
var failed = false

for path in paths {
    let url = URL(fileURLWithPath: path)
    switch mode {
    case "html":
        print(pipeline.html(for: url, options: options))
    case "json":
        do {
            let model = try AnalyzerRegistry.default.analyze(url: url, options: options)
            print(String(decoding: try model.jsonData(), as: UTF8.self))
        } catch {
            FileHandle.standardError.write("\(path): \(error)\n".data(using: .utf8)!)
            failed = true
        }
    default:
        let start = Date()
        let report = pipeline.report(for: url, options: options)
        let ms = Int(Date().timeIntervalSince(start) * 1000)
        print("== \(report.title)  (\(ms) ms)")
        if let s = report.subtitle { print("   \(s)") }
        if !report.badges.isEmpty { print("   [" + report.badges.map(\.text).joined(separator: "] [") + "]") }
        print("   " + report.stats.map { "\($0.label): \($0.value)" }.joined(separator: "  "))
        for section in report.sections {
            print("-- \(section.title)")
            for block in section.blocks { printBlock(block, indent: "   ") }
        }
    }
}

func printBlock(_ b: Block, indent: String) {
    switch b {
    case .keyValues(let kv): kv.forEach { print("\(indent)\($0.key): \($0.value)") }
    case .identity(let label, let value, let caption):
        print("\(indent)\(label): \(value)" + (caption.map { "  (\($0))" } ?? ""))
    case .meter(let fraction, let label, let caption):
        let filled = Int((max(0, min(1, fraction)) * 20).rounded())
        print("\(indent)[\(String(repeating: "#", count: filled))\(String(repeating: ".", count: 20 - filled))] \(label)" + (caption.map { " — \($0)" } ?? ""))
    case .table(let t):
        print(indent + t.columns.map(\.0).joined(separator: " | "))
        t.rows.forEach { print(indent + $0.joined(separator: " | ")) }
        if let more = t.more { print(indent + more) }
    case .bars(let rows, let valueHeader, let extraHeader):
        print("\(indent)(\(valueHeader)\(extraHeader.isEmpty ? "" : " / \(extraHeader)"))")
        rows.forEach { print("\(indent)\($0.label)\($0.marker.map { " \($0)" } ?? ""): \($0.display)\($0.extra.isEmpty ? "" : " / \($0.extra)")") }
    case .composition(let segments):
        print(indent + segments.filter { $0.value > 0 }.map { "\($0.label) \($0.display)" }.joined(separator: " · "))
    case .disclosure(let s, let d, let blocks):
        print("\(indent)\(s)  — \(d ?? "")")
        blocks.forEach { printBlock($0, indent: indent + "    ") }
    case .note(let t, _): print("\(indent)! \(t)")
    case .text(let t): print(indent + t)
    case .structureDiagram(let diagram):
        print("\(indent)\(diagram.nodes.count) tables, \(diagram.edges.count) relations in diagram")
        if diagram.omittedTables > 0 || diagram.omittedRelations > 0 {
            print("\(indent)\(diagram.omittedTables) tables and \(diagram.omittedRelations) relations omitted")
        }
    }
}

exit(failed ? 1 : 0)
