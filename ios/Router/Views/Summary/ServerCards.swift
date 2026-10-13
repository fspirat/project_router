import SwiftUI
import RouterCore

/// «Подключён сервер» + the «через VPN» check (contract §4.3, §4.4).
struct ServerCard: View {
    let status: RouterStatus
    let now: TimeInterval

    var body: some View {
        let server = Summary.currentServer(status)
        let latency = Summary.latency(status, now: now)
        Card {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(CurrentServer.label)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(server.name)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                    if let tag = server.tag {
                        ToneChip(text: tag, tone: server.isDirect ? .warn : .neutral)
                    }
                    Spacer(minLength: 0)
                }
            }
            .accessibilityElement(children: .combine)
            LineDivider()
            LatencyRow(latency: latency)
        }
    }
}

/// «Проверка через VPN» (contract-stage4 §9.4): the title on one line, the big value on the right,
/// the explanation («Задержка — как пинг: …») below the title, «Проверено …» under the value.
/// VoiceOver: «Проверка через VPN, задержка 48 мс».
/// At accessibility text sizes the title, value, caption and footer are stacked (nothing truncates).
struct LatencyRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let latency: LatencyTile

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                stacked
            } else {
                regular
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(LatencyTile.accessibilityLabel(value: latency.value))
        .accessibilityValue(latency.footer ?? "")
    }

    private var stacked: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LatencyTile.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(latency.value)
                .font(.title3.weight(.semibold))
                .numericValue(latency.value)
                .foregroundStyle(Theme.levelText(latency.tone))
                .fixedSize(horizontal: false, vertical: true)
            Text(LatencyTile.caption)
                .font(.caption)
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
            if let footer = latency.footer {
                Text(footer)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var regular: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(LatencyTile.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .allowsTightening(true)
                    .layoutPriority(1)
                Spacer(minLength: 8)
                Text(latency.value)
                    .font(.title3.weight(.semibold))
                    .numericValue(latency.value)
                    .foregroundStyle(Theme.levelText(latency.tone))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(LatencyTile.caption)
                    .font(.caption)
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let footer = latency.footer {
                    Text(footer)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.dim)
                        .multilineTextAlignment(.trailing)
                }
            }
        }
    }
}

/// Service tiles: YouTube / Discord / Telegram … via the current server (contract §4.5).
struct ServicesCard: View {
    let status: RouterStatus

    var body: some View {
        let tiles = Summary.services(status)
        if !tiles.isEmpty {
            Card {
                CardTitle("Сервисы", symbol: "globe")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in
                        ServiceTileView(tile: tile)
                    }
                }
            }
        }
    }
}

struct ServiceTileView: View {
    let tile: ServiceTile

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: tile.icon)
                .font(.title3)
                .foregroundStyle(Theme.dim)
                .accessibilityHidden(true)
            Text(tile.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
            Text(tile.valueText)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.levelText(tile.tone))
                .lineLimit(2)
        }
        .innerTile()
        .accessibilityElement(children: .combine)
    }
}

/// «Интернет сейчас»: WAN speed from `/net` (every 3 s while visible) and today's traffic from `/data`.
struct InternetCard: View {
    @Environment(RouterStore.self) var store

    var body: some View {
        let current: NetStats? = store.offline ? nil : (store.net ?? store.status?.sys.net)
        let today: TrafficToday? = (store.dayData ?? store.latestData).map { Summary.trafficToday($0) }
        Card {
            CardTitle("Интернет сейчас", symbol: "speedometer")
            if let net = current {
                HStack(alignment: .top, spacing: 16) {
                    SpeedValue(symbol: "arrow.down", label: "Загрузка", value: Fmt.speed(net.rx))
                    SpeedValue(symbol: "arrow.up", label: "Отдача", value: Fmt.speed(net.tx))
                }
                Text("С момента включения: ↓\u{00A0}\(Fmt.bytes(net.rxTotal)) · ↑\u{00A0}\(Fmt.bytes(net.txTotal))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.dim)
            } else {
                Text(store.offline ? "Скорость появится, когда роутер снова будет на связи." : "—")
                    .font(.subheadline)
                    .foregroundStyle(Theme.dim)
            }
            if let traffic = today, traffic.isVisible {
                LineDivider()
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Сегодня ↓\u{00A0}\(traffic.downText)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.text)
                    Text("↑\u{00A0}\(traffic.upText)")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(Theme.dim)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Сегодня скачано \(traffic.downText), отдано \(traffic.upText)")
                Text(Summary.todayCaption)
                    .font(.caption)
                    .foregroundStyle(Theme.faint)
            }
        }
        // `/net` every 3 s only while this card is on screen (and no sheet is up, see `shouldPoll`).
        .pollingScope([.net])
    }
}

struct SpeedValue: View {
    let symbol: String
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(label, systemImage: symbol)
                .font(.caption)
                .foregroundStyle(Theme.dim)
            Text(value)
                .font(.title2.weight(.semibold))
                .numericValue(value)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
