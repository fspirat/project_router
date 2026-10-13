import SwiftUI
import RouterCore

// MARK: - Subscriptions (§5.1.7): view + «Обновить» only (add / delete — in the web panel)

struct VPNSubscriptionsCard: View {
    @Environment(RouterStore.self) private var store
    let status: RouterStatus
    let now: TimeInterval

    var body: some View {
        let rows = VPN.subscriptions(status, now: now)
        Card {
            CardHeader(VPNTexts.subscriptionsTitle, symbol: "doc.text") {
                Text(VPN.subscriptionsHeader(rows.count))
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Theme.dim)
            }
            if rows.isEmpty {
                EmptyStateView(title: VPNTexts.noSubscriptions, systemImage: "tray")
            } else {
                ForEach(rows) { row in
                    if row.id != rows.first?.id {
                        LineDivider()
                    }
                    VPNSubscriptionRowView(row: row)
                }
                if rows.count > 1 {
                    VPNUpdateButton(title: VPNTexts.updateAll, action: .subupdateAll, label: nil)
                }
                Text(VPNTexts.subscriptionsFooter)
                    .font(.footnote)
                    .foregroundStyle(Theme.dim)
            }
        }
    }
}

struct VPNSubscriptionRowView: View {
    let row: SubscriptionRow

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(row.name)
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if row.hwid || row.isCurrentSource {
                    HStack(spacing: 6) {
                        if row.hwid {
                            ToneChip(text: "HWID", tone: .info)
                                .accessibilityHint(VPNTexts.hwidHint)
                        }
                        if row.isCurrentSource {
                            ToneChip(text: "сервер отсюда подключён", tone: .ok)
                        }
                    }
                }
                Text(row.info)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if row.daysLeftText != nil || row.expiryText != nil {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let left = row.daysLeftText {
                        Text(left)
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(row.daysLeftIsCritical ? Theme.err : Theme.text)
                    }
                    if let expiry = row.expiryText {
                        Text(expiry)
                            .font(.subheadline)
                            .foregroundStyle(Theme.dim)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
            if let usage = row.usageText {
                Text(usage)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let percent = row.percent {
                MeterBar(percent: percent, tone: row.barTone)
            }
            VPNUpdateButton(title: VPNTexts.update, action: row.updateAction, label: row.name)
        }
        .padding(.vertical, 4)
    }
}

/// «Обновить» (one subscription) / «Обновить все»: `subupdate` → 428 high.
struct VPNUpdateButton: View {
    @Environment(RouterStore.self) private var store
    let title: String
    let action: RouterAction
    let label: String?

    var body: some View {
        let busy = store.vpnIsBusy(action)
        VStack(alignment: .leading, spacing: 4) {
            Button {
                store.perform(action, label: label, symbol: "arrow.down.circle")
            } label: {
                HStack(spacing: 6) {
                    if busy {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.down.circle")
                            .accessibilityHidden(true)
                    }
                    Text(title)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(Theme.text)
            }
            .appButtonStyle(.secondary)
            .disabled(!store.canPerform(action))
            .accessibilityLabel(label.map { "\(title) подписку «\($0)»" } ?? title)
            .accessibilityHint("Список серверов скачается заново, потом VPN перезапустится. Сначала спросит подтверждение.")
            VPNLockCountdown(action: action)
        }
    }
}

// MARK: - Router speed test (§5.1.8)

/// «С роутера, через VPN» / «С роутера, без VPN» with «Запустить» (job, no dialog) and the caption.
struct VPNSpeedTestCard: View {
    let status: RouterStatus
    let now: TimeInterval

