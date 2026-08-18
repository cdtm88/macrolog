import Foundation
import SwiftData

#if targetEnvironment(simulator)
/// Simulator-only sample data so dev builds show realistic days instead of
/// whatever was last typed in by hand. Never compiled into device builds.
///
/// Seeding is versioned: bump `version` after editing the sample set and the
/// next launch wipes all entries and reseeds. Entries are marked `.written`
/// although nothing was sent to Health — editing or deleting one runs the
/// delete-by-tag reconciliation, which completes cleanly when no sample
/// exists (ENT-05), so the lifecycle paths stay exercisable.
enum SimulatorSeed {
    static let version = 1
    private static let defaultsKey = "simulatorSeedVersion"

    @MainActor
    static func seedIfNeeded(context: ModelContext) {
        // The unit-test host also launches the app in the simulator; don't
        // touch its store mid-suite.
        guard ProcessInfo.processInfo.environment["XCTestSessionIdentifier"] == nil else { return }
        let defaults = UserDefaults.standard
        guard defaults.integer(forKey: defaultsKey) < version else { return }
        do {
            try context.delete(model: FoodEntry.self)
            for entry in sampleEntries() { context.insert(entry) }
            try context.save()
            defaults.set(version, forKey: defaultsKey)
        } catch {
            // A dev convenience must never block launch; worst case the old
            // data stays and seeding retries next launch.
        }
    }

    /// Four days against the default targets (160g protein floor, 2,500 kcal
    /// ceiling), covering every header state:
    /// - today: two meals, mid-day in progress
    /// - yesterday: passes both (2,070 kcal, 161g)
    /// - 2 days ago: over the kcal ceiling, protein met (2,980 kcal, 160g)
    /// - 3 days ago: light day — kcal pass, protein miss (1,450 kcal, 43g)
    private static func sampleEntries() -> [FoodEntry] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        func at(_ daysAgo: Int, _ hour: Int, _ minute: Int) -> Date {
            calendar.date(byAdding: DateComponents(day: -daysAgo, hour: hour, minute: minute),
                          to: today)!
        }
        func entry(_ name: String, _ capturedAt: Date,
                   kcal: Double, protein: Double, carbs: Double, fat: Double,
                   fiber: Double, sodium: Double) -> FoodEntry {
            FoodEntry(name: name,
                      macros: Macros(kcal: kcal, protein: protein, carbs: carbs,
                                     fat: fat, fiber: fiber, sodium: sodium),
                      capturedAt: capturedAt,
                      status: .written)
        }
        return [
            // Today — in progress.
            entry("Greek yoghurt, granola & blueberries", at(0, 7, 50),
                  kcal: 420, protein: 28, carbs: 52, fat: 12, fiber: 6, sodium: 140),
            entry("Chicken burrito bowl", at(0, 12, 40),
                  kcal: 680, protein: 45, carbs: 72, fat: 21, fiber: 10, sodium: 980),

            // Yesterday — both targets pass.
            entry("Porridge with banana & peanut butter", at(1, 7, 30),
                  kcal: 520, protein: 18, carbs: 74, fat: 17, fiber: 8, sodium: 220),
            entry("Tuna salad wholegrain sandwich", at(1, 12, 15),
                  kcal: 460, protein: 35, carbs: 46, fat: 15, fiber: 6, sodium: 720),
            entry("Protein shake", at(1, 16, 30),
                  kcal: 210, protein: 42, carbs: 9, fat: 3, fiber: 1, sodium: 160),
            entry("Salmon, new potatoes & greens", at(1, 19, 20),
                  kcal: 700, protein: 48, carbs: 52, fat: 30, fiber: 7, sodium: 480),
            entry("Skyr with honey", at(1, 21, 0),
                  kcal: 180, protein: 18, carbs: 24, fat: 2, fiber: 0, sodium: 65),

            // Two days ago — kcal ceiling blown, protein met.
            entry("Bacon & egg roll, flat white", at(2, 8, 10),
                  kcal: 650, protein: 30, carbs: 48, fat: 36, fiber: 3, sodium: 1250),
            entry("Chicken katsu curry with rice", at(2, 13, 0),
                  kcal: 850, protein: 40, carbs: 96, fat: 34, fiber: 6, sodium: 1350),
            entry("Beer & salted peanuts", at(2, 17, 45),
                  kcal: 380, protein: 10, carbs: 18, fat: 25, fiber: 3, sodium: 420),
            entry("Margherita pizza", at(2, 20, 15),
                  kcal: 890, protein: 38, carbs: 98, fat: 38, fiber: 6, sodium: 1750),
            entry("Protein shake", at(2, 22, 0),
                  kcal: 210, protein: 42, carbs: 9, fat: 3, fiber: 1, sodium: 160),

            // Three days ago — light day: kcal pass, protein miss.
            entry("Avocado toast & coffee", at(3, 8, 0),
                  kcal: 430, protein: 12, carbs: 42, fat: 24, fiber: 7, sodium: 540),
            entry("Butternut squash soup & roll", at(3, 13, 30),
                  kcal: 380, protein: 9, carbs: 58, fat: 11, fiber: 8, sodium: 890),
            entry("Veggie pasta with parmesan", at(3, 19, 0),
                  kcal: 640, protein: 22, carbs: 88, fat: 20, fiber: 9, sodium: 610),
        ]
    }
}
#endif
