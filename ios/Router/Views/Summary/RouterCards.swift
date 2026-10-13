import SwiftUI
import RouterCore

/// «Роутер» (contract §4.7): meters, temperature, uptime and the LED toggle.
struct RouterCard: View {
    @Environment(RouterStore.self) var store
    let status: RouterStatus

    var body: some View {
        let sys = status.sys
        Card {
            HStack(spacing: 8) {
                Image(systemName: "wifi.router")
                    .foregroundStyle(Theme.dim)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(Summary.routerTitle(sys))
                        .font(.headline)
                        .foregroundStyle(Theme.text)
                    if !sys.fw.isEmpty {
                        Text(sys.fw)
                            .font(.caption)
                            .foregroundStyle(Theme.dim)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            ForEach(Array(Summary.meters(sys).enumerated()), id: \.offset) { _, meter in
                MeterRow(meter: meter)
            }
            ForEach(Array(Summary.routerFacts(sys).enumerated()), id: \.offset) { _, fact in
                FactRow(label: fact.label, value: fact.value)
            }
            if let led = store.led, led.isAvailable {
                LineDivider()
                LEDRow(isOn: led.on)
            }
        }
    }
}

struct MeterRow: View {
    let meter: Meter

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(meter.title)
                    .font(.subheadline)
                    .foregroundStyle(Theme.text)
                Spacer(minLength: 8)
                Text(Fmt.percent(meter.percent))
                    .font(.subheadline.weight(.semibold))
                    .numericValue(meter.percent)
                    .foregroundStyle(meter.tone == .ok ? Theme.text : Theme.levelText(meter.tone))
            }
            MeterBar(percent: meter.percent, tone: meter.tone)
            Text(meter.caption)
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.dim)
        }
        .accessibilityElement(children: .combine)
    }
}

/// «Подсветка»: `POST action/ledset {on}` without a dialog; optimistic, rolled back on error.
/// A local mirror of the switch is used so the store is only called from the view's own actor.
struct LEDRow: View {
    @Environment(RouterStore.self) var store
    let isOn: Bool
    @State var toggle: Bool = false

    var body: some View {
        Toggle(isOn: $toggle) {
            Label {
                Text("Подсветка")
                    .foregroundStyle(Theme.text)
            } icon: {
                Image(systemName: isOn ? "lightbulb" : "lightbulb.slash")
                    .foregroundStyle(Theme.dim)
            }
        }
        .tint(Theme.acc)
        .disabled(!store.isEnabled(.led))
        .accessibilityLabel("Подсветка роутера")
        .onAppear {
            toggle = isOn
        }
        .onChange(of: isOn) { _, newValue in
            toggle = newValue
        }
        .onChange(of: toggle) { _, newValue in
            if newValue != isOn {
                store.setLED(on: newValue)
            }
        }
    }
}

/// «Подписка» (contract §4.8): expiry date, days left, traffic used / left.
struct SubscriptionCard: View {
    let status: RouterStatus
    let now: TimeInterval

    var body: some View {
        if let line = Summary.subscriptionLine(status, now: now), let pick = Summary.pickSubscription(status) {
            Card {
                CardTitle("Подписка", symbol: "calendar")
                Text(line.prefix + line.date)
                    .font(.body.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
                HStack(spacing: 4) {
                    Text("осталось")
                        .foregroundStyle(Theme.dim)
                    Text("\(line.daysLeft)\u{00A0}дн.")
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundStyle(line.daysLeftIsCritical ? Theme.err : Theme.text)
                    Spacer(minLength: 0)
                }
                .font(.subheadline)
                if let usage = SubscriptionCard.usageText(line.usage) {
                    Text(usage)
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(Theme.dim)
                }
                Text(SubscriptionCard.trafficLeft(pick))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// RouterCore gives « · израсходовано …»; drop the leading separator for a separate line.
    static func usageText(_ usage: String?) -> String? {
        guard let text = usage else {
            return nil
        }
        let separator = " · "
        if text.hasPrefix(separator) {
            return String(text.dropFirst(separator.count))
        }
        return text
    }

    static func trafficLeft(_ pick: SubscriptionPick) -> String {
        if pick.total > 0 {
            let left = max(0, pick.total - pick.down - pick.up)
            return "Трафика осталось: \(Fmt.bytes(left))"
        }
        return "Трафик без лимита"
    }
}

/// Devices online (contract §4.11) with the top 4 by today's download; «Все устройства» opens the tab.
struct DevicesCard: View {
    @Environment(RouterStore.self) var store
    let status: RouterStatus

    var body: some View {
        let rows = Summary.topOnlineDevices(status, data: store.dayData ?? store.latestData)
        Card {
            HStack(alignment: .firstTextBaseline) {
                CardTitle("Устройства", symbol: "macbook.and.iphone")
                Spacer(minLength: 8)
                Text(Summary.onlineText(status))
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.accText)
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(row.name)
                        .font(.subheadline)
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    if row.todayDown > 0 {
                        Text("↓\u{00A0}\(Fmt.bytes(row.todayDown))")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Theme.dim)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            Button {
                store.selectedTab = .devices
            } label: {
                CardRow("Все устройства", systemImage: "list.bullet", showsChevron: true)
            }
            .buttonStyle(.plain)
        }
    }
}

/// The last 5 events from `/data` (contract §4.10): time, chip (colour AND word), text.
struct EventsCard: View {
    @Environment(RouterStore.self) var store
    let now: TimeInterval

    var body: some View {
        Card {
            CardTitle("Последние события", symbol: "scroll")
            if let data = store.dayData ?? store.latestData {
                let rows = Summary.recentEvents(data, now: now)
                if rows.isEmpty {
                    Text(Summary.emptyEvents)
                        .font(.subheadline)
                        .foregroundStyle(Theme.dim)
                } else {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        EventRowView(row: row)
                    }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct EventRowView: View {
    let row: EventRow

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
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Router buttons (contract §4.13). Disabled offline, during quiet windows and while another runs.
/// Liquid Glass (guide §3.7): no coloured prominent button in this group — glass buttons, reboot with a red label.
struct ActionsCard: View {
    @Environment(RouterStore.self) var store

    var body: some View {
        Card(spacing: 10) {
            CardTitle("Действия", symbol: "bolt")
            GlassGroup(axis: .vertical, spacing: 10) {
                ActionButton(button: .check, kind: .secondary, busyText: ActionTexts.pingBusy)
                ActionButton(button: .restartVPN, kind: .secondary, busyText: nil)
                ActionButton(button: .updateSubs, kind: .secondary, busyText: nil)
                ActionButton(button: .reboot, kind: .destructiveOutline, busyText: nil)
            }
            if store.offline {
                Text(OfflineBanner.note)
                    .font(.footnote)
                    .foregroundStyle(Theme.dim)
            }
        }
    }
}

struct ActionButton: View {
    @Environment(RouterStore.self) var store
    let button: SummaryButton
    let kind: ActionButtonStyle.Kind
    let busyText: String?

    var body: some View {
        let busy = store.isBusy(button)
        AppButton(
            title: busy ? (busyText ?? button.title) : button.title,
            systemImage: button.symbol,
            kind: kind,
            isBusy: busy
        ) {
            store.tap(button)
        }
        .disabled(!store.isEnabled(button))
    }
}