    var body: some View {
        Card {
            CardTitle("Тест скорости роутера", symbol: "speedometer")
            VPNSpeedChannel(info: VPN.speedCard(via: .vpn, result: status.speed.vpn, now: now))
            LineDivider()
            VPNSpeedChannel(info: VPN.speedCard(via: .direct, result: status.speed.direct, now: now))
            Label(VPNTexts.speedCaption, systemImage: "info.circle")
                .font(.footnote)
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct VPNSpeedChannel: View {
    @Environment(RouterStore.self) private var store
    let info: SpeedCardInfo

    var body: some View {
        let action = RouterAction.speedtest(via: info.via)
        let running = store.isRunning(action)
        VStack(alignment: .leading, spacing: 10) {
            Text(info.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.text)
                .accessibilityAddTraits(.isHeader)
            if info.isEmpty {
                Text(info.emptyText)
                    .font(.subheadline)
                    .foregroundStyle(Theme.dim)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], alignment: .leading, spacing: 8) {
                    VPNSpeedMetric(label: "Загрузка", value: info.downText, symbol: "arrow.down")
                    VPNSpeedMetric(label: "Отдача", value: info.upText, symbol: "arrow.up")
                    VPNSpeedMetric(label: "Задержка", value: info.latencyText, symbol: "timer")
                }
                if !info.meta.isEmpty {
                    Text(info.meta)
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button {
                store.perform(action)
            } label: {
                HStack(spacing: 6) {
                    if running {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "play.fill")
                            .accessibilityHidden(true)
                    }
                    Text(running ? VPNTexts.speedBusy : VPNTexts.speedRun)
                        .fontWeight(.semibold)
                }
                .foregroundStyle(Theme.text)
            }
            .appButtonStyle(.secondary)
            .disabled(!store.canPerform(action))
            .accessibilityLabel(running ? VPNTexts.speedBusy : "\(VPNTexts.speedRun): \(info.title)")
            VPNLockCountdown(action: action)
        }
    }
}

struct VPNSpeedMetric: View {
    let label: String
    let value: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(label, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(Theme.dim)
            Text(value)
                .font(.headline)
                .numericValue(value)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .innerTile()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
    }
}

/// 90-day history (`data.speed`, the same in every range) with an optional «Отдача» view.
struct VPNSpeedHistoryCard: View {
    @Environment(RouterStore.self) private var store
    @State private var showsUpload = false
    let now: TimeInterval

    var body: some View {
        let rows = store.latestData?.speed ?? []
        let chart = VPN.speedHistory(rows, now: now, upload: showsUpload)
        Card {
            CardTitle(showsUpload ? "История отдачи, Мбит/с" : VPNTexts.speedHistoryTitle, symbol: "chart.xyaxis.line")
            if chart.isEmpty {
                if store.latestData == nil {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Загружаю историю…")
                            .font(.subheadline)
                            .foregroundStyle(Theme.dim)
                    }
                    .frame(minHeight: 44)
                } else {
                    EmptyStateView(title: chart.caption, systemImage: "chart.xyaxis.line")
                }
            } else {
                SegmentedPicker(
                    title: "Показать",
                    selection: $showsUpload,
                    options: [SegmentOption(false, "Загрузка"), SegmentOption(true, "Отдача")]
                )
                VPNSpeedChartView(chart: chart)
                HStack(spacing: 12) {
                    ForEach(chart.series) { series in
                        LegendItem(color: VPNSpeedChartView.color(series.via), text: series.label)
                    }
                    Spacer(minLength: 0)
                }
                .font(.caption2)
                .foregroundStyle(Theme.dim)
                .accessibilityHidden(true)
                Text(chart.caption)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.dim)
            }
        }
    }
}

// MARK: - Own servers (§5.1.9, `/vds`, read-only, works offline)

struct VPNOwnServersCard: View {
    @Environment(RouterStore.self) private var store
    let now: TimeInterval

    var body: some View {
        let info = VPN.ownServers(store.vds, now: now)
        let error = store.readError(.vds)
        Card {
            CardTitle(VPNTexts.ownServersTitle, symbol: "server.rack")
            if store.vds == nil && error == nil {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Загружаю…")
                        .font(.subheadline)
                        .foregroundStyle(Theme.dim)
                }
                .frame(minHeight: 44)
            } else {
                ForEach(info.rows) { row in
                    if row.id != info.rows.first?.id {
                        LineDivider()
                    }
                    VPNOwnServerRowView(row: row)
                }
                Text(info.footer)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Theme.dim)
            }
            if let error = error {
                Banner(tone: .warn, text: error)
            }
        }
    }
}

struct VPNOwnServerRowView: View {
    let row: OwnServerRow

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ToneDot(tone: row.tone, size: 10)
                .padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    if let caption = row.caption {
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(Theme.dim)
                    }
                }
                Text(row.statusLine)
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Theme.levelText(row.tone))
                if let load = row.loadLine {
                    Text(load)
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let uptime = row.uptimeLine {
                    Text(uptime)
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.name + (row.caption.map { ", " + $0 } ?? "") + ", " + (row.tone == .ok ? "в порядке" : "проблема"))
        .accessibilityValue([row.statusLine, row.loadLine ?? "", row.uptimeLine ?? ""].filter { !$0.isEmpty }.joined(separator: ". "))
    }
}
