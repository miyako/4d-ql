import XCTest
@testable import FourDFileKit
@testable import FourDRender

final class QueryTests: XCTestCase {
    func testQueryConditionMarkupRemainsByteExact() {
        let condition = QueryCondition(connector: "WHERE", field: "<Field>", operation: "is & equal",
                                       code: "1", operands: [KeyValue("value", "\"saved\"", mono: true)])
        var report = Report(title: "Query")
        report.sections = [Section("", [.queryConditions([condition])])]
        let html = HTMLRenderer().render(report)
        let expected = #"<ol class="query-conditions"><li><span class="query-connector">WHERE</span><div class="query-card"><div class="query-field">&lt;Field&gt;</div><div class="query-operation">is &amp; equal <span class="query-code">criterion 1</span></div><dl><dt>value</dt><dd class="mono">&quot;saved&quot;</dd></dl></div></li></ol>"#
        XCTAssertTrue(html.contains(expected))
        report.sections = [Section("", [.queryConditions([])])]
        XCTAssertTrue(HTMLRenderer().render(report).contains(#"<ol class="query-conditions"></ol>"#))
    }

    private func file(_ text: String, ext: String = "4df") throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
        try text.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try FileManager.default.removeItem(at: url) }
        return url
    }

    func testAttachedQueryShapeWithBOM() throws {
        let text = """
        {"mainTable":1,"queryDestination":1,"version":3,"ja":false,"lines":[
          {"tableNumber":"1","fieldNumber":"2","criterion":"15","oneBox":""},
          {"lineOperator":"1","tableNumber":"1","fieldNumber":"4","criterion":"1","oneBox":"abc"}
        ]}
        """
        let url = try file("\u{FEFF}" + text, ext: "4DF")
        let info = try XCTUnwrap(try AnalyzerRegistry.default.analyze(url: url) as? QueryFileInfo)
        XCTAssertEqual(info.text, text)
        XCTAssertEqual(info.lines.count, 2)
        let html = PreviewPipeline().html(for: url)
        for expected in ["4D Saved Query", "Create selection", "Table 1 / Field 2",
                         "is in list", "WHERE", "AND", "Table 1 / Field 4", "is equal to",
                         "abc", "&quot;&quot; (empty)", "Original JSON", "Version 3"] {
            XCTAssertTrue(html.contains(expected), expected)
        }
        XCTAssertTrue(html.contains("<ol class=\"query-conditions\">"))
        XCTAssertTrue(html.contains("<details><summary><span class=\"st\">Original JSON"))
        XCTAssertFalse(html.contains("Query details"))
        XCTAssertFalse(html.contains("Table and field names/types are not stored"))
        XCTAssertFalse(html.contains("<dt>ja</dt>"))
        XCTAssertFalse(html.contains("<dt>queryDestination</dt>"))
        XCTAssertFalse(html.contains("No preview available"))
    }

