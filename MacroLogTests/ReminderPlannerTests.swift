import Testing
import Foundation
@testable import MacroLog

/// The reminder rules (suppression, horizon, shortfall copy) are pure — these
/// tests pin them without touching UNUserNotificationCenter.
struct ReminderPlannerTests {

    // Fixed UTC calendar so results don't depend on the machine's locale.
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: day,
                                           hour: hour, minute: minute))!
    }

    /// 08:00 on 2026-08-10, before both default times.
    private var morning: Date { date(10, 8) }
    private let lunchAndDinner = [12 * 60 + 30, 19 * 60] // 12:30, 19:00

    private func plan(times: [Int]? = nil,
                      entries: [Date] = [],
                      protein: Double = 0,
                      target: Double = 160,
                      now: Date? = nil,
                      enabled: Bool = true) -> [PlannedReminder] {
        ReminderPlanner.plan(enabled: enabled,
                             times: times ?? lunchAndDinner,
                             todayEntryTimes: entries,
                             todayProtein: protein,
                             proteinTarget: target,
                             now: now ?? morning,
                             calendar: calendar)
    }

    @Test func disabledOrNoTimesYieldsEmptyPlan() {
        #expect(plan(enabled: false).isEmpty)
        #expect(plan(times: []).isEmpty)
    }

    @Test func fullHorizonWhenNothingLogged() {
        let reminders = plan()
        #expect(reminders.count == ReminderPlanner.horizonDays * 2)
        #expect(reminders == reminders.sorted { $0.fireDate < $1.fireDate })
    }

    @Test func pastTimesTodayAreNotScheduled() {
        let reminders = plan(now: date(10, 13)) // after 12:30, before 19:00
        #expect(!reminders.contains { $0.fireDate == date(10, 12, 30) })
        #expect(reminders.contains { $0.fireDate == date(10, 19) })
        #expect(reminders.count == ReminderPlanner.horizonDays * 2 - 1)
    }

    @Test func mealWithinWindowSuppressesOnlyThatReminder() {
        // Logged 12:00 — suppresses 12:30 (30 min before) but not 19:00.
        let reminders = plan(entries: [date(10, 12)])
        #expect(!reminders.contains { $0.fireDate == date(10, 12, 30) })
        #expect(reminders.contains { $0.fireDate == date(10, 19) })
    }

    @Test func suppressionBoundaryIsInclusive() {
        // Exactly T − 2h suppresses; one second earlier does not.
        let atBoundary = plan(entries: [date(10, 10, 30)])
        #expect(!atBoundary.contains { $0.fireDate == date(10, 12, 30) })

        let justOutside = plan(entries: [date(10, 10, 30).addingTimeInterval(-1)])
        #expect(justOutside.contains { $0.fireDate == date(10, 12, 30) })
    }

    @Test func futureDaysAreNeverSuppressed() {
        let reminders = plan(entries: [date(10, 18)]) // suppresses today's 19:00
        #expect(!reminders.contains { $0.fireDate == date(10, 19) })
        #expect(reminders.contains { $0.fireDate == date(11, 19) })
    }

    @Test func yesterdaysEntryNeverSuppressesToday() {
        // A stale entry time from the previous day must be ignored even if it
        // falls inside the window arithmetic.
        let reminders = plan(times: [60], // 01:00 today
                             entries: [date(9, 23, 30)],
                             now: date(10, 0, 30))
        #expect(reminders.contains { $0.fireDate == date(10, 1) })
    }

    @Test func finalSlotCarriesShortfallCopy() {
        let reminders = plan(protein: 115)
        let today1900 = reminders.first { $0.fireDate == date(10, 19) }!
        #expect(today1900.body.contains("45g short"))
        #expect(today1900.title == "Protein check")
        let today1230 = reminders.first { $0.fireDate == date(10, 12, 30) }!
        #expect(today1230.body == "Anything to log?")
    }

    @Test func metTargetGetsGenericFinalCopy() {
        let reminders = plan(protein: 160)
        let today1900 = reminders.first { $0.fireDate == date(10, 19) }!
        #expect(today1900.body == "Anything to log?")
        #expect(!today1900.body.contains("short"))
    }

    @Test func futureDaysAssumeNothingLogged() {
        // A future-day reminder only fires if the app never opened that day,
        // so its shortfall is the full target regardless of today's protein.
        let reminders = plan(protein: 160)
        let tomorrow1900 = reminders.first { $0.fireDate == date(11, 19) }!
        #expect(tomorrow1900.body.contains("160g short"))
    }

    @Test func unsortedTimesStillMakeLatestTimeFinal() {
        let reminders = plan(times: [19 * 60, 12 * 60 + 30], protein: 100)
        let today1900 = reminders.first { $0.fireDate == date(10, 19) }!
        #expect(today1900.body.contains("60g short"))
        #expect(reminders == reminders.sorted { $0.fireDate < $1.fireDate })
    }

    @Test func identifiersAreDeterministicAndPrefixed() {
        let first = plan()
        let second = plan()
        #expect(first.map(\.id) == second.map(\.id))
        #expect(first.allSatisfy { $0.id.hasPrefix(ReminderPlanner.idPrefix) })
        #expect(Set(first.map(\.id)).count == first.count)
        #expect(first.first?.id == "mealreminder.2026-08-10.750")
    }
}

