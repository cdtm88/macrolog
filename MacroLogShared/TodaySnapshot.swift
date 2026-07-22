import Foundation

/// A frozen copy of today's cumulative macros, written by the app into the App
/// Group and read by the widget.
///
/// The widget cannot open the app's SwiftData store across process boundaries
/// cheaply, so instead the app publishes this small snapshot whenever the day's
/// totals change and asks WidgetKit to reload. This satisfies WID-01/02/04:
/// the widget always has a value to show, updates within seconds of a confirmed
/// entry, and shows zeros before the first meal.
public struct TodaySnapshot: Codable, Equatable, Sendable {
    public var totals: Macros
    /// Start-of-day the totals belong to. The widget compares this against its
    /// own notion of "today" so a stale snapshot from yesterday renders zeros
    /// rather than carrying yesterday's numbers into a new day.
    public var dayStart: Date
    public var entryCount: Int

    public init(totals: Macros, dayStart: Date, entryCount: Int) {
        self.totals = totals
        self.dayStart = dayStart
        self.entryCount = entryCount
    }

    public static let empty = TodaySnapshot(totals: .zero,
                                            dayStart: Calendar.current.startOfDay(for: Date()),
                                            entryCount: 0)
}

/// Reads and writes the shared `TodaySnapshot`. Used by the app (writer) and the
/// widget (reader).
public enum TodaySnapshotStore {
    private static let key = "today_snapshot_v1"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: SharedConstants.appGroupID)
    }

    public static func write(_ snapshot: TodaySnapshot) {
        guard let defaults else { return }
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: key)
        }
    }

    /// Returns the snapshot if it belongs to the current local day, otherwise an
    /// empty snapshot for today. Keeps the widget correct across a midnight
    /// rollover even if the app has not run to refresh it.
    public static func read(now: Date = Date(),
                            calendar: Calendar = .current) -> TodaySnapshot {
        let todayStart = calendar.startOfDay(for: now)
        guard let defaults,
              let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(TodaySnapshot.self, from: data),
              calendar.isDate(snapshot.dayStart, inSameDayAs: todayStart)
        else {
            return TodaySnapshot(totals: .zero, dayStart: todayStart, entryCount: 0)
        }
        return snapshot
    }
}
