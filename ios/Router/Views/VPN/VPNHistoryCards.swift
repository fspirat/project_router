import SwiftUI
import RouterCore

// MARK: - Switch history (§5.1.5)

/// The latest 5 `auto`/`manual` events of the chart range (fallback: `status.log`), «Все в журнале».
struct VPNSwitchHistoryCard: View {
    @Environment(RouterStore.self) private var store
    let range: DataRange
    let now: TimeInterval

    var body: some View {
        let rows = VPN.switchHistory(data: store.data(range), status: store.status, now: now, limit: 5)
        Card {
            CardHeader("Смены сервера", symbol: "arrow.triangle.swap") {
                Text(range.title)
                    .font(.footnote)
                    .foregroundStyle(Theme.dim)
            }
            if rows.isEmpty {
                EmptyStateView(title: VPNTexts.noSwitches, systemImage: "checkmark.circle")
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(rows) { row in
                        if row.id != rows.first?.id {
                            LineDivider()
                        }
                        VPNSwitchRowView(row: row)
                    }
                }
            }
            Button {
                store.openJournal(range: range)
            } label: {
                Label(VPNTexts.allInJournal, systemImage: "scroll")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity)
            }
            .appButtonStyle(.secondary)
            .accessibilityHint("Откроет вкладку «Журнал» с тем же периодом.")
        }
    }
}

struct VPNSwitchRowView: View {
    let row: SwitchHistoryRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(row.time)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.dim)
                ToneChip(text: row.chip, tone: row.level)
                Spacer(minLength: 0)
            }
            Text(row.text)
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.time), \(row.chip): \(row.text)")
    }
}

// MARK: - Connection history (§5.1.6)

/// «Связь» or one service over 24 ч / 7 дн / 30 дн: chart with failure bars and offline bands, tooltip, stats.
struct VPNConnectionCard: View {
    @Environment(RouterStore.self) private var store
    @Binding var range: DataRange
    /// "" = «Связь», else a service name.
    @State private var seriesName: String = ""
    let now: TimeInterval

    var body: some View {
        let services = store.status.map { VPN.services($0) } ?? []
        let series = HistoryChart.validSeries(seriesName.isEmpty ? .connection : .service(seriesName), services: services)
        let data = store.data(range)
        let chart = VPNConnectionCard.makeChart(series: series, data: data, range: range, status: store.status, now: now)
        Card {
            CardTitle(chart.title, symbol: "waveform.path.ecg")
            SegmentedPicker(
                title: "Период",
                selection: $range,
                options: DataRange.allCases.map { SegmentOption($0, $0.shortLabel) }
            )
            if !services.isEmpty {
                VPNSeriesChips(services: services, series: series) { name in
                    seriesName = name
                }
            }
            VPNConnectionChartBody(chart: chart, isLoading: data == nil && chart.isEmpty && store.readError(.data(range)) == nil, now: now)
            StatsGrid(facts: chart.statsFacts(series == .connection && data?.dataRange == range ? data?.stats : nil))
            if let error = store.readError(.data(range)) {
                Banner(tone: .warn, text: error)
            }
        }
    }

    static func makeChart(series: HistoryChart.Series, data: DataResponse?, range: DataRange, status: RouterStatus?, now: TimeInterval) -> HistoryChart {
        switch series {
        case .connection:
            let points = HistoryChart.connectionPoints(data: data, range: range, status: status)
            return HistoryChart.connection(points: points, range: range, now: now)
        case .service(let name):
            let points = data?.tpoints[name] ?? []
            return HistoryChart.service(name, points: points, range: range, now: now)
        }
    }
}

/// «Связь» + one chip per service (selection only).
struct VPNSeriesChips: View {
    let services: [ServiceRef]
    let series: HistoryChart.Series
    let select: (String) -> Void

    var body: some View {
        GlassChipRow {
            GlassChip(title: VPNTexts.connectionTitle, systemImage: "waveform.path.ecg", isSelected: series == .connection) {
                select("")
            }
            ForEach(services, id: \.name) { service in
                GlassChip(
                    title: service.name,
                    systemImage: Summary.serviceIcon(name: service.name, host: service.host, kind: service.kind),
                    isSelected: series == .service(service.name)
                ) {
                    select(service.name)
                }
            }
        }
        .padding(.horizontal, -16)
    }
}

/// Chart + legend + caption, or the empty / loading line.
struct VPNConnectionChartBody: View {
    let chart: HistoryChart
    let isLoading: Bool
    let now: TimeInterval

    var body: some View {
        if isLoading {
            HStack(spacing: 10) {
                ProgressView()
                Text("Загружаю историю…")
                    .font(.subheadline)
                    .foregroundStyle(Theme.dim)
            }
            .frame(minHeight: 60)
        } else if chart.isEmpty || chart.segments.isEmpty && chart.offlineBands.isEmpty && chart.failMarks.isEmpty {
            Text(chart.caption)
                .font(.subheadline)
                .foregroundStyle(Theme.dim)
        } else {
            VPNHistoryChartView(chart: chart, now: now)
            if chart.series == .connection {
                ChartLegend()
            } else {
                HStack(spacing: 12) {
                    LegendItem(color: Theme.acc, text: "задержка")
                    LegendItem(color: Theme.err, text: "не ответил")
                    Spacer(minLength: 0)
                }
                .font(.caption2)
                .foregroundStyle(Theme.dim)
                .accessibilityHidden(true)
            }
            Text(chart.caption)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.dim)
        }
    }
}
