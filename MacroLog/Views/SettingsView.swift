import SwiftUI
import UserNotifications

/// Minimal preferences sheet: the daily targets, meal reminders, the protein
/// check, and the daily-totals export. Values write through to `SettingsStore`
/// as they change; the single reminder re-arm and widget refresh happen when
/// the sheet dismisses (`settingsSheetDismissed`), so scrubbing a time picker
/// doesn't thrash the scheduler.
struct SettingsView: View {
    @Bindable var model: CaptureViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var proteinTarget = SettingsStore.proteinTarget()
    @State private var kcalTarget = SettingsStore.kcalTarget()
    @State private var remindersEnabled = SettingsStore.remindersEnabled()
    @State private var reminderTimes = SettingsStore.reminderTimes()
    @State private var proteinReminderEnabled = SettingsStore.proteinReminderEnabled()
    @State private var proteinReminderTime = SettingsStore.proteinReminderTime()
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var isTogglingReminders = false
    @State private var isTogglingProteinReminder = false
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            List {
                targetSection
                remindersSection
                proteinReminderSection
                dataSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                authorizationStatus = await model.reminderAuthorizationStatus()
                // Eagerly built: the store is tiny and nothing can add entries
                // while this modal is up.
                exportURL = model.dailyTotalsExportURL()
            }
        }
    }

    // MARK: - Daily targets

    private var targetSection: some View {
        Section {
            Stepper(value: $proteinTarget, in: 50...400, step: 5) {
                HStack {
                    Text("Protein")
                        .font(.system(.body))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Text("\(Int(proteinTarget)) g")
                        .font(.system(.body, weight: .bold))
                        .foregroundStyle(Theme.protein)
                        .monospacedDigit()
                }
            }
            .onChange(of: proteinTarget) { _, value in
                SettingsStore.setProteinTarget(value)
            }
            Stepper(value: $kcalTarget, in: 1200...5000, step: 50) {
                HStack {
                    Text("Calories")
                        .font(.system(.body))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Text("\(Int(kcalTarget)) kcal")
                        .font(.system(.body, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .monospacedDigit()
                }
            }
            .onChange(of: kcalTarget) { _, value in
                SettingsStore.setKcalTarget(value)
            }
        } header: {
            Text("Daily targets")
        } footer: {
            Text("Shown on the Today screen and widget. The protein target also drives reminders.")
        }
    }

    // MARK: - Meal reminders

    private var remindersSection: some View {
        Section {
            Toggle("Remind me to log", isOn: $remindersEnabled)
                .disabled(isTogglingReminders)
                .onChange(of: remindersEnabled) { _, enabled in
                    isTogglingReminders = true
                    Task {
                        if enabled {
                            let authorized = await model.enableReminders()
                            authorizationStatus = authorized
                                ? .authorized
                                : await model.reminderAuthorizationStatus()
                            reminderTimes = SettingsStore.reminderTimes()
                        } else {
                            model.disableReminders()
                        }
                        isTogglingReminders = false
                    }
                }

            if remindersEnabled {
                if authorizationStatus == .denied {
                    deniedRow
                }
                ForEach(reminderTimes.indices, id: \.self) { index in
                    DatePicker("Reminder \(index + 1)",
                               selection: timeBinding(at: index),
                               displayedComponents: .hourAndMinute)
                }
                .onDelete { offsets in
                    reminderTimes.remove(atOffsets: offsets)
                    SettingsStore.setReminderTimes(reminderTimes)
                }
                if reminderTimes.count < ReminderPlanner.maxTimes {
                    Button {
                        addTime()
                    } label: {
                        Label("Add reminder", systemImage: "plus.circle.fill")
                            .font(.system(.body, weight: .medium))
                    }
                }
            }
        } header: {
            Text("Meal reminders")
        } footer: {
            Text("A reminder is skipped when you've logged a meal in the 2 hours before it. The last reminder of the day shows how much protein you're short.")
        }
    }

    // MARK: - Protein check

    private var proteinReminderSection: some View {
        Section {
            Toggle("Daily protein check", isOn: $proteinReminderEnabled)
                .disabled(isTogglingProteinReminder)
                .onChange(of: proteinReminderEnabled) { _, enabled in
                    isTogglingProteinReminder = true
                    Task {
                        if enabled {
                            let authorized = await model.enableProteinReminder()
                            authorizationStatus = authorized
                                ? .authorized
                                : await model.reminderAuthorizationStatus()
                        } else {
                            model.disableProteinReminder()
                        }
                        isTogglingProteinReminder = false
                    }
                }

            if proteinReminderEnabled {
                if authorizationStatus == .denied {
                    deniedRow
                }
                DatePicker("Time",
                           selection: proteinTimeBinding,
                           displayedComponents: .hourAndMinute)
            }
        } footer: {
            Text("Fires at this time if you're still short of your protein target — even if you've logged recently. Skipped once the target is met.")
        }
    }

    private var proteinTimeBinding: Binding<Date> {
        Binding {
            date(fromMinutes: proteinReminderTime)
        } set: { newValue in
            proteinReminderTime = minutes(from: newValue)
            SettingsStore.setProteinReminderTime(proteinReminderTime)
        }
    }

    // MARK: - Data

    private var dataSection: some View {
        Section {
            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("Export daily totals", systemImage: "square.and.arrow.up")
                        .font(.system(.body, weight: .medium))
                }
            }
        } header: {
            Text("Data")
        } footer: {
            Text("A CSV of every logged day's totals.")
        }
    }

    /// Mirrors the Health denied banner: an explicit state with a route to
    /// iOS Settings, never a silent no-op while the toggle claims otherwise.
    private var deniedRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "bell.slash.fill")
                .foregroundStyle(.orange)
            Text("Notifications are off for MacroLog.")
                .font(.system(.footnote))
                .foregroundStyle(Theme.secondary)
            Spacer()
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.system(.footnote, weight: .semibold))
        }
    }

    // MARK: - Time helpers (minutes-since-midnight ↔ Date for DatePicker)

    private func timeBinding(at index: Int) -> Binding<Date> {
        Binding {
            date(fromMinutes: reminderTimes.indices.contains(index) ? reminderTimes[index] : 0)
        } set: { newValue in
            guard reminderTimes.indices.contains(index) else { return }
            reminderTimes[index] = minutes(from: newValue)
            SettingsStore.setReminderTimes(reminderTimes)
        }
    }

    private func date(fromMinutes minutes: Int) -> Date {
        let dayStart = Calendar.current.startOfDay(for: .now)
        return Calendar.current.date(byAdding: .minute, value: minutes, to: dayStart) ?? .now
    }

    private func minutes(from date: Date) -> Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }

    private func addTime() {
        // New slot lands 90 minutes after the latest, capped at 21:00.
        let next = min((reminderTimes.max() ?? 11 * 60) + 90, 21 * 60)
        reminderTimes.append(next)
        SettingsStore.setReminderTimes(reminderTimes)
    }
}
