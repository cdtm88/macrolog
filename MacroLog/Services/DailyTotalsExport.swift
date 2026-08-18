import Foundation

/// One day's confirmed totals, for export.
struct DailyTotal: Equatable {
    let dayStart: Date
    let totals: Macros
    let entryCount: Int
}

/// One confirmed meal, for the full export. `estimated` is the AI's frozen
/// original estimate — nil for favourites and pre-instrumentation entries.
struct MealExportItem: Equatable {
    let capturedAt: Date
    let name: String
    let macros: Macros
    var estimated: Macros? = nil
}

/// Formats the settings sheet's CSV export. Pure — no I/O — so the format is
/// pinned by unit tests. Two granularities: "lite" is one row per day's
/// totals; "full" (2026-08-18 field feedback) is one row per meal with its
/// name and time.
enum DailyTotalsExport {
    static let header = "date,kcal,protein_g,carbs_g,fat_g,fiber_g,sodium_mg,entries"
    static let mealHeader = "date,time,name,kcal,protein_g,carbs_g,fat_g,fiber_g,sodium_mg,"
        + "est_kcal,est_protein_g,est_carbs_g,est_fat_g,est_fiber_g,est_sodium_mg"

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

    /// One row per confirmed meal, oldest first; local `yyyy-MM-dd` and
    /// `HH:mm`, values rounded to integers. Names are CSV-quoted when they
    /// contain a comma, quote, or newline. The `est_*` columns carry the AI's
    /// original estimate for measuring bias against the confirmed values;
    /// they're empty when no estimate was recorded.
    static func mealCSV(items: [MealExportItem], calendar: Calendar = .current) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.calendar = calendar
        dateFormatter.timeZone = calendar.timeZone
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "en_US_POSIX")
        timeFormatter.calendar = calendar
        timeFormatter.timeZone = calendar.timeZone
        timeFormatter.dateFormat = "HH:mm"

        let rows = items.sorted { $0.capturedAt < $1.capturedAt }.map { item in
            return ([dateFormatter.string(from: item.capturedAt),
                     timeFormatter.string(from: item.capturedAt),
                     csvField(item.name)]
                    + macroFields(item.macros)
                    + (item.estimated.map(macroFields) ?? Array(repeating: "", count: 6)))
                .joined(separator: ",")
        }
        return ([mealHeader] + rows).joined(separator: "\n") + "\n"
    }

    private static func macroFields(_ m: Macros) -> [String] {
        [m.kcal, m.protein, m.carbs, m.fat, m.fiber, m.sodium]
            .map { String(Int($0.rounded())) }
    }

    private static func csvField(_ value: String) -> String {
        // Defuse spreadsheet formula injection: a leading =, +, - or @ turns
        // the cell into a live formula when the CSV is opened in Excel or
        // Sheets. The leading apostrophe is the spreadsheet convention for
        // "treat as text".
        let defused = "=+-@".contains(value.first ?? " ") ? "'" + value : value
        guard defused.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else {
            return defused
        }
        return "\"" + defused.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
