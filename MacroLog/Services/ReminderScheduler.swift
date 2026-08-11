import Foundation
import UserNotifications

/// Thin executor for `ReminderPlanner`'s output: replaces the app's pending
/// notification requests with the given plan. Holds no decision logic and
/// never requests authorization on its own — the permission prompt fires only
/// from the settings toggle (`requestAuthorization`), so it can never stack
/// onto the HealthKit prompt at first launch (the HB-08 spirit: inert until
/// the user opts in).
actor ReminderScheduler {
    private let center = UNUserNotificationCenter.current()

    /// Replaces all pending MacroLog reminders with the plan. When
    /// notifications aren't authorized it clears any leftovers and returns —
    /// it never prompts.
    func sync(plan: [PlannedReminder]) async {
        let pending = await center.pendingNotificationRequests()
        let ours = pending.map(\.identifier).filter { id in
            ReminderPlanner.allIDPrefixes.contains(where: id.hasPrefix)
        }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        // The app is (or was just) frontmost, so any delivered banner has
        // served its purpose. Single-purpose app — every delivered
        // notification is ours to clear.
        center.removeAllDeliveredNotifications()

        for reminder in plan {
            let content = UNMutableNotificationContent()
            content.title = reminder.title
            content.body = reminder.body
            content.sound = .default
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: reminder.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: reminder.id,
                                                        content: content,
                                                        trigger: trigger))
        }
    }

    /// The one place the permission prompt may fire — called from the settings
    /// toggle, never from a lifecycle hook.
    func requestAuthorization() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }
}
