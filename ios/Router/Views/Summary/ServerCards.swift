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
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Проверка через VPN · \(LatencyTile.label)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.text)
                    Text(LatencyTile.caption)
                        .font(.caption)
                        .foregroundStyle(Theme.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    Text(latency.value)
                        .font(.system(.title3, design: .monospaced, weight: .semibold))
                        .foregroundStyle(Theme.levelText(latency.tone))
                        .multilineTextAlignment(.trailing)
                    if let footer = latency.footer {
                        Text(footer)
                            .font(.caption)
                            .foregroundStyle(Theme.dim)
                    }
                }
            }
            .accessibilityElement(children: .combine)
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
                .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                .foregroundStyle(Theme.levelText(tile.tone))
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// «Интернет сейчас»: WAN speed from `/net` (every 3 s while visible) and today's traffic from `/data`.
struct InternetCard: View {
    @Environment(RouterStore.self) var store

    var body: some View {
        let current: NetStats? = store.offline ? nil : (store.net ?? store.status?.sys.net)
        let today: TrafficToday? = store.dayData.map { Summary.trafficToday($0) }
        Card {
            CardTitle("Интернет сейчас", symbol: "speedometer")
            if let net = current {
                HStack(alignment: .top, spacing: 16) {
                    SpeedValue(symbol: "arrow.down", label: "Загрузка", value: Fmt.speed(net.rx))
                    SpeedValue(symbol: "arrow.up", label: "Отдача", value: Fmt.speed(net.tx))
                }
                Text("С момента включения: ↓ \(Fmt.bytes(net.rxTotal)) · ↑ \(Fmt.bytes(net.txTotal))")
                    .font(.caption)
                    .foregroundStyle(Theme.faint)
            } else {
                Text(store.offline ? "Скорость появится, когда роутер снова будет на связи." : "—")
                    .font(.subheadline)
                    .foregroundStyle(Theme.faint)
            }
            if let traffic = today, traffic.isVisible {
                LineDivider()
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text("Сегодня ↓ \(traffic.downText)")
                        .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("↑ \(traffic.upText)")
                        .font(.system(.subheadline, design: .monospaced))
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
        .onAppear {
            store.netCardVisible = true
        }
        .onDisappear {
            store.netCardVisible = false
        }
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
                .font(.system(.title2, design: .monospaced, weight: .semibold))
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
