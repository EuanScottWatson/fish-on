import XCTest
@testable import FishCore

final class FishCoreTests: XCTestCase {
    func testDatesPreserveCalendarDay() {
        XCTAssertEqual(britishDate("2026-05-17"), "17/05/2026")
        XCTAssertEqual(britishDate(""), "Date not recorded")
        XCTAssertEqual(britishDate("unknown"), "unknown")
    }
    func testRecordsHandleNullsAndNumericCoordinates() throws {
        let data = #"[{"id":"one","lat":51.5,"lon":"-0.1","species":null}]"#.data(using: .utf8)!
        let record = try XCTUnwrap(decodeRecords(data).first)
        XCTAssertEqual(record.id, "one")
        XCTAssertEqual(record.string("species"), "")
        XCTAssertEqual(record.number("lat"), 51.5)
        XCTAssertEqual(record.number("lon"), -0.1)
        XCTAssertNil(record.number("species"))
        XCTAssertThrowsError(try decodeRecords(Data("{}".utf8)))
    }
}