/// The dedicated protein check: never suppressed by meal logging, skipped only
/// once the target is met (or its time has passed).
struct ProteinReminderPlannerTests {

    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 8, day: day,
                                           hour: hour, minute: minute))!
    }

    /// 08:00 on 2026-08-10, before the default 20:00 check.
    private var morning: Date { date(10, 8) }

    private func proteinPlan(time: Int = 20 * 60,
                             protein: Double = 0,
                             target: Double = 160,
                             now: Date? = nil,
                             enabled: Bool = true) -> [PlannedReminder] {
        ReminderPlanner.proteinPlan(enabled: enabled,
                                    timeMinutes: time,
                                    todayProtein: protein,
                                    proteinTarget: target,
                                    now: now ?? morning,
                                    calendar: calendar)
    }

    @Test func disabledYieldsEmptyPlan() {
        #expect(proteinPlan(enabled: false).isEmpty)
    }

    @Test func fullHorizonWhenNothingLogged() {
        let reminders = proteinPlan()
        #expect(reminders.count == ReminderPlanner.horizonDays)
        #expect(reminders == reminders.sorted { $0.fireDate < $1.fireDate })
    }

    @Test func firesDespiteRecentMealLog() {
        // A meal at 19:30 suppresses a 19:00-adjacent *meal* reminder slot but
        // must leave the protein check untouched — that's its whole purpose.
        let meals = ReminderPlanner.plan(enabled: true,
                                         times: [20 * 60],
                                         todayEntryTimes: [date(10, 19, 30)],
                                         todayProtein: 90,
                                         proteinTarget: 160,
                                         now: date(10, 19, 45),
                                         calendar: calendar)
        #expect(!meals.contains { $0.id == "mealreminder.2026-08-10.1200" })

        let protein = proteinPlan(protein: 90, now: date(10, 19, 45))
        #expect(protein.contains { $0.id == "proteinreminder.2026-08-10.1200" })
    }

    @Test func skippedWhenTargetMet() {
        let reminders = proteinPlan(protein: 160)
        #expect(!reminders.contains { $0.fireDate == date(10, 20) })
        #expect(reminders.contains { $0.fireDate == date(11, 20) })
        #expect(reminders.count == ReminderPlanner.horizonDays - 1)
    }

    @Test func skippedWhenTimePast() {
        let reminders = proteinPlan(now: date(10, 21))
        #expect(!reminders.contains { $0.fireDate == date(10, 20) })
        #expect(reminders.count == ReminderPlanner.horizonDays - 1)
    }

    @Test func copyCarriesTodaysShortfall() {
        let reminders = proteinPlan(protein: 150)
        let today = reminders.first { $0.fireDate == date(10, 20) }!
        #expect(today.title == "Protein check")
        #expect(today.body == "You're 10g short of your protein target.")
    }

    @Test func futureDaysAssumeFullShortfall() {
        let reminders = proteinPlan(protein: 150)
        let tomorrow = reminders.first { $0.fireDate == date(11, 20) }!
        #expect(tomorrow.body.contains("160g short"))
    }

    @Test func identifiersDistinctFromMealReminders() {
        let first = proteinPlan()
        let second = proteinPlan()
        #expect(first.map(\.id) == second.map(\.id))
        #expect(first.allSatisfy { $0.id.hasPrefix(ReminderPlanner.proteinIDPrefix) })
        #expect(Set(first.map(\.id)).count == first.count)
        #expect(first.first?.id == "proteinreminder.2026-08-10.1200")

        // A meal reminder at the same time on the same day must not collide.
        let meals = ReminderPlanner.plan(enabled: true, times: [20 * 60],
                                         todayEntryTimes: [], todayProtein: 0,
                                         proteinTarget: 160, now: morning,
                                         calendar: calendar)
        #expect(Set(meals.map(\.id)).isDisjoint(with: Set(first.map(\.id))))
    }
}
