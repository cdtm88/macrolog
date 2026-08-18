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

    // MARK: - Full (per-meal) export

    private func meal(_ dayOfMonth: Int, hour: Int = 12, minute: Int = 30,
                      name: String = "Chicken salad",
                      estimated: Macros? = nil) -> MealExportItem {
        let date = calendar.date(from: DateComponents(year: 2026, month: 8,
                                                      day: dayOfMonth,
                                                      hour: hour, minute: minute))!
        return MealExportItem(capturedAt: date, name: name,
                              macros: Macros(kcal: 430, protein: 38, carbs: 22,
                                             fat: 18, fiber: 6, sodium: 640),
                              estimated: estimated)
    }

    private let mealHeader = "date,time,name,kcal,protein_g,carbs_g,fat_g,fiber_g,sodium_mg,"
        + "est_kcal,est_protein_g,est_carbs_g,est_fat_g,est_fiber_g,est_sodium_mg"

    @Test func emptyMealInputYieldsHeaderOnly() {
        #expect(DailyTotalsExport.mealCSV(items: [], calendar: calendar)
                == mealHeader + "\n")
    }

    @Test func fullMealExampleRowWithoutEstimateLeavesColumnsEmpty() {
        let csv = DailyTotalsExport.mealCSV(items: [meal(10)], calendar: calendar)
        #expect(csv == mealHeader + """

        2026-08-10,12:30,Chicken salad,430,38,22,18,6,640,,,,,,

        """)
    }

    @Test func mealRowCarriesTheFrozenEstimate() {
        let csv = DailyTotalsExport.mealCSV(
            items: [meal(10, estimated: Macros(kcal: 610, protein: 41, carbs: 25,
                                               fat: 33, fiber: 5, sodium: 1400))],
            calendar: calendar)
        #expect(csv.contains("430,38,22,18,6,640,610,41,25,33,5,1400\n"))
    }

    @Test func mealRowsAreOldestFirstRegardlessOfInputOrder() {
        let csv = DailyTotalsExport.mealCSV(
            items: [meal(10, hour: 19), meal(10, hour: 8), meal(3)],
            calendar: calendar)
        let stamps = csv.split(separator: "\n").dropFirst().map { $0.prefix(16) }
        #expect(stamps == ["2026-08-03,12:30", "2026-08-10,08:30", "2026-08-10,19:30"])
    }

    @Test func mealNamesWithCommasOrQuotesAreCSVQuoted() {
        let csv = DailyTotalsExport.mealCSV(
            items: [meal(10, name: #"Fish, chips & "extra" salt"#)],
            calendar: calendar)
        #expect(csv.contains(#""Fish, chips & ""extra"" salt""#))
    }

    @Test func plainMealNamesAreNotQuoted() {
        let csv = DailyTotalsExport.mealCSV(items: [meal(10)], calendar: calendar)
        #expect(!csv.contains("\""))
    }

    @Test func formulaLeadingNamesAreDefusedWithApostrophe() {
        for name in ["=SUM(A1:A9)", "+2h brunch", "-ve cal soup", "@home wrap"] {
            let csv = DailyTotalsExport.mealCSV(items: [meal(10, name: name)],
                                                calendar: calendar)
            #expect(csv.contains(",'\(name),"), "expected '\(name) to be defused")
        }
    }
}
