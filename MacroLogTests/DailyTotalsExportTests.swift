import Testing
import Foundation
@testable import MacroLog

/// Pins the CSV export format: header, ordering, rounding, units.
struct DailyTotalsExportTests {

    // Fixed UTC calendar so the yyyy-MM-dd column doesn't depend on the
    // machine's timezone.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func day(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: day))!
    }

    private func total(_ dayOfMonth: Int, kcal: Double = 1430, protein: Double = 96,
                       carbs: Double = 152, fat: Double = 48, fiber: Double = 12,
                       sodium: Double = 2300, entries: Int = 3) -> DailyTotal {
        DailyTotal(dayStart: day(dayOfMonth),
                   totals: Macros(kcal: kcal, protein: protein, carbs: carbs,
                                  fat: fat, fiber: fiber, sodium: sodium),
                   entryCount: entries)
    }

    @Test func emptyInputYieldsHeaderOnly() {
        #expect(DailyTotalsExport.csv(days: [], calendar: calendar)
                == "date,kcal,protein_g,carbs_g,fat_g,fiber_g,sodium_mg,entries\n")
    }

    @Test func fullExampleRow() {
        let csv = DailyTotalsExport.csv(days: [total(10)], calendar: calendar)
        #expect(csv == """
        date,kcal,protein_g,carbs_g,fat_g,fiber_g,sodium_mg,entries
        2026-08-10,1430,96,152,48,12,2300,3

        """)
    }

    @Test func rowsAreOldestFirstRegardlessOfInputOrder() {
        let csv = DailyTotalsExport.csv(days: [total(10), total(3), total(7)],
                                        calendar: calendar)
        let dates = csv.split(separator: "\n").dropFirst().map { $0.prefix(10) }
        #expect(dates == ["2026-08-03", "2026-08-07", "2026-08-10"])
    }

    @Test func valuesRoundToNearestInteger() {
        let csv = DailyTotalsExport.csv(
            days: [total(10, kcal: 1430.4, protein: 96.5, carbs: 151.6, fat: 47.4)],
            calendar: calendar)
        #expect(csv.contains("2026-08-10,1430,97,152,47,"))
    }

    @Test func sodiumStaysInMilligrams() {
        let csv = DailyTotalsExport.csv(days: [total(10, sodium: 2300)],
                                        calendar: calendar)
        #expect(csv.contains(",2300,3\n"))
    }

    @Test func nonConsecutiveDaysAreNotGapFilled() {
        let csv = DailyTotalsExport.csv(days: [total(3), total(10)], calendar: calendar)
        #expect(csv.split(separator: "\n").count == 3) // header + 2 rows
    }
}
