import SwiftUI
import RouterCore

/// «Новые за неделю» (contract-stage4 §5.2.4): newest first, one row per MAC, up to 5 rows plus «Ещё N».
/// Each row opens the device card; a MAC without a lease opens a card with MAC, traffic and rename only.
struct DevicesNewCard: View {
    let rows: [NewDeviceRow]
    @State private var showAll = false

    private static let limit = 5

    var body: some View {
        let visible = showAll ? rows : Array(rows.prefix(DevicesNewCard.limit))
        let hidden = rows.count - visible.count
        Card(tint: Theme.info, spacing: 0) {
            CardHeader(DeviceTexts.newTitle, symbol: "sparkles") {
                Text(String(rows.count))
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.dim)
                    .accessibilityLabel(Fmt.count(rows.count, "устройство", "устройства", "устройств"))
            }
            .padding(.bottom, 6)
            ForEach(Array(visible.enumerated()), id: \.element.id) { item in
                if item.offset > 0 {
                    LineDivider()
                }
                NavigationLink(value: DeviceRoute(mac: item.element.mac)) {
                    NewDeviceRowView(row: item.element)
                }
                .buttonStyle(.plain)
            }
            if hidden > 0 {
                LineDivider()
                Button {
                    showAll = true
                } label: {
                    Text("Ещё \(hidden)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.accText)
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Показать ещё " + Fmt.count(hidden, "устройство", "устройства", "устройств"))
            }
        }
    }
}

/// «Galaxy-S23 · вчера 21:44 · Открыть ›».
private struct NewDeviceRowView: View {
    let row: NewDeviceRow

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.body.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Theme.dim)
                    .lineLimit(2)
            }
            Spacer(minLength: 8)
            HStack(spacing: 4) {
                Text(DeviceTexts.open)
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
            }
            .foregroundStyle(Theme.accText)
            .accessibilityHidden(true)
        }
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(row.title + ", появилось " + row.whenText + (showsMAC ? ", адрес " + row.mac : ""))
        .accessibilityHint("Открыть карточку устройства")
    }

    /// The MAC is the title already when the lease is gone and there is no own name.
    private var showsMAC: Bool {
        return !row.isKnown && row.title != row.mac
    }

    /// «появилось вчера 21:44» (+ «· <mac>» for a device without a lease).
    private var subtitle: String {
        var text = "появилось " + row.whenText
        if showsMAC {
            text += " · " + row.mac
        }
        return text
    }
}
