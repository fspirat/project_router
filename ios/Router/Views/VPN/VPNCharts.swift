import SwiftUI
import Charts
import RouterCore

// Swift Charts for the VPN tab: connection history (§5.1.6) and router speed history (§5.1.8).
// Charts sit inside material cards (no glass inside charts). Touch shows a tooltip line above the chart
// (`chartXSelection`, iOS 17) — reading only, never an action.

/// Axis ticks and labels on the Samara clock.
enum VPNChartAxis {
    static let samara: TimeZone = TimeZone(identifier: "Europe/Samara") ?? TimeZone(secondsFromGMT: 4 * 3600) ?? TimeZone.current

    static let dayMonthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.timeZone = samara
        f.dateFormat = "d.MM"
        return f
    }()

    static func date(_ ts: Int) -> Date {
        return Date(timeIntervalSince1970: TimeInterval(ts))
    }

    /// Tick step: 6 h (day), 1 day (week), 5 days (month or longer spans).
    static func tickStep(span: Int) -> Int {
        if span <= 2 * 86400 {
            return 6 * 3600
        }
        if span <= 8 * 86400 {
            return 86400
        }
        return 5 * 86400
    }

    /// Ticks aligned to the Samara clock inside `[from, to]` (at most 8).
    static func ticks(from: Int, to: Int) -> [Date] {
        let step = tickStep(span: max(1, to - from))
        let offset = samara.secondsFromGMT(for: date(to))
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

    /// «14:00» for spans up to 2 days, else «13.10».
    static func label(_ value: Date?, span: Int) -> String {
        guard let d = value else {
            return ""
        }
        if span <= 2 * 86400 {
            return Fmt.hourMinute(Int(d.timeIntervalSince1970))
        }
        return dayMonthFormatter.string(from: d)
    }
}

/// A plotted sample.
struct VPNChartPoint: Identifiable {
    let id: Int
    let series: String
    let date: Date
    let value: Double
}

/// A marker with a stable id (bands, fail bars, the selection rule).
struct VPNChartMarker: Identifiable {
    let id: Int
    let from: Date
    let to: Date
    let height: Double
}

// MARK: - Connection history

struct VPNHistoryChartView: View {
    let chart: HistoryChart
    let now: TimeInterval
    @State private var selection: Date? = nil

    var body: some View {
        let tip = selection.flatMap { chart.tooltip(at: $0.timeIntervalSince1970, now: now) }
        VStack(alignment: .leading, spacing: 6) {
            VPNTooltipLine(time: tip?.time, value: tip?.value, tone: tip?.tone ?? .neutral)
            VPNHistoryPlot(chart: chart, selectedTS: tip?.ts, selection: $selection)
                .frame(height: 180)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("График: " + chart.title)
                .accessibilityValue(VPNHistoryPlot.summary(chart))
        }
    }
}

struct VPNHistoryPlot: View {
    let chart: HistoryChart
    let selectedTS: Int?
    @Binding var selection: Date?

