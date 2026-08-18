import Testing
import Foundation
@testable import MacroLog

/// Settings must always resolve to usable defaults — the widget reads the
/// protein target cold, before the app has ever written anything.
struct SettingsStoreTests {

    /// A scratch suite so tests never touch the real App Group.
    private func makeDefaults() -> (UserDefaults, cleanup: () -> Void) {
        let name = "settings-tests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        return (defaults, { defaults.removePersistentDomain(forName: name) })
    }

    @Test func unsetSuiteReturnsDefaults() {
        let (defaults, cleanup) = makeDefaults()
        defer { cleanup() }
        #expect(SettingsStore.proteinTarget(defaults: defaults) == 160)
        #expect(SettingsStore.kcalTarget(defaults: defaults) == 2500)
        #expect(SettingsStore.fiberTarget(defaults: defaults) == 30)
        #expect(SettingsStore.remindersEnabled(defaults: defaults) == false)
        #expect(SettingsStore.reminderTimes(defaults: defaults) == [])
        #expect(SettingsStore.proteinReminderEnabled(defaults: defaults) == false)
        #expect(SettingsStore.proteinReminderTime(defaults: defaults) == 20 * 60)
        #expect(SettingsStore.exportFull(defaults: defaults) == false)
    }

    @Test func valuesRoundTrip() {
        let (defaults, cleanup) = makeDefaults()
        defer { cleanup() }
        SettingsStore.setProteinTarget(185, defaults: defaults)
        SettingsStore.setKcalTarget(2750, defaults: defaults)
        SettingsStore.setFiberTarget(40, defaults: defaults)
        SettingsStore.setExportFull(true, defaults: defaults)
        SettingsStore.setRemindersEnabled(true, defaults: defaults)
        SettingsStore.setReminderTimes([12 * 60 + 30, 19 * 60], defaults: defaults)
        SettingsStore.setProteinReminderEnabled(true, defaults: defaults)
        SettingsStore.setProteinReminderTime(21 * 60 + 15, defaults: defaults)
        #expect(SettingsStore.proteinTarget(defaults: defaults) == 185)
        #expect(SettingsStore.kcalTarget(defaults: defaults) == 2750)
        #expect(SettingsStore.fiberTarget(defaults: defaults) == 40)
        #expect(SettingsStore.exportFull(defaults: defaults) == true)
        #expect(SettingsStore.remindersEnabled(defaults: defaults) == true)
        #expect(SettingsStore.reminderTimes(defaults: defaults) == [750, 1140])
        #expect(SettingsStore.proteinReminderEnabled(defaults: defaults) == true)
        #expect(SettingsStore.proteinReminderTime(defaults: defaults) == 1275)
    }

    @Test func garbledValuesFallBackToDefaults() {
        let (defaults, cleanup) = makeDefaults()
        defer { cleanup() }
        defaults.set("not a number", forKey: "protein_target_g")
        defaults.set("not a number", forKey: "kcal_target")
        defaults.set(Data("not json".utf8), forKey: "reminder_times_v1")
        defaults.set("not a number", forKey: "protein_reminder_time")
        #expect(SettingsStore.proteinTarget(defaults: defaults) == 160)
        #expect(SettingsStore.kcalTarget(defaults: defaults) == 2500)
        #expect(SettingsStore.reminderTimes(defaults: defaults) == [])
        #expect(SettingsStore.proteinReminderTime(defaults: defaults) == 20 * 60)
    }

    @Test func nonPositiveTargetFallsBackToDefault() {
        let (defaults, cleanup) = makeDefaults()
        defer { cleanup() }
        SettingsStore.setProteinTarget(0, defaults: defaults)
        SettingsStore.setKcalTarget(0, defaults: defaults)
        SettingsStore.setFiberTarget(0, defaults: defaults)
        #expect(SettingsStore.proteinTarget(defaults: defaults) == 160)
        #expect(SettingsStore.kcalTarget(defaults: defaults) == 2500)
        #expect(SettingsStore.fiberTarget(defaults: defaults) == 30)
    }

    @Test func outOfRangeProteinReminderTimeFallsBackToDefault() {
        let (defaults, cleanup) = makeDefaults()
        defer { cleanup() }
        SettingsStore.setProteinReminderTime(-1, defaults: defaults)
        #expect(SettingsStore.proteinReminderTime(defaults: defaults) == 20 * 60)
        SettingsStore.setProteinReminderTime(24 * 60, defaults: defaults)
        #expect(SettingsStore.proteinReminderTime(defaults: defaults) == 20 * 60)
    }
}
