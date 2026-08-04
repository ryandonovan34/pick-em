import XCTest
@testable import PickEm

final class WeekModelTests: XCTestCase {

    func testDisplayLabel_fallsBackToLabel_whenWithinStandardWeekWindow() {
        // Regression test: MockData's windowed() helper used to set endsOn
        // unconditionally, which made every mock week render as a raw date
        // range (e.g. "Jun 1 – Jun 5") instead of its real "Week N" label.
        XCTAssertEqual(MockData.nflWeek.displayLabel, "Week 9")
        XCTAssertEqual(MockData.nflWeek13.displayLabel, "Week 10")
    }

    func testDisplayLabel_allHistoryWeeksFallBackToLabel() {
        // History weeks alternate their closing prime-time slot between SNF
        // (odd week numbers) and MNF (even) — see MockData.weeklySlotKickoff.
        // A standard NFL week runs Thursday through the FOLLOWING Monday
        // (MNF), which is +7 days from a Monday-anchored startsOn — windowed()
        // only widens endsOn past +7, so both SNF (+6) and MNF (+7 exactly,
        // not beyond it) weeks stay within the standard window and show
        // "Week N", not a raw date range.
        for week in MockData.allWeeks {
            XCTAssertEqual(week.displayLabel, week.label, "week \(week.id) rendered a date range instead of \"\(week.label)\"")
        }
    }

    func testDisplayLabel_usesDateRange_whenWindowExceedsSevenDays() {
        let week = Week(
            id: "w", groupID: "g", weekNumber: 1, label: "Custom Window", createdAt: Date(),
            startsOn: Date(timeIntervalSince1970: 0),
            endsOn: Date(timeIntervalSince1970: 0).addingTimeInterval(86400 * 9)
        )
        XCTAssertNotEqual(week.displayLabel, week.label)
    }
}
