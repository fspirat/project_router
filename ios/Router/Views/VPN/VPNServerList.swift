import SwiftUI
import RouterCore

// Server list (contract-stage4 §5.1.3), port of web renderServers: sort chips, «Свои серверы», subscription
// groups, «Не отвечают: N» (collapsed), «Напрямую, без VPN». A tap on a row opens the server card; there is
// no swipe action and no tap-to-switch on the row itself.

struct VPNServersSection: View {
    @Environment(RouterStore.self) private var store
    /// UI preference (not data): `ServerSort.storageValue`.
    @AppStorage("vpnSort") private var sortStorage: String = ServerSort.default.storageValue
    let status: RouterStatus
    let now: TimeInterval
    let openServer: (String) -> Void

    var body: some View {
        let list = VPN.serverList(status, sort: ServerSort(storage: sortStorage), now: now)
        VStack(alignment: .leading, spacing: Metrics.cardSpacing) {
            if !list.groups.isEmpty {
                VPNSortChips(sort: list.sort, services: list.services) { key in
                    sortStorage = list.sort.tapped(key).storageValue
                }
            }
            if let empty = list.emptyText {
                Card {
                    CardTitle("Серверы", symbol: "server.rack")
                    EmptyStateView(title: empty, systemImage: "antenna.radiowaves.left.and.right.slash")
                }
            }
            ForEach(list.groups) { group in
                VPNServerGroupCard(group: group, openServer: openServer)
            }
            if !list.dead.isEmpty {
                VPNDeadServersCard(title: list.deadTitle, rows: list.dead, openServer: openServer)
            }
            if let direct = list.direct {
                VPNDirectCard(row: direct, openServer: openServer)
            }
            VPNServersFooter(footer: list.footer)
        }
    }
}

/// «Сортировка: пинг / имя / <сервис>»; tapping the active key flips the direction (selection only).
struct VPNSortChips: View {
    let sort: ServerSort
    let services: [ServiceRef]
    let select: (ServerSortKey) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel("Сортировка")
                .padding(.horizontal, 4)
            GlassChipRow {
                chip(.ping, title: "Пинг")
                chip(.name, title: "Имя")
                ForEach(services, id: \.name) { service in
                    chip(.service(service.name), title: service.name)
                }
            }
            .fullBleed()
        }
    }

    private func chip(_ key: ServerSortKey, title: String) -> some View {
        let selected = sort.key == key
        let arrow = sort.ascending ? "arrow.up" : "arrow.down"
        return GlassChip(title: title, systemImage: selected ? arrow : nil, isSelected: selected) {
            select(key)
        }
        .accessibilityLabel("Сортировка: \(title)")
        .accessibilityValue(selected ? (sort.ascending ? "по возрастанию" : "по убыванию") : "")
        .accessibilityHint(selected ? "Нажми ещё раз, чтобы поменять направление." : "")
    }
}

/// One group card: «Свои серверы» or a subscription group (untitled → «Серверы»).
struct VPNServerGroupCard: View {
    let group: VPNServerGroup
    let openServer: (String) -> Void

    var body: some View {
        let isOwn = group.kind == .own
        Card(spacing: 4) {
            CardTitle(group.title ?? "Серверы", symbol: isOwn ? "server.rack" : "list.bullet.rectangle")
                .padding(.bottom, 4)
            ForEach(group.rows) { row in
                if row.id != group.rows.first?.id {
                    LineDivider()
                }
                VPNServerRowButton(row: row, openServer: openServer)
            }
        }
    }
}

/// «Не отвечают: N», collapsed by default. Rows open the server card (no quick action).
struct VPNDeadServersCard: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false
    let title: String
    let rows: [VPNServerRow]
    let openServer: (String) -> Void

    var body: some View {
        Card(spacing: 4) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right.slash")
                        .foregroundStyle(Theme.dim)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(Theme.text)
                    Spacer(minLength: 8)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.faint)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? "развёрнуто" : "свёрнуто")
            if isExpanded {
                ForEach(rows) { row in
                    LineDivider()
                    VPNServerRowButton(row: row, openServer: openServer)
                }
            }
        }
    }
}

/// «Напрямую, без VPN»: ping = TCP to ya.ru from the router.
struct VPNDirectCard: View {
    let row: VPNServerRow
    let openServer: (String) -> Void

    var body: some View {
        Card(spacing: 4) {
            CardTitle(VPNTexts.directButton, symbol: "arrow.right.circle")
                .padding(.bottom, 4)
            VPNServerRowButton(row: row, openServer: openServer)
            Text(VPNTexts.directCaption)
                .font(.caption)
                .foregroundStyle(Theme.dim)
        }
    }
}

/// Footer caption + «Проверить все серверы» (the Summary «Проверить» ping job; no dialog while VPN passes).
struct VPNServersFooter: View {
    @Environment(RouterStore.self) private var store
    let footer: String

