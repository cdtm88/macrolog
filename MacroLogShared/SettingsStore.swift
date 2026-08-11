import Foundation

/// User-adjustable settings, kept in the App Group so the widget can read the
/// targets directly at timeline-generation time. Deliberately not in
/// `TodaySnapshot` — the snapshot zeroes at every midnight rollover, and a
/// target is a setting, not a day-scoped total. Also deliberately not
/// SwiftData: a handful of scalars doesn't warrant a schema migration.
///
/// Unset or garbled values fall back to defaults (the same tolerance as the
/// `Macros` decoder) — the app and widget always have something to show.
public enum SettingsStore {
    public static let defaultProteinTarget: Double = 160
    public static let defaultKcalTarget: Double = 2500
    /// Minutes since local midnight — 20:00.
    public static let defaultProteinReminderTime = 20 * 60

    private static let proteinTargetKey = "protein_target_g"
    private static let kcalTargetKey = "kcal_target"
    private static let remindersEnabledKey = "reminders_enabled"
    private static let reminderTimesKey = "reminder_times_v1"
    private static let proteinReminderEnabledKey = "protein_reminder_enabled"
    private static let proteinReminderTimeKey = "protein_reminder_time"

    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: SharedConstants.appGroupID)
    }

    // MARK: - Protein target

    public static func proteinTarget(defaults: UserDefaults? = nil) -> Double {
        let store = defaults ?? sharedDefaults
        guard let value = store?.object(forKey: proteinTargetKey) as? Double,
              value > 0 else { return defaultProteinTarget }
        return value
    }

    public static func setProteinTarget(_ grams: Double, defaults: UserDefaults? = nil) {
        (defaults ?? sharedDefaults)?.set(grams, forKey: proteinTargetKey)
    }

    // MARK: - Calorie target

    public static func kcalTarget(defaults: UserDefaults? = nil) -> Double {
        let store = defaults ?? sharedDefaults
        guard let value = store?.object(forKey: kcalTargetKey) as? Double,
              value > 0 else { return defaultKcalTarget }
        return value
    }

    public static func setKcalTarget(_ kcal: Double, defaults: UserDefaults? = nil) {
        (defaults ?? sharedDefaults)?.set(kcal, forKey: kcalTargetKey)
    }

    // MARK: - Meal reminders

    public static func remindersEnabled(defaults: UserDefaults? = nil) -> Bool {
        (defaults ?? sharedDefaults)?.bool(forKey: remindersEnabledKey) ?? false
    }

    public static func setRemindersEnabled(_ enabled: Bool, defaults: UserDefaults? = nil) {
        (defaults ?? sharedDefaults)?.set(enabled, forKey: remindersEnabledKey)
    }

    /// Reminder times as minutes since local midnight, at most three.
    public static func reminderTimes(defaults: UserDefaults? = nil) -> [Int] {
        guard let data = (defaults ?? sharedDefaults)?.data(forKey: reminderTimesKey),
              let times = try? JSONDecoder().decode([Int].self, from: data)
        else { return [] }
        return times
    }

    public static func setReminderTimes(_ minutes: [Int], defaults: UserDefaults? = nil) {
        guard let data = try? JSONEncoder().encode(minutes) else { return }
        (defaults ?? sharedDefaults)?.set(data, forKey: reminderTimesKey)
    }

    // MARK: - Protein reminder

    public static func proteinReminderEnabled(defaults: UserDefaults? = nil) -> Bool {
        (defaults ?? sharedDefaults)?.bool(forKey: proteinReminderEnabledKey) ?? false
    }

    public static func setProteinReminderEnabled(_ enabled: Bool, defaults: UserDefaults? = nil) {
        (defaults ?? sharedDefaults)?.set(enabled, forKey: proteinReminderEnabledKey)
    }

    /// Fire time as minutes since local midnight.
    public static func proteinReminderTime(defaults: UserDefaults? = nil) -> Int {
        let store = defaults ?? sharedDefaults
        guard let value = store?.object(forKey: proteinReminderTimeKey) as? Int,
              (0..<24 * 60).contains(value) else { return defaultProteinReminderTime }
        return value
    }

    public static func setProteinReminderTime(_ minutes: Int, defaults: UserDefaults? = nil) {
        (defaults ?? sharedDefaults)?.set(minutes, forKey: proteinReminderTimeKey)
    }
}