    var body: some View {
        let top = chart.yMax
        let lines = VPNHistoryPlot.linePoints(chart)
        let areas = chart.series == .connection ? lines : []
        let dots = VPNHistoryPlot.singlePoints(chart)
        let bands = VPNHistoryPlot.bands(chart, top: top)
        let fails = VPNHistoryPlot.fails(chart, top: top)
        let rules = VPNHistoryPlot.selection(selectedTS, top: top)
        let span = max(1, chart.to - chart.from)
        let ticks = VPNChartAxis.ticks(from: chart.from, to: chart.to)
        let fromDate = VPNChartAxis.date(chart.from)
        let toDate = VPNChartAxis.date(max(chart.to, chart.from + 1))
        Chart {
            ForEach(bands) { band in
                RectangleMark(
                    xStart: .value("Начало", band.from),
                    xEnd: .value("Конец", band.to),
                    yStart: .value("мс", 0.0),
                    yEnd: .value("мс", band.height)
                )
                .foregroundStyle(Theme.offline)
            }
            ForEach(areas) { point in
                AreaMark(
                    x: .value("Время", point.date),
                    yStart: .value("мс", 0.0),
                    yEnd: .value("мс", point.value),
                    series: .value("Отрезок", point.series)
                )
                .foregroundStyle(Theme.area)
            }
            ForEach(lines) { point in
                LineMark(
                    x: .value("Время", point.date),
                    y: .value("мс", point.value),
                    series: .value("Отрезок", point.series)
                )
                .foregroundStyle(Theme.acc)
                .lineStyle(StrokeStyle(lineWidth: 1.75))
            }
            ForEach(dots) { point in
                PointMark(
                    x: .value("Время", point.date),
                    y: .value("мс", point.value)
                )
                .foregroundStyle(Theme.acc)
                .symbolSize(16)
            }
            ForEach(fails) { mark in
                RuleMark(
                    x: .value("Время", mark.from),
                    yStart: .value("мс", 0.0),
                    yEnd: .value("мс", mark.height)
                )
                .foregroundStyle(Theme.err)
                .lineStyle(StrokeStyle(lineWidth: 2))
            }
            ForEach(rules) { mark in
                RuleMark(x: .value("Время", mark.from))
                    .foregroundStyle(Theme.dim)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartXScale(domain: fromDate...toDate)
        .chartYScale(domain: 0.0...top)
        .chartLegend(.hidden)
        .chartXSelection(value: $selection)
        .chartXAxis {
            AxisMarks(values: ticks) { value in
                AxisGridLine()
                    .foregroundStyle(Theme.chartGrid)
                AxisValueLabel {
                    Text(VPNChartAxis.label(value.as(Date.self), span: span))
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
                    .foregroundStyle(Theme.dim)
            }
        }
    }

    /// Segments with 2+ samples: one series per segment so gaps stay gaps.
    static func linePoints(_ chart: HistoryChart) -> [VPNChartPoint] {
        var out: [VPNChartPoint] = []
        for (index, segment) in chart.segments.enumerated() where segment.count > 1 {
            for sample in segment {
                out.append(VPNChartPoint(id: out.count, series: "s\(index)", date: VPNChartAxis.date(sample.ts), value: Double(sample.ms)))
            }
        }
        return out
    }

    /// A single isolated ok sample is drawn as a dot.
    static func singlePoints(_ chart: HistoryChart) -> [VPNChartPoint] {
        var out: [VPNChartPoint] = []
        for (index, segment) in chart.segments.enumerated() where segment.count == 1 {
            if let sample = segment.first {
                out.append(VPNChartPoint(id: out.count, series: "p\(index)", date: VPNChartAxis.date(sample.ts), value: Double(sample.ms)))
            }
        }
        return out
    }

    static func bands(_ chart: HistoryChart, top: Double) -> [VPNChartMarker] {
        return chart.offlineBands.enumerated().map { index, band in
            VPNChartMarker(id: index, from: VPNChartAxis.date(band.from), to: VPNChartAxis.date(band.to), height: top)
        }
    }

    /// Fail bars at the bottom: tall for a failed point, short for an ok bucket with failures.
    static func fails(_ chart: HistoryChart, top: Double) -> [VPNChartMarker] {
        return chart.failMarks.enumerated().map { index, mark in
            let d = VPNChartAxis.date(mark.ts)
            return VPNChartMarker(id: index, from: d, to: d, height: top * (mark.isTall ? 0.14 : 0.07))
        }
    }

    static func selection(_ ts: Int?, top: Double) -> [VPNChartMarker] {
        guard let t = ts else {
            return []
        }
        let d = VPNChartAxis.date(t)
        return [VPNChartMarker(id: 0, from: d, to: d, height: top)]
    }

    /// VoiceOver summary: failures and offline periods in words, plus the scale.
    static func summary(_ chart: HistoryChart) -> String {
        var parts: [String] = []
        let failures = chart.points.filter { $0.ms == 0 }.count
        if chart.series == .connection {
            parts.append(failures == 0 ? "без сбоев VPN" : "отметок о сбоях VPN: \(failures)")
            if !chart.offlineBands.isEmpty {
                parts.append("роутер был не на связи")
            }
        } else {
            parts.append(failures == 0 ? "всегда отвечал" : "не отвечал: \(failures) раз")
        }
        parts.append(chart.caption)
        return parts.joined(separator: ", ")
    }
}

/// The value under the finger, or a hint. Fixed height so the chart does not jump.
struct VPNTooltipLine: View {
    let time: String?
    let value: String?
    let tone: Tone

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let value = value {
                if let time = time, !time.isEmpty {
                    Text(time)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.dim)
                }
                Text(value)
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.levelText(tone))
            } else {
                Text("Коснись графика, чтобы увидеть значение")
                    .font(.caption)
                    .foregroundStyle(Theme.faint)
            }
            Spacer(minLength: 0)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .frame(minHeight: 18)
        .accessibilityHidden(value == nil)
    }
}

