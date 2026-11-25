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
    func testMultipartFieldsAndPhotoRemainIntact() {
        let photo = Data([0xff, 0xd8, 0x00, 0xff])
        let result = multipartBody(fields: ["species": "Pike", "id": "abc"], photo: photo, boundary: "test-boundary")
        XCTAssertNotNil(result.range(of: Data("name=\"species\"\r\n\r\nPike\r\n".utf8)))
        XCTAssertNotNil(result.range(of: Data("name=\"id\"\r\n\r\nabc\r\n".utf8)))
        XCTAssertNotNil(result.range(of: photo))
        XCTAssertTrue(result.suffix(Data("--test-boundary--\r\n".utf8).count).elementsEqual(Data("--test-boundary--\r\n".utf8)))
    }
}
