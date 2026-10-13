import SwiftUI
import Charts
import RouterCore

/// «Связь за сутки» (contract §4.9): `/data` points (fallback: `status.history`) and the day stats.
struct HistoryChartCard: View {
    @Environment(RouterStore.self) var store
    let now: TimeInterval

    var body: some View {
        let points: [DataPoint] = store.dayData?.points ?? (store.status?.history ?? [])
        let chart = Summary.chart(points: points, now: now)
        Card {
            CardTitle("Связь за сутки", symbol: "waveform.path.ecg")
            if chart.isEmpty {
                Text(Summary.emptyChart)
                    .font(.subheadline)
                    .foregroundStyle(Theme.dim)
            } else {
                MiniChartView(chart: chart)
                    .frame(height: 150)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("График задержки VPN за сутки")
                    .accessibilityValue(HistoryChartCard.accessibilitySummary(chart))
                ChartLegend()
            }
            if let stats = store.dayData?.stats {
                StatsGrid(facts: Summary.statsFacts(stats))
            }
        }
    }

    static func accessibilitySummary(_ chart: MiniChart) -> String {
        var parts: [String] = []
        let failures = chart.failMarks.count
        let offline = chart.offlineBands.count
        parts.append(failures == 0 ? "без сбоев VPN" : "сбоев VPN: \(failures)")
        if offline > 0 {
            parts.append("роутер был не на связи")
        }
        return parts.joined(separator: ", ")
    }
}

/// The chart itself (Swift Charts). x: last 24 h; y: 0…max(150, max ms)·1.15.
struct MiniChartView: View {
    let chart: MiniChart

    struct LinePoint: Identifiable {
        let id: Int
        let series: String
        let date: Date
        let ms: Double
    }

    var body: some View {
        let points = MiniChartView.linePoints(chart)
        let singles = MiniChartView.singlePoints(chart)
        let top = chart.yMax
        let fromDate = MiniChartView.date(chart.from)
        let toDate = MiniChartView.date(max(chart.to, chart.from + 1))
        let ticks = MiniChartView.axisDates(from: chart.from, to: chart.to)
        Chart {
            ForEach(chart.offlineBands, id: \.self) { ts in
                RectangleMark(
                    xStart: .value("Начало", MiniChartView.date(ts - MiniChart.bandWidth / 2)),
                    xEnd: .value("Конец", MiniChartView.date(ts + MiniChart.bandWidth / 2)),
                    yStart: .value("мс", 0.0),
                    yEnd: .value("мс", top)
                )
                .foregroundStyle(Theme.offline)
            }
            ForEach(points) { point in
                AreaMark(
                    x: .value("Время", point.date),
                    yStart: .value("мс", 0.0),
                    yEnd: .value("мс", point.ms),
                    series: .value("Отрезок", point.series)
                )
                .foregroundStyle(Theme.area)
                LineMark(
                    x: .value("Время", point.date),
                    y: .value("мс", point.ms),
                    series: .value("Отрезок", point.series)
                )
                .foregroundStyle(Theme.acc)
                .lineStyle(StrokeStyle(lineWidth: 1.75))
            }
            ForEach(singles) { point in
                PointMark(
                    x: .value("Время", point.date),
                    y: .value("мс", point.ms)
                )
                .foregroundStyle(Theme.acc)
                .symbolSize(16)
            }
            ForEach(chart.failMarks, id: \.self) { ts in
                RuleMark(
                    x: .value("Время", MiniChartView.date(ts)),
                    yStart: .value("мс", 0.0),
                    yEnd: .value("мс", top * 0.14)
                )
                .foregroundStyle(Theme.err)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
        }
        .chartXScale(domain: fromDate...toDate)
        .chartYScale(domain: 0.0...top)
        .chartLegend(.hidden)
        .chartXAxis {
            AxisMarks(values: ticks) { value in
                AxisGridLine()
                    .foregroundStyle(Theme.chartGrid)
                AxisValueLabel {
                    Text(MiniChartView.timeLabel(value.as(Date.self)))
                        .font(.caption2)
                        .foregroundStyle(Theme.dim)
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine()
                    .foregroundStyle(Theme.chartGrid)
                AxisValueLabel()
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.dim)
            }
        }
        // The automatic Y labels follow the environment locale: decimal comma whatever the phone's region.
        .environment(\.locale, Locale(identifier: "ru_RU"))
    }

    static func date(_ ts: Int) -> Date {
        return Date(timeIntervalSince1970: TimeInterval(ts))
    }

    /// Points of segments with 2+ samples (drawn as line + area), one series per segment so gaps stay gaps.
    static func linePoints(_ chart: MiniChart) -> [LinePoint] {
        var out: [LinePoint] = []
        for (index, segment) in chart.segments.enumerated() where segment.count > 1 {
            for sample in segment {
                out.append(LinePoint(id: out.count, series: "s\(index)", date: date(sample.ts), ms: Double(sample.ms)))
            }
        }
        return out
    }

    /// One-sample segments are drawn as dots.
    static func singlePoints(_ chart: MiniChart) -> [LinePoint] {
        var out: [LinePoint] = []
        for (index, segment) in chart.segments.enumerated() where segment.count == 1 {
            if let sample = segment.first {
                out.append(LinePoint(id: out.count, series: "p\(index)", date: date(sample.ts), ms: Double(sample.ms)))
            }
        }
        return out
    }

    /// Every 6 hours on the Samara clock (UTC+4) inside the window.
    static func axisDates(from: Int, to: Int) -> [Date] {
        let step = 6 * 3600
        let offset = 4 * 3600
        var first = ((from + offset) / step) * step - offset
        if first < from {
            first += step
        }
        var out: [Date] = []
        var t = first
        while t <= to && out.count < 8 {
            out.append(date(t))
            t += step
        }
        return out
    }

    static func timeLabel(_ value: Date?) -> String {
        guard let d = value else {
            return ""
        }
        return Fmt.hourMinute(Int(d.timeIntervalSince1970))
    }
}