    func testUTIRoutingWithoutExtension() throws {
        let url = try file(#"{"mainTable":"1","version":3,"lines":[]}"#, ext: "txt")
        XCTAssertTrue(try AnalyzerRegistry.default.analyze(url: url, contentType: "com.4d.4d.queryFile") is QueryFileInfo)
        XCTAssertTrue(AnalyzerRegistry.default.allContentTypes.contains("com.4d.4d.queryFile"))
    }

    func testConnectorsRangesAndUnknownInputsArePreserved() throws {
        let url = try file("""
        {"mainTable":2,"version":3,"queryDestination":4,"future":{"x":true},"lines":[
          {"tableNumber":2,"fieldNumber":3,"criterion":7,"firstBox":10,"secondBox":20},
          {"lineOperator":2,"tableNumber":2,"fieldNumber":4,"criterion":8,"oneBox":null},
          {"lineOperator":3,"tableNumber":2,"fieldNumber":5,"criterion":41},
          {"lineOperator":99,"tableNumber":2,"fieldNumber":6,"criterion":999,"formula":"<script>&\\""},
          {"tableNumber":2,"fieldNumber":7,"criterion":11,"oneBox":"日本語"}
        ]}
        """)
        let html = PreviewPipeline().html(for: url)
        for expected in ["OR", "EXCEPT", "Remove from selection", "inclusive", "exclusive",
                         "firstBox", "secondBox", "null", "is empty", "Unknown connector 99",
                         "Unknown criterion", "criterion 999", "contains / is today",
                         "日本語", "&lt;script&gt;&amp;&quot;", "future"] {
            XCTAssertTrue(html.contains(expected), expected)
        }
        XCTAssertFalse(html.contains("<script>"))
        let info = try XCTUnwrap(try AnalyzerRegistry.default.analyze(url: url) as? QueryFileInfo)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: info.jsonData()) as? [String: Any])
        XCTAssertEqual((json["lines"] as? [[String: Any]])?.count, 5)
        XCTAssertNotNil((json["properties"] as? [String: Any])?["future"])
    }

    func testLargeIntegerValuesRemainExact() throws {
        let url = try file(#"{"mainTable":1,"version":3,"lines":[{"criterion":1,"oneBox":9223372036854775807}]}"#)
        let info = try XCTUnwrap(try AnalyzerRegistry.default.analyze(url: url) as? QueryFileInfo)
        XCTAssertEqual(info.lines[0]["oneBox"], .integerNumber(Int64.max))
        XCTAssertTrue(String(decoding: try info.jsonData(), as: UTF8.self).contains("9223372036854775807"))
        XCTAssertTrue(PreviewPipeline().html(for: url).contains("9223372036854775807"))
    }

    func testUnknownVersionDoesNotGuessSemantics() throws {
        let url = try file(#"{"mainTable":1,"version":99,"lines":[{"criterion":15}]}"#)
        let html = PreviewPipeline().html(for: url)
        XCTAssertTrue(html.contains("This query version is not decoded"))
        XCTAssertTrue(html.contains("Version 99"))
        XCTAssertTrue(html.contains("Original JSON"))
        XCTAssertFalse(html.contains("<ol class=\"query-conditions\">"))
        XCTAssertFalse(html.contains("is in list"))
    }

    func testSelectionDestinationsAndComparisonLabels() throws {
        for (code, label) in [(1, "Create selection"), (2, "Filter selection"),
                              (3, "Add to selection"), (4, "Remove from selection"),
                              (99, "Query destination 99")] {
            let url = try file(#"{"mainTable":1,"version":3,"queryDestination":\#(code),"lines":[]}"#)
            XCTAssertTrue(PreviewPipeline().html(for: url).contains(label))
        }
        for (code, label) in [(0, "is false"), (1, "is true / is equal to"),
                              (2, "is not equal to"), (3, "is greater than or equal to"),
                              (4, "is greater than"), (5, "is less than or equal to"),
                              (6, "is less than"), (9, "starts with"), (10, "ends with"),
                              (12, "does not contain / is within current period"),
                              (13, "contains keywords"), (14, "does not contain keywords"),
                              (21, "is yesterday"), (31, "is tomorrow"), (42, "is not empty"),
                              (-999, "Unknown criterion")] {
            let url = try file(#"{"mainTable":1,"version":3,"lines":[{"tableNumber":1,"fieldNumber":1,"criterion":\#(code)}]}"#)
            let html = PreviewPipeline().html(for: url)
            XCTAssertTrue(html.contains(label), "\(code): \(label)")
            XCTAssertTrue(html.contains("criterion \(code)"))
        }
    }

    func testEmptyQueryAndMissingConnectorAreExplicit() throws {
        let empty = try file(#"{"mainTable":1,"version":3,"lines":[]}"#)
        XCTAssertTrue(PreviewPipeline().html(for: empty).contains("No conditions are saved"))
        let missing = try file(#"{"mainTable":1,"version":3,"lines":[{},{}]}"#)
        let html = PreviewPipeline().html(for: missing)
        XCTAssertTrue(html.contains("Unknown connector (not saved)"))
        XCTAssertTrue(html.contains("Unknown criterion"))
        XCTAssertTrue(html.contains("Field (not saved)"))
    }

    func testMalformedQueriesShowErrors() throws {
        for text in ["", "not JSON", "[]", "{}", #"{"mainTable":true,"lines":[]}"#,
                     #"{"mainTable":0,"lines":[]}"#, #"{"mainTable":1,"lines":{}}"#,
                     #"{"mainTable":1,"lines":[null]}"#] {
            let url = try file(text)
            XCTAssertThrowsError(try AnalyzerRegistry.default.analyze(url: url), text)
            XCTAssertTrue(PreviewPipeline().html(for: url).contains("No preview available"), text)
        }
    }

    func testInvalidUTF8AndSizeLimit() throws {
        let url = try file("")
        try Data([0xFF, 0xFE, 0x01]).write(to: url)
        XCTAssertThrowsError(try AnalyzerRegistry.default.analyze(url: url)) { error in
            XCTAssertEqual(String(describing: error), QueryFileError.invalidUTF8.description)
        }
        try Data(repeating: 0x20, count: 4 * 1024 * 1024 + 1).write(to: url)
        XCTAssertThrowsError(try AnalyzerRegistry.default.analyze(url: url)) { error in
            XCTAssertEqual(String(describing: error), QueryFileError.tooLarge.description)
        }
    }

    func testConditionCardLimitRetainsAllLinesInModelAndSource() throws {
        let lines = (1...201).map {
            #"{"tableNumber":1,"fieldNumber":\#($0),"criterion":1,"oneBox":"value\#($0)"}"#
        }.joined(separator: ",")
        let url = try file(#"{"mainTable":1,"version":3,"lines":[\#(lines)]}"#)
        let info = try XCTUnwrap(try AnalyzerRegistry.default.analyze(url: url) as? QueryFileInfo)
        XCTAssertEqual(info.lines.count, 201)
        let html = PreviewPipeline().html(for: url)
        XCTAssertEqual(html.components(separatedBy: "<div class=\"query-card\">").count - 1, 200)
        XCTAssertTrue(html.contains("Showing the first 200 conditions"))
        XCTAssertTrue(html.contains("value201"))
    }
}
