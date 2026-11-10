import XCTest
@testable import FourDRender

final class SpreadsheetNumberFormatTests: XCTestCase {
    func testCommonNumericFormats() {
        XCTAssertEqual(SpreadsheetNumberFormat.text(1234.5, format: "#,##0.00"), "1,234.50")
        XCTAssertEqual(SpreadsheetNumberFormat.text(0.125, format: "0.0%"), "12.5%")
        XCTAssertEqual(SpreadsheetNumberFormat.text(42, format: "\"USD \"0.00"), "USD 42.00")
        XCTAssertEqual(SpreadsheetNumberFormat.text(-12.5, format: "0.00;(0.00)"), "(12.50)")
        XCTAssertEqual(SpreadsheetNumberFormat.text(7, format: "0000"), "0007")
        XCTAssertEqual(SpreadsheetNumberFormat.text(0, format: "General"), "0")
    }

    func testDatesAndTimeAreIndependentOfLocalTimeZone() {
        XCTAssertEqual(SpreadsheetNumberFormat.text(1, format: "yyyy-mm-dd"), "1900-01-01")
        XCTAssertEqual(SpreadsheetNumberFormat.text(61, format: "yyyy-mm-dd"), "1900-03-01")
        XCTAssertEqual(SpreadsheetNumberFormat.text(45_292, format: "yyyy-mm-dd"), "2024-01-01")
        XCTAssertEqual(SpreadsheetNumberFormat.text(0.5, format: "hh:mm:ss"), "12:00:00")
        XCTAssertEqual(SpreadsheetNumberFormat.text(0.75, format: "h:mm AM/PM"), "6:00 PM")
        XCTAssertEqual(SpreadsheetNumberFormat.text(45_292, format: "m/d/yyyy"), "1/1/2024")
        XCTAssertEqual(SpreadsheetNumberFormat.text(0, format: "yyyy-mm-dd", oaDate: true), "1899-12-30")
        XCTAssertEqual(SpreadsheetNumberFormat.text(1, format: "yyyy-mm-dd", oaDate: true), "1899-12-31")
        XCTAssertEqual(SpreadsheetNumberFormat.text(60, format: "yyyy-mm-dd", oaDate: true), "1900-02-28")
    }

    func testUnsupportedFormatsDoNotPretendToBeFormatted() {
        for format in ["[Red]0.00", "# ?/?", "0.00E+00", "[h]:mm", "0_);(0)", "#,##0,,", "0%%"] {
            XCTAssertNil(SpreadsheetNumberFormat.text(42, format: format), format)
        }
        XCTAssertNil(SpreadsheetNumberFormat.text(60, format: "yyyy-mm-dd"))
        XCTAssertNil(SpreadsheetNumberFormat.text(.infinity, format: "General"))
    }
}
