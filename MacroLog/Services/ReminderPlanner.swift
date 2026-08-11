import Foundation

/// One scheduled meal reminder, ready to hand to `ReminderScheduler`.
struct PlannedReminder: Equatable {
    let id: String
    let fireDate: Date
    let title: String
    let body: String
}

/// Decides which reminders should be pending given the settings and today's
/// entries. Pure — everything that touches `UNUserNotificationCenter` lives in
/// `ReminderScheduler`, so every rule here is unit-testable (the same split as
/// `WeightBridge.shouldSync`).
///
/// Rules:
/// - Reminders are one-shot triggers planned over the next `horizonDays` days.
///   With no background execution the app can only top the horizon up while it
///   is open; beyond it reminders go quiet and the widget stays the passive
///   nudge.
/// - A reminder at time T today is skipped when a meal was logged at or after
///   T − `suppressionWindow`. Future days are never suppressed, and today's
///   already-past times are not scheduled.
/// - The latest time each day carries protein-shortfall copy. The copy is
///   frozen at plan time, reflecting state as of the last time the app ran —
///   which is exactly the situation a reminder exists for: logging is in-app
///   only, and every confirm/foreground re-plans.
/// - A second, independent family (`proteinPlan`) checks the protein target at
///   a fixed time each day. Unlike meal reminders it is *never* suppressed by
///   a recent log — a logged low-protein meal silencing the protein nudge is
///   exactly the failure it exists to fix. It is skipped only once the target
///   is met.
enum ReminderPlanner {
    static let horizonDays = 7
    static let suppressionWindow: TimeInterval = 2 * 3600
    static let maxTimes = 3

    /// Identifier prefixes for the requests this app schedules; the scheduler
    /// replaces exactly the pending requests carrying one of them.
    static let idPrefix = "mealreminder."
    static let proteinIDPrefix = "proteinreminder."
    static var allIDPrefixes: [String] { [idPrefix, proteinIDPrefix] }

    static func plan(enabled: Bool,
                     times: [Int],
                     todayEntryTimes: [Date],
                     todayProtein: Double,
                     proteinTarget: Double,
                     now: Date = Date(),
                     calendar: Calendar = .current) -> [PlannedReminder] {
        guard enabled, !times.isEmpty else { return [] }
        let sortedTimes = times.sorted()
        let finalTime = sortedTimes.last!
        let dayStart = calendar.startOfDay(for: now)
        // Only meals logged today may suppress — guards against a caller
        // passing stale times across a midnight rollover.
        let entryTimes = todayEntryTimes.filter { calendar.isDate($0, inSameDayAs: now) }

        var result: [PlannedReminder] = []
        for offset in 0..<horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: dayStart)
            else { continue }
            for minutes in sortedTimes {
                guard let fireDate = calendar.date(byAdding: .minute, value: minutes, to: day)
                else { continue }
                if offset == 0 {
                    if fireDate <= now { continue }
                    if entryTimes.contains(where: { $0 >= fireDate - suppressionWindow }) { continue }
                }
                let logged = offset == 0 ? todayProtein : 0
                let shortfall = max(0, proteinTarget - logged)
                let isFinal = minutes == finalTime
                let title = isFinal && shortfall > 0 ? "Protein check" : "MacroLog"
                let body = isFinal && shortfall > 0
                    ? "You're \(Int(shortfall.rounded()))g short of your protein target."
                    : "Anything to log?"
                result.append(PlannedReminder(id: id(prefix: idPrefix, day: day,
                                                     minutes: minutes, calendar: calendar),
                                              fireDate: fireDate,
                                              title: title,
                                              body: body))
            }
        }
        return result
    }

    /// The dedicated daily protein check. Takes no entry times on purpose:
    /// immunity to meal-log suppression is structural, not a flag.
    static func proteinPlan(enabled: Bool,
                            timeMinutes: Int,
                            todayProtein: Double,
                            proteinTarget: Double,
                            now: Date = Date(),
                            calendar: Calendar = .current) -> [PlannedReminder] {
        guard enabled else { return [] }
        let dayStart = calendar.startOfDay(for: now)

        var result: [PlannedReminder] = []
        for offset in 0..<horizonDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: dayStart),
                  let fireDate = calendar.date(byAdding: .minute, value: timeMinutes, to: day)
            else { continue }
            if offset == 0 {
                if fireDate <= now { continue }
                if todayProtein >= proteinTarget { continue }
            }
            // Future days assume nothing logged — a future reminder only fires
            // if the app never opened that day (same reasoning as `plan`).
            let logged = offset == 0 ? todayProtein : 0
            let shortfall = max(0, proteinTarget - logged)
            result.append(PlannedReminder(id: id(prefix: proteinIDPrefix, day: day,
                                                 minutes: timeMinutes, calendar: calendar),
                                          fireDate: fireDate,
                                          title: "Protein check",
                                          body: "You're \(Int(shortfall.rounded()))g short of your protein target."))
        }
        return result
    }

    private static func id(prefix: String, day: Date, minutes: Int, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%@%04d-%02d-%02d.%d",
                      prefix, c.year ?? 0, c.month ?? 0, c.day ?? 0, minutes)
    }
}
