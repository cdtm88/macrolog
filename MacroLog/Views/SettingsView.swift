import SwiftUI
import UserNotifications

/// Minimal preferences sheet: the daily targets, notifications, and the CSV
/// export. Values write through to `SettingsStore` as they change; the single
/// reminder re-arm and widget refresh happen when the sheet dismisses
/// (`settingsSheetDismissed`), so scrubbing a time picker doesn't thrash the
/// scheduler.
struct SettingsView: View {
    @Bindable var model: CaptureViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var proteinTarget = SettingsStore.proteinTarget()
    @State private var fiberTarget = SettingsStore.fiberTarget()
    @State private var kcalTarget = SettingsStore.kcalTarget()
    @State private var remindersEnabled = SettingsStore.remindersEnabled()
    @State private var reminderTimes = SettingsStore.reminderTimes()
    @State private var proteinReminderEnabled = SettingsStore.proteinReminderEnabled()
    @State private var proteinReminderTime = SettingsStore.proteinReminderTime()
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @State private var isTogglingReminders = false
    @State private var isTogglingProteinReminder = false
    @State private var exportFull = SettingsStore.exportFull()
    @State private var exportURL: URL?
    @State private var bias: EstimationBias?

    var body: some View {
        NavigationStack {
            List {
                targetSection
                notificationsSection
                dataSection
                accuracySection
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
                exportURL = model.exportURL()
                bias = model.estimationBias()
            }
        }
    }

    // MARK: - Daily targets

    private var targetSection: some View {
        Section {
            targetStepper("Protein", value: $proteinTarget, in: 50...400, step: 5,
                          unit: "g", store: SettingsStore.setProteinTarget)
            targetStepper("Fibre", value: $fiberTarget, in: 10...100, step: 5,
                          unit: "g", store: SettingsStore.setFiberTarget)
            targetStepper("Calories", value: $kcalTarget, in: 1200...5000, step: 50,
                          unit: "kcal", store: SettingsStore.setKcalTarget)
        } header: {
            Text("Daily targets")
        } footer: {
            Text("Shown on the Today screen and widget. The protein target also drives reminders.")
        }
    }

    private func targetStepper(_ label: String, value: Binding<Double>,
                               in range: ClosedRange<Double>, step: Double,
                               unit: String,
                               store: @escaping (Double, UserDefaults?) -> Void) -> some View {
        Stepper(value: value, in: range, step: step) {
            HStack {
                Text(label)
                    .font(.system(.body))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("\(Int(value.wrappedValue)) \(unit)")
                    .font(.system(.body, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .monospacedDigit()
            }
        }
        .onChange(of: value.wrappedValue) { _, newValue in
            store(newValue, nil)
        }
    }

    // MARK: - Notifications

    /// Meal reminders and the daily protein check in one section — two
    /// toggles, one shared denied banner.
    private var notificationsSection: some View {
        Section {
            if (remindersEnabled || proteinReminderEnabled) && authorizationStatus == .denied {
                deniedRow
            }

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
                DatePicker("Protein check time",
                           selection: proteinTimeBinding,
                           displayedComponents: .hourAndMinute)
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("A meal reminder is skipped when you've logged in the 2 hours before it; the day's last one shows how much protein you're short. The protein check fires at its set time regardless of recent logging, and is skipped once the target is met.")
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
            Picker("Export detail", selection: $exportFull) {
                Text("Lite").tag(false)
                Text("Full").tag(true)
            }
            .onChange(of: exportFull) { _, full in
                SettingsStore.setExportFull(full)
                exportURL = model.exportURL()
            }
            if let exportURL {
                ShareLink(item: exportURL) {
                    Label(exportFull ? "Export meals" : "Export daily totals",
                          systemImage: "square.and.arrow.up")
                        .font(.system(.body, weight: .medium))
                }
            }
        } header: {
            Text("Data")
        } footer: {
            Text(exportFull
                 ? "A CSV of every logged meal — date, time, name, and macros."
                 : "A CSV of every logged day's totals.")
        }
    }

    // MARK: - Estimation accuracy

    /// How the AI's frozen original estimates compare with the confirmed
    /// values — the in-app view of the export's `est_*` columns (the D-04
    /// evidence for any Opus escalation). Read-only; measurement, not a goal.
    private var accuracySection: some View {
        Section {
            if let bias {
                biasRow("Calories", bias.kcal)
                biasRow("Protein", bias.protein)
                biasRow("Carbs", bias.carbs)
                biasRow("Fat", bias.fat)
            } else {
                Text("No AI-estimated meals yet.")
                    .font(.system(.footnote))
                    .foregroundStyle(Theme.secondary)
            }
        } header: {
            Text("Estimation accuracy")
        } footer: {
            if let bias {
                Text("AI estimates vs your confirmed values across \(bias.mealCount) meals. Positive means the AI over-estimates.")
            }
        }
    }

    private func biasRow(_ label: String, _ fraction: Double?) -> some View {
        HStack {
            Text(label)
                .font(.system(.body))
                .foregroundStyle(Theme.ink)
            Spacer()
            Text(fraction.map { String(format: "%+.0f%%", $0 * 100) } ?? "—")
                .font(.system(.body, weight: .bold))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
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
