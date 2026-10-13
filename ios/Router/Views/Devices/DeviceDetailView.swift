import SwiftUI
import RouterCore

/// The device card (contract-stage4 §5.3), pushed from the list. Reads the shared caches, so it updates
/// with every `/status` and `/data` read. A MAC without a lease shows only MAC, traffic and rename.
struct DeviceDetailView: View {
    @Environment(RouterStore.self) private var store
    let mac: String
    @State private var showRename = false
    @State private var showSchedule = false

    private static let kinds: Set<ReadKind> = [.status, .data(.day)]

    var body: some View {
        let detail = store.deviceDetail(mac: mac)
        ScreenScroll(refresh: DeviceDetailView.kinds) {
            DeviceDetailHeader(detail: detail)
            if store.offline && detail.isKnown {
                StaleDataNote()
                    .padding(.horizontal, 4)
            }
            DeviceFactsCard(detail: detail)
                .staleDimmed(store.offline && detail.isKnown)
            DeviceActionsCard(detail: detail, showRename: $showRename, showSchedule: $showSchedule)
            Text(detail.footer)
                .font(.footnote)
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
        .navigationTitle(detail.title)
        .navigationBarTitleDisplayMode(.inline)
        .pollingScope(DeviceDetailView.kinds)
        .appSheet(isPresented: $showRename) {
            DeviceRenameSheet(mac: mac)
        }
        .appSheet(isPresented: $showSchedule) {
            DeviceScheduleSheet(mac: mac)
        }
    }
}

/// Name, «Имя в сети: …», status and labels. The screen's one hero card (real glass on iOS 26).
private struct DeviceDetailHeader: View {
    @Environment(RouterStore.self) private var store
    let detail: DeviceDetail

    var body: some View {
        let status = statusLine
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Theme.dot(status.tone))
                .frame(width: 48, height: 48)
                .background(Theme.soft(status.tone), in: Circle())
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(detail.title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let caption = detail.networkNameCaption {
                    Text(caption)
                        .font(.footnote)
                        .foregroundStyle(Theme.dim)
                }
                HStack(spacing: 6) {
                    ToneDot(tone: status.tone)
                    Text(status.text)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(status.tone == .neutral ? Theme.dim : Theme.levelText(status.tone))
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Статус: " + status.text)
                if let device = store.routerDevice(mac: detail.mac) {
                    let labels = Devices.labels(device)
                    if !labels.isEmpty {
                        DeviceLabelsView(labels: labels)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .heroGlassCard(tint: tint)
    }

    private var icon: String {
        guard let device = store.routerDevice(mac: detail.mac) else {
            return "questionmark.circle"
        }
        if !device.online {
            return "wifi.slash"
        }
        if let band = device.band, band != "wired" {
            return "wifi"
        }
        return "cable.connector"
    }

    private var tint: Color? {
        if detail.blocked || detail.sblocked {
            return Theme.err
        }
        return detail.isOnline ? Theme.acc : nil
    }

    /// «В сети · Wi-Fi 5 ГГц» / «Не в сети» from the core rows; a device without a lease says so.
    private var statusLine: (text: String, tone: Tone) {
        if let row = detail.rows.first(where: { $0.label == DeviceDetailLabels.status }) {
            return (row.value, row.tone)
        }
        if store.status == nil {
            return ("Нет данных от роутера", .neutral)
        }
        return ("Сейчас нет в списке роутера", .neutral)
    }
}

/// Labels of `DetailRow`s the screen treats specially (RouterCore `Devices.detail`).
enum DeviceDetailLabels {
    static let status = "Статус"
    static let mac = "MAC"
    static let ip = "IP"
    static let signal = "Сигнал"
    static let today = "Сегодня"
    static let month = "За месяц"
}

/// IP, MAC (+ «скрытый MAC»), signal, traffic today/month, internet, VPN, schedule.
private struct DeviceFactsCard: View {
    @Environment(RouterStore.self) private var store
    let detail: DeviceDetail

    var body: some View {
        let rows = detail.rows.filter { $0.label != DeviceDetailLabels.status }
        let signalLevel = store.routerDevice(mac: detail.mac).map { Devices.signalLevel($0.signal) }
        Card(spacing: 0) {
            CardTitle("Подробности", symbol: "info.circle")
                .padding(.bottom, 6)
            ForEach(Array(rows.enumerated()), id: \.element.id) { item in
                if item.offset > 0 {
                    LineDivider()
                }
                DeviceFactRow(row: item.element, signalLevel: item.element.label == DeviceDetailLabels.signal ? signalLevel : nil)
            }
        }
    }
}

/// Label on the left, value on the right (tabular digits), optional caption under it.
private struct DeviceFactRow: View {
    let row: DetailRow
    /// 1–4 for the «Сигнал» row (spoken as a word), else nil.
    var signalLevel: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    label
                    Spacer(minLength: 8)
                    value
                        .multilineTextAlignment(.trailing)
                }
                VStack(alignment: .leading, spacing: 2) {
                    label
                    value
                }
            }
            if let caption = row.caption {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.label)
        .accessibilityValue(spokenValue)
    }

    private var label: some View {
        Text(row.label)
            .font(.subheadline)
            .foregroundStyle(Theme.dim)
    }

    private var value: some View {
        Text(row.value)
            .font(.subheadline.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(row.tone == .neutral ? Theme.text : Theme.levelText(row.tone))
            .textSelection(.enabled)
    }

    private var spokenValue: String {
        var text = row.value.replacingOccurrences(of: " · ", with: ", ")
        if let level = signalLevel, level > 0 {
            text = DeviceAccessibility.signalWord(level) + ", " + text
        }
        if row.label == DeviceDetailLabels.today || row.label == DeviceDetailLabels.month {
            text = DeviceAccessibility.traffic(text)
        }
        if let caption = row.caption {
            text += ". " + caption
        }
        return text
    }
}
