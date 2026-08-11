import Testing
import Foundation
@testable import MacroLog

/// Pins the Morning / Lunch / Evening boundaries the day list groups by.
struct MealPeriodTests {

    // Fixed UTC calendar so results don't depend on the machine's locale.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: 10,
                                           hour: hour, minute: minute))!
    }

    @Test func boundaries() {
        #expect(MealPeriod.period(for: date(0, 0), calendar: calendar) == .morning)
        #expect(MealPeriod.period(for: date(10, 59), calendar: calendar) == .morning)
        #expect(MealPeriod.period(for: date(11, 0), calendar: calendar) == .lunch)
        #expect(MealPeriod.period(for: date(16, 59), calendar: calendar) == .lunch)
        #expect(MealPeriod.period(for: date(17, 0), calendar: calendar) == .evening)
        #expect(MealPeriod.period(for: date(23, 59), calendar: calendar) == .evening)
    }

    @Test func displayOrderIsNewestFirstAndComplete() {
        #expect(MealPeriod.displayOrder == [.evening, .lunch, .morning])
        #expect(Set(MealPeriod.displayOrder) == Set(MealPeriod.allCases))
    }
}