// MARK: - Speed history

/// «История загрузки, Мбит/с»: one line + square points per channel (VPN = acc, напрямую = info).
struct VPNSpeedChartView: View {
    let chart: SpeedHistoryChart
    @State private var selection: Date? = nil

    var body: some View {
        let tip = selection.flatMap { VPNSpeedChartView.nearest(chart, to: $0) }
        VStack(alignment: .leading, spacing: 6) {
            VPNTooltipLine(time: nil, value: tip?.tooltip, tone: .info)
            VPNSpeedPlot(chart: chart, selectedTS: tip?.ts, selection: $selection)
                .frame(height: 170)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(VPNTexts.speedHistoryTitle)
                .accessibilityValue(chart.caption)
        }
    }

    /// The nearest test of any channel.
    static func nearest(_ chart: SpeedHistoryChart, to date: Date) -> SpeedPoint? {
        let t = date.timeIntervalSince1970
        var best: SpeedPoint? = nil
        var dist = Double.infinity
        for series in chart.series {
            for point in series.points {
                let d = abs(Double(point.ts) - t)
                if d < dist {
                    dist = d
                    best = point
                }
            }
        }
        return best
    }

    static func color(_ via: SpeedVia) -> Color {
        return via == .vpn ? Theme.acc : Theme.info
    }
}

struct VPNSpeedPlot: View {
    let chart: SpeedHistoryChart
    let selectedTS: Int?
    @Binding var selection: Date?

    struct Sample: Identifiable {
        let id: String
        let label: String
        let color: Color
        let date: Date
        let mbit: Double
    }

    var body: some View {
        let samples = VPNSpeedPlot.samples(chart)
        let top = max(chart.yMax / 1e6, 1)
        let span = max(1, chart.to - chart.from)
        let rules = VPNHistoryPlot.selection(selectedTS, top: top)
        let fromDate = VPNChartAxis.date(chart.from)
        let toDate = VPNChartAxis.date(max(chart.to, chart.from + 1))
        Chart {
            ForEach(samples) { sample in
                LineMark(
                    x: .value("Время", sample.date),
                    y: .value("Мбит/с", sample.mbit),
                    series: .value("Канал", sample.label)
                )
                .foregroundStyle(sample.color)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            ForEach(samples) { sample in
                PointMark(
                    x: .value("Время", sample.date),
                    y: .value("Мбит/с", sample.mbit)
                )
                .symbol(.square)
                .symbolSize(22)
                .foregroundStyle(sample.color)
            }
            ForEach(rules) { mark in
                RuleMark(x: .value("Время", mark.from))
                    .foregroundStyle(Theme.dim)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        }
        .chartXScale(domain: fromDate...toDate)
        .chartYScale(domain: 0.0...top)
        .chartLegend(.hidden)
        .chartXSelection(value: $selection)
        .chartXAxis {
            AxisMarks(values: VPNChartAxis.ticks(from: chart.from, to: chart.to)) { value in
                AxisGridLine()
                    .foregroundStyle(Theme.chartGrid)
                AxisValueLabel {
                    Text(VPNChartAxis.label(value.as(Date.self), span: span))
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
                    .foregroundStyle(Theme.dim)
            }
        }
    }

    static func samples(_ chart: SpeedHistoryChart) -> [Sample] {
        var out: [Sample] = []
        for series in chart.series {
            let color = VPNSpeedChartView.color(series.via)
            for (index, point) in series.points.enumerated() {
                out.append(Sample(
                    id: "\(series.via.rawValue)-\(index)",
                    label: series.label,
                    color: color,
                    date: VPNChartAxis.date(point.ts),
                    mbit: Double(point.value) / 1e6
                ))
            }
        }
        return out
    }
}
