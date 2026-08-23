import Foundation

/// AI-estimate vs confirmed bias across the instrumented meals — the in-app
/// readout of the data the Full export's `est_*` columns carry, and the
/// evidence base for the D-04 Opus escalation decision. Pure, so the numbers
/// are pinned by unit tests.
///
/// Each figure is the signed aggregate error as a fraction of the confirmed
/// total: (Σ estimated − Σ confirmed) / Σ confirmed. Positive means the AI
/// over-estimates. Nil when that macro's confirmed total is zero.
struct EstimationBias: Equatable {
    let mealCount: Int
    let kcal: Double?
    let protein: Double?
    let carbs: Double?
    let fat: Double?
    let fiber: Double?
    let sodium: Double?

    /// Computes the bias over the meals that carry a frozen estimate —
    /// favourites and pre-instrumentation entries (nil `estimated`) are
    /// excluded. Nil when no instrumented meal exists yet.
    static func compute(items: [MealExportItem]) -> EstimationBias? {
        let pairs = items.compactMap { item in
            item.estimated.map { (estimated: $0, confirmed: item.macros) }
        }
        guard !pairs.isEmpty else { return nil }

        let estimated = pairs.reduce(Macros.zero) { $0 + $1.estimated }
        let confirmed = pairs.reduce(Macros.zero) { $0 + $1.confirmed }

        func bias(_ keyPath: KeyPath<Macros, Double>) -> Double? {
            let base = confirmed[keyPath: keyPath]
            guard base > 0 else { return nil }
            return (estimated[keyPath: keyPath] - base) / base
        }

        return EstimationBias(mealCount: pairs.count,
                              kcal: bias(\.kcal),
                              protein: bias(\.protein),
                              carbs: bias(\.carbs),
                              fat: bias(\.fat),
                              fiber: bias(\.fiber),
                              sodium: bias(\.sodium))
    }
}
