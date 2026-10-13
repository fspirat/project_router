import SwiftUI
import RouterCore

// Chart helpers shared by «Сводка» and «VPN» (no Swift Charts here).

/// Legend under the chart: line = VPN check ok, red = failed, grey = router offline.
struct ChartLegend: View {
    var body: some View {
        HStack(spacing: 12) {
            LegendItem(color: Theme.acc, text: "задержка")
            LegendItem(color: Theme.err, text: "VPN не прошёл")
            LegendItem(color: Theme.faint, text: "нет связи")
            Spacer(minLength: 0)
        }
        .font(.caption2)
        .foregroundStyle(Theme.dim)
        .accessibilityHidden(true)
    }
}

struct LegendItem: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 10, height: 4)
            Text(text)
        }
    }
}

/// «Средняя / Лучшая / Худшая / Сбоев / Без связи».
struct StatsGrid: View {
    let facts: [Fact]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                VStack(alignment: .leading, spacing: 2) {
                    Text(fact.label)
                        .font(.caption)
                        .foregroundStyle(Theme.dim)
                    Text(fact.value)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.text)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
    }
}
