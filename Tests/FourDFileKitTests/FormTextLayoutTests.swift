#if canImport(AppKit)
import AppKit
#endif
import XCTest
@testable import FourDFileKit
@testable import FourDRender

final class FormTextLayoutTests: XCTestCase {
    private let plain = FormValue.object([])

    func testWrappingUsesWordBoundariesAndShapedAdvances() {
        let text = "office affinity alpha beta gamma"
        let font = FormTextLayout.font(size: 13, properties: plain)
        let width = font.width("office affinity ") + 1
        let layout = FormTextLayout(text: text, width: width, size: 13, properties: plain, maxLines: 10)
        XCTAssertEqual(layout.lines.first?.text, "office affinity ")
        XCTAssertEqual(layout.lines.map(\.text).joined(), text)
        XCTAssertTrue(layout.lines.allSatisfy { $0.width <= width + 0.01 })
    }

    func testExplicitBlankLinesAndLineEndingsArePreserved() {
        let layout = FormTextLayout(text: "First\r\n\r\nLast\r", width: 200, size: 13, properties: plain, maxLines: 10)
        XCTAssertEqual(layout.lines.map(\.text), ["First", "", "Last", ""])
    }

    func testNarrowWrappingNeverSplitsComposedCharacters() {
        let text = "e\u{301}👨‍👩‍👧‍👦日本語"
        let layout = FormTextLayout(text: text, width: 1, size: 13, properties: plain, maxLines: 20)
        XCTAssertEqual(layout.lines.map(\.text).joined(), text)
        XCTAssertTrue(layout.lines.allSatisfy { $0.text.count == 1 })
    }

    func testRightToLeftTextRetainsLogicalOrder() {
        let text = "مرحبا بالعالم هذا نص عربي"
        let layout = FormTextLayout(text: text, width: 90, size: 13, properties: plain, maxLines: 20)
        XCTAssertGreaterThan(layout.lines.count, 1)
        XCTAssertEqual(layout.lines.map(\.text).joined(), text)
    }

    func testSingleLineAndWorkLimits() {
        let single = FormTextLayout(text: "First\nSecond", width: 1, size: 13,
                                    properties: .object([FormMember(name: "multiline", value: .string("no"))]), maxLines: 10)
        XCTAssertEqual(single.lines.map(\.text), ["First"])
        let bounded = FormTextLayout(text: String(repeating: "x", count: 10_000), width: 1, size: 13,
                                     properties: plain, maxLines: 10_000)
        XCTAssertEqual(bounded.lines.count, 100)
        let characters = FormTextLayout(text: String(repeating: "x", count: 10_000), width: 10_000, size: 13,
                                        properties: plain, maxLines: 1)
        XCTAssertEqual(characters.lines.first?.text.count, 4_096)
    }

    func testUTF16BudgetDoesNotShapeAnUnboundedGrapheme() {
        let hugeCluster = "a" + String(repeating: "\u{301}", count: 6_000)
        XCTAssertEqual(FormTextLayout.bounded(hugeCluster), "")
        let text = String(repeating: "x", count: 4_095) + "👨‍👩‍👧‍👦"
        XCTAssertEqual(FormTextLayout.bounded(text), String(repeating: "x", count: 4_095))
        XCTAssertEqual(FormTextLayout.bounded("e\u{301}"), "e\u{301}")
    }

    func testNoWordwrapPreservesExplicitLinesWithoutSoftWrapping() throws {
        let properties = FormValue.object([FormMember(name: "wordwrap", value: .string("none")),
                                           FormMember(name: "multiline", value: .string("yes"))])
        let layout = FormTextLayout(text: "Long first line\r\n\r\nLong last line\r", width: 1, size: 13,
                                    properties: properties, maxLines: 10)
        XCTAssertEqual(layout.lines.map(\.text), ["Long first line", "", "Long last line", ""])
        XCTAssertGreaterThan(try XCTUnwrap(layout.lines.first).width, 1)
    }
}

#if canImport(AppKit)
extension FormTextLayoutTests {
    func testFontTraitsAndFallbackAreConsistent() {
        let styled = FormValue.object([FormMember(name: "fontWeight", value: .string("bold")),
                                       FormMember(name: "fontStyle", value: .string("italic"))])
        let font = FormTextLayout.font(size: 13, properties: styled).font
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.bold))
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.italic))
        let missing = FormValue.object([FormMember(name: "fontFamily", value: .string("Missing Form Font"))])
        XCTAssertEqual(FormTextLayout.font(size: 13, properties: missing).font.fontName,
                       FormTextLayout.font(size: 13, properties: plain).font.fontName)
    }

    func testMainFontThemeHasBoldDefaultAndRespectsWeightOverride() {
        let main = FormValue.object([FormMember(name: "fontTheme", value: .string("main"))])
        XCTAssertTrue(FormTextLayout.font(size: 13, properties: main).font.fontDescriptor.symbolicTraits.contains(.bold))
        var normal = main
        normal["fontWeight"] = .string("normal")
        XCTAssertFalse(FormTextLayout.font(size: 13, properties: normal).font.fontDescriptor.symbolicTraits.contains(.bold))
    }

    func testExplicitHelveticaKeepsNativeParagraphLeading() {
        let properties = FormValue.object([FormMember(name: "fontFamily", value: .string("Helvetica"))])
        let layout = FormTextLayout(text: "First\n\nLast", width: 200, size: 15, properties: properties, maxLines: 10)
        XCTAssertEqual(layout.lineHeight, 18)
        XCTAssertEqual(layout.lines.map(\.text), ["First", "", "Last"])
    }

    func testArialUsesItsMeasuredNativeLineAdvance() {
        let properties = FormValue.object([FormMember(name: "fontFamily", value: .string("Arial"))])
        for (size, advance) in [(13.0, 15.0), (15.0, 17.0)] {
            let layout = FormTextLayout(text: "Hgj\n\nHgj", width: 180, size: size, properties: properties, maxLines: 10)
            XCTAssertEqual(layout.lineHeight, advance)
        }
    }
}
#endif

#if os(Windows)
extension FormTextLayoutTests {
    func testDirectWriteMeasuresSegoeUI() {
        XCTAssertTrue(FormFontFace.installed("Segoe UI", size: 12))
        let font = FormTextLayout.font(size: 12, properties: plain, platform: .windows)
        XCTAssertGreaterThan(font.width("Windows"), font.width("W"))
        XCTAssertGreaterThan(font.lineHeight, 12)
        let layout = FormTextLayout(text: "alpha beta gamma delta", width: font.width("alpha beta ") + 1, size: 12,
                                    properties: plain, maxLines: 10, platform: .windows)
        XCTAssertEqual(layout.lines.first?.text, "alpha beta ")
    }
}
#endif
