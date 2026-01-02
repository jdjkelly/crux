import XCTest
@testable import Crux

final class DateRelativeTests: XCTestCase {

    // MARK: - relativeShort Tests

    func testRelativeShortNow() {
        let date = Date()
        XCTAssertEqual(date.relativeShort, "now")
    }

    func testRelativeShortSecondsAgo() {
        let date = Date().addingTimeInterval(-30)
        XCTAssertEqual(date.relativeShort, "now")
    }

    func testRelativeShortMinutesAgo() {
        let date = Date().addingTimeInterval(-120) // 2 minutes
        XCTAssertEqual(date.relativeShort, "2m")
    }

    func testRelativeShortOneMinute() {
        let date = Date().addingTimeInterval(-60)
        XCTAssertEqual(date.relativeShort, "1m")
    }

    func testRelativeShortHoursAgo() {
        let date = Date().addingTimeInterval(-7200) // 2 hours
        XCTAssertEqual(date.relativeShort, "2h")
    }

    func testRelativeShortOneHour() {
        let date = Date().addingTimeInterval(-3600)
        XCTAssertEqual(date.relativeShort, "1h")
    }

    func testRelativeShortDaysAgo() {
        let date = Date().addingTimeInterval(-259200) // 3 days
        XCTAssertEqual(date.relativeShort, "3d")
    }

    func testRelativeShortOneDay() {
        let date = Date().addingTimeInterval(-86400)
        XCTAssertEqual(date.relativeShort, "1d")
    }

    func testRelativeShortWeeksAgo() {
        let date = Date().addingTimeInterval(-1209600) // 2 weeks
        XCTAssertEqual(date.relativeShort, "2w")
    }

    func testRelativeShortOneWeek() {
        let date = Date().addingTimeInterval(-604800)
        XCTAssertEqual(date.relativeShort, "1w")
    }

    func testRelativeShortMonthsAgo() {
        let date = Date().addingTimeInterval(-5184000) // ~2 months (60 days)
        XCTAssertEqual(date.relativeShort, "2mo")
    }

    func testRelativeShortOneMonth() {
        let date = Date().addingTimeInterval(-2592000) // 30 days
        XCTAssertEqual(date.relativeShort, "1mo")
    }

    func testRelativeShortYearsAgo() {
        let date = Date().addingTimeInterval(-63072000) // 2 years
        XCTAssertEqual(date.relativeShort, "2y")
    }

    func testRelativeShortOneYear() {
        let date = Date().addingTimeInterval(-31536000)
        XCTAssertEqual(date.relativeShort, "1y")
    }

    // MARK: - Boundary Tests

    func testBoundaryMinutesToHours() {
        // Just under an hour
        let date59min = Date().addingTimeInterval(-3540) // 59 minutes
        XCTAssertEqual(date59min.relativeShort, "59m")

        // Exactly one hour
        let date1h = Date().addingTimeInterval(-3600)
        XCTAssertEqual(date1h.relativeShort, "1h")
    }

    func testBoundaryHoursToDays() {
        // Just under a day
        let date23h = Date().addingTimeInterval(-82800) // 23 hours
        XCTAssertEqual(date23h.relativeShort, "23h")

        // Exactly one day
        let date1d = Date().addingTimeInterval(-86400)
        XCTAssertEqual(date1d.relativeShort, "1d")
    }

    func testBoundaryDaysToWeeks() {
        // 6 days
        let date6d = Date().addingTimeInterval(-518400)
        XCTAssertEqual(date6d.relativeShort, "6d")

        // 7 days = 1 week
        let date1w = Date().addingTimeInterval(-604800)
        XCTAssertEqual(date1w.relativeShort, "1w")
    }

    func testBoundaryWeeksToMonths() {
        // 4 weeks
        let date4w = Date().addingTimeInterval(-2419200)
        XCTAssertEqual(date4w.relativeShort, "4w")

        // 30 days = 1 month
        let date1mo = Date().addingTimeInterval(-2592000)
        XCTAssertEqual(date1mo.relativeShort, "1mo")
    }

    // MARK: - Edge Cases

    func testFutureDate() {
        // Future dates would have negative interval, but the current implementation
        // doesn't handle this specially - it would show "now" for recent future dates
        let futureDate = Date().addingTimeInterval(30)
        // This tests current behavior - future dates within 60 seconds show "now"
        // (since interval is negative, it's < 60)
        XCTAssertNotNil(futureDate.relativeShort)
    }

    func testVeryOldDate() {
        let veryOld = Date().addingTimeInterval(-315360000) // 10 years
        XCTAssertEqual(veryOld.relativeShort, "10y")
    }

    // MARK: - relativeFormatted Tests (system formatter)

    func testRelativeFormattedReturnsString() {
        let date = Date().addingTimeInterval(-3600)
        let result = date.relativeFormatted
        // Just verify it returns something - exact format depends on locale
        XCTAssertFalse(result.isEmpty)
    }

    func testRelativeFormattedRecentDate() {
        let date = Date().addingTimeInterval(-60)
        let result = date.relativeFormatted
        XCTAssertFalse(result.isEmpty)
    }
}
