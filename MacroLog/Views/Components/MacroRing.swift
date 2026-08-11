import SwiftUI

/// The tricolour macro ring from the prototype: three arcs sized by each
/// macro's calorie contribution (protein & carbs ×4 kcal/g, fat ×9), with an
/// optional centred calorie readout.
struct MacroRing: View {
    let macros: Macros
    var size: CGFloat
    var lineWidth: CGFloat
    var showCenter: Bool = false

    private var segments: [(value: Double, color: Color)] {
        [(macros.protein * 4, Theme.protein),
         (macros.carbs * 4, Theme.carbs),
         (macros.fat * 9, Theme.fat)]
    }

    private var total: Double {
        max(segments.reduce(0) { $0 + $1.value }, 1)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.ringTrack, lineWidth: lineWidth)

            ForEach(Array(arcs().enumerated()), id: \.offset) { _, arc in
                Circle()
                    .trim(from: arc.start, to: arc.end)
                    .stroke(arc.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }

            if showCenter {
                VStack(spacing: 0) {
                    Text("\(Int(macros.kcal.rounded()))")
                        .font(.system(size: size * 0.23, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(maxWidth: size * 0.72)
                    Text("KCAL")
                        .font(.system(size: size * 0.085, weight: .bold))
                        .tracking(1)
                        .foregroundStyle(Theme.secondary)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private struct Arc { let start: CGFloat; let end: CGFloat; let color: Color }

    private func arcs() -> [Arc] {
        let gap = 0.008 // small visual separation between arcs
        var cursor: CGFloat = 0
        var result: [Arc] = []
        for segment in segments {
            let fraction = CGFloat(segment.value / total)
            let start = cursor
            let end = max(start, cursor + fraction - gap)
            result.append(Arc(start: start, end: end, color: segment.color))
            cursor += fraction
        }
        return result
    }

    private var accessibilityText: String {
        "\(Int(macros.kcal.rounded())) calories. "
        + "Protein \(Int(macros.protein.rounded())) grams, "
        + "carbohydrate \(Int(macros.carbs.rounded())) grams, "
        + "fat \(Int(macros.fat.rounded())) grams."
    }
}
