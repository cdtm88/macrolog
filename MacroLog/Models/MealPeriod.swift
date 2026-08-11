import Foundation

/// Loose time-of-day buckets the day list groups meals under — purely visual,
/// nothing else keys off them. Boundaries are deliberately coarse: before
/// 11:00 is Morning, 11:00–16:59 is Lunch, 17:00 onward is Evening, all in
/// the entry's local capture time.
enum MealPeriod: CaseIterable {
    case morning, lunch, evening

    /// Section order on the day list — newest period first, matching the
    /// list's reverse-chronological sort.
    static let displayOrder: [MealPeriod] = [.evening, .lunch, .morning]

    var title: String {
        switch self {
        case .morning: "Morning"
        case .lunch: "Lunch"
        case .evening: "Evening"
        }
    }

    static func period(for date: Date, calendar: Calendar = .current) -> MealPeriod {
        let hour = calendar.component(.hour, from: date)
        if hour < 11 { return .morning }
        if hour < 17 { return .lunch }
        return .evening
    }
}