    var body: some View {
        let busy = store.isBusy(.check)
        VStack(alignment: .leading, spacing: 10) {
            Text(footer)
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
            AppButton(
                title: busy ? ActionTexts.pingBusy : "Проверить все серверы",
                systemImage: "arrow.clockwise",
                kind: .secondary,
                isBusy: busy
            ) {
                store.vpnCheckAll()
            }
            .disabled(!store.isEnabled(.check))
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Row

struct VPNServerRowButton: View {
    let row: VPNServerRow
    let openServer: (String) -> Void

    var body: some View {
        Button {
            openServer(row.id)
        } label: {
            VPNServerRowView(row: row)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(VPNA11y.row(row))
        .accessibilityHint("Открыть карточку сервера")
        .accessibilityAddTraits(.isButton)
    }
}

/// Name (+ «свой» / «без VPN»), the services line, ping bars + «41 мс», «сейчас» or a chevron.
struct VPNServerRowView: View {
    let row: VPNServerRow

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(row.name)
                        .font(.body.weight(row.isCurrent ? .semibold : .regular))
                        .foregroundStyle(Theme.text)
                        .lineLimit(2)
                    if let tag = row.tag {
                        ToneChip(text: tag, tone: row.isDirect ? .warn : .neutral)
                    }
                }
                if !row.cells.isEmpty {
                    Text(VPNServiceText.line(row.cells))
                        .font(.footnote)
                        .lineLimit(2)
                } else if row.isDead {
                    Text("не отвечает")
                        .font(.footnote)
                        .foregroundStyle(Theme.dim)
                }
            }
            Spacer(minLength: 8)
            VPNPingBadge(text: row.pingText, tone: row.pingTone, level: row.pingLevel, isBest: row.pingIsBest)
            if row.isCurrent {
                ToneChip(text: "сейчас", tone: .ok)
            } else {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.faint)
            }
        }
        .padding(.vertical, 6)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .opacity(row.isDead ? 0.6 : 1)
    }
}

/// `cellularbars` (level 0–5) + «41 мс» / «—», tone by `msTone`, bold when it is the best of the column.
struct VPNPingBadge: View {
    let text: String
    let tone: Tone
    let level: Int
    var isBest: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "cellularbars", variableValue: Double(max(0, min(5, level))) / 5)
                .foregroundStyle(Theme.dot(tone))
                .accessibilityHidden(true)
            Text(text)
                .font(.subheadline.weight(isBest ? .bold : .medium))
                .monospacedDigit()
                .foregroundStyle(isBest ? Theme.accText : Theme.levelText(tone))
                .lineLimit(1)
                .fixedSize()
        }
    }
}

// MARK: - Texts

/// The services line «YouTube 61 · Discord — · Telegram ·» with the best value bold/accent, «—» red,
/// «·» (not measured) and «блок» faint.
enum VPNServiceText {
    static func line(_ cells: [ServiceCell]) -> AttributedString {
        var out = AttributedString()
        for (index, cell) in cells.enumerated() {
            if index > 0 {
                var sep = AttributedString(" · ")
                sep.foregroundColor = Theme.faint
                out.append(sep)
            }
            var name = AttributedString(cell.service + Fmt.nbsp)
            name.foregroundColor = Theme.dim
            out.append(name)
            var value = AttributedString(cell.text)
            value.foregroundColor = valueColor(cell)
            if cell.isBest {
                let bold: Font = Font.footnote.weight(.bold)
                value.font = bold
            }
            out.append(value)
        }
        return out
    }

    static func valueColor(_ cell: ServiceCell) -> Color {
        if cell.value == nil || cell.isBlocked {
            return Theme.faint
        }
        if cell.isBest {
            return Theme.accText
        }
        switch cell.tone {
        case .err:
            return Theme.err
        case .warn:
            return Theme.warn
        default:
            return Theme.text
        }
    }
}

/// VoiceOver texts (levels as words, never colour only).
enum VPNA11y {
    static func ping(_ text: String, tone: Tone) -> String {
        if text == "—" || text == "нет ответа" {
            return "пинг: нет ответа"
        }
        return "пинг \(text), \(level(tone))"
    }

    static func level(_ tone: Tone) -> String {
        switch tone {
        case .ok:
            return "быстро"
        case .warn:
            return "средне"
        case .err:
            return "медленно"
        case .info, .neutral:
            return Theme.levelWord(tone)
        }
    }

    static func cell(_ cell: ServiceCell) -> String {
        if cell.isBlocked {
            return "\(cell.service): \(cell.hint ?? "блок")"
        }
        guard let v = cell.value else {
            return "\(cell.service): ещё не мерили"
        }
        if v > 0 {
            return "\(cell.service) \(Fmt.ms(v))" + (cell.isBest ? ", лучший" : "")
        }
        return "\(cell.service): нет ответа"
    }

    static func row(_ row: VPNServerRow) -> String {
        var parts: [String] = [row.name]
        if let tag = row.tag {
            parts.append(tag)
        }
        if row.isCurrent {
            parts.append("подключён сейчас")
        }
        parts.append(ping(row.pingText, tone: row.pingTone) + (row.pingIsBest ? ", лучший" : ""))
        for cell in row.cells {
            parts.append(self.cell(cell))
        }
        return parts.joined(separator: ", ")
    }
}
