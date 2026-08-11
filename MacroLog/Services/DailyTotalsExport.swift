import Foundation

/// One day's confirmed totals, for export.
struct DailyTotal: Equatable {
    let dayStart: Date
    let totals: Macros
    let entryCount: Int
}

/// Formats daily totals as CSV for the settings sheet's share link. Pure — no
/// I/O — so the format is pinned by unit tests. Daily granularity only: the
/// export deliberately carries no meal-level rows (names could get personal;
/// totals are what a coach or an AI chat needs).
enum DailyTotalsExport {
    static let header = "date,kcal,protein_g,carbs_g,fat_g,fiber_g,sodium_mg,entries"

    /// One row per supplied day (days without entries never reach here),
    /// oldest first, values rounded to integers to match the app's display;
    /// dates are local `yyyy-MM-dd`. Ends with a trailing newline.
    static func csv(days: [DailyTotal], calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        let rows = days.sorted { $0.dayStart < $1.dayStart }.map { day in
            let t = day.totals
            return [formatter.string(from: day.dayStart),
                    String(Int(t.kcal.rounded())),
                    String(Int(t.protein.rounded())),
                    String(Int(t.carbs.rounded())),
                    String(Int(t.fat.rounded())),
                    String(Int(t.fiber.rounded())),
                    String(Int(t.sodium.rounded())),
                    String(day.entryCount)].joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }
}
