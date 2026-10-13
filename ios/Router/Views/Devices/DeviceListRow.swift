import SwiftUI
import RouterCore

/// One device row inside a section card (contract-stage4 §5.2.3): online dot, name, subtitle (IP · rate),
/// labels, Wi-Fi signal and today's traffic. Plain content (no glass per row); the whole row is the tap target.
struct DeviceListRow: View {
    let row: DeviceRowInfo
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        DeviceOnlineDot(isOnline: row.isOnline)
                        info
                    }
                    HStack(spacing: 12) {
                        trailing
                        Spacer(minLength: 0)
                    }
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    DeviceOnlineDot(isOnline: row.isOnline)
                    info
                    Spacer(minLength: 8)
                    trailing
                    chevron
                }
            }
        }
        .padding(.vertical, 8)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DeviceAccessibility.rowLabel(row))
        .accessibilityHint("Открыть карточку устройства")
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(row.title)
                .font(.body.weight(row.isOnline ? .semibold : .regular))
                .foregroundStyle(row.hasName ? Theme.text : Theme.dim)
                .lineLimit(2)
            if !row.subtitle.isEmpty {
                Text(row.subtitle)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Theme.dim)
                    .lineLimit(2)
            }
            if !row.labels.isEmpty {
                DeviceLabelsView(labels: row.labels)
                    .padding(.top, 2)
            }
        }
    }

    @ViewBuilder
    private var trailing: some View {
        HStack(spacing: 10) {
            if let level = row.signalLevel {
                DeviceSignalIcon(level: level)
            }
            if let today = row.todayText {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(today)
                        .font(.subheadline.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Text(DeviceTexts.today)
                        .font(.caption2)
                        .foregroundStyle(Theme.dim)
                }
            }
        }
    }

    private var chevron: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.faint)
            .accessibilityHidden(true)
    }
}

/// Filled accent dot (online) or a hollow ring (offline).
struct DeviceOnlineDot: View {
    let isOnline: Bool

    var body: some View {
        Group {
            if isOnline {
                Circle()
                    .fill(Theme.acc)
            } else {
                Circle()
                    .strokeBorder(Theme.faint, lineWidth: 1.5)
            }
        }
        .frame(width: 9, height: 9)
        .accessibilityHidden(true)
    }
}

/// The row labels: «без интернета», «по расписанию», «мимо VPN», «⏲ 23:00–07:00». Wraps to a column when
/// the row is too narrow (large Dynamic Type).
struct DeviceLabelsView: View {
    let labels: [DeviceLabel]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                chips
            }
            VStack(alignment: .leading, spacing: 4) {
                chips
            }
        }
    }

    private var chips: some View {
        ForEach(Array(labels.enumerated()), id: \.offset) { item in
            ToneChip(text: item.element.text, tone: item.element.tone, systemImage: item.element.symbol)
                .monospacedDigit()
        }
    }
}

/// The Wi-Fi symbol filled to the signal level (1–4).
struct DeviceSignalIcon: View {
    let level: Int

    var body: some View {
        Image(systemName: "wifi", variableValue: Double(min(max(level, 0), 4)) / 4)
            .font(.subheadline)
            .foregroundStyle(level <= 1 ? Theme.warn : Theme.dim)
            .accessibilityHidden(true)
    }
}

/// VoiceOver texts: levels as words, arrows as words.
enum DeviceAccessibility {
    /// «отличный» / «хороший» / «средний» / «слабый».
    static func signalWord(_ level: Int) -> String {
        switch level {
        case 4:
            return "отличный"
        case 3:
            return "хороший"
        case 2:
            return "средний"
        case 1:
            return "слабый"
        default:
            return "неизвестен"
        }
    }

    /// «↓ 1,5 ГБ» → «скачано 1,5 ГБ» (RouterCore puts an NBSP after the arrows; a plain space is still accepted).
    static func traffic(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "↓" + Fmt.nbsp, with: "скачано ")
            .replacingOccurrences(of: "↑" + Fmt.nbsp, with: "отдано ")
            .replacingOccurrences(of: "↓ ", with: "скачано ")
            .replacingOccurrences(of: "↑ ", with: "отдано ")
            .replacingOccurrences(of: " · ", with: ", ")
    }

    static func rowLabel(_ row: DeviceRowInfo) -> String {
        var parts: [String] = [row.title]
        parts.append(row.isOnline ? "в сети" : "не в сети")
        for label in row.labels {
            parts.append(label.symbol == "timer" ? "расписание " + label.text : label.text)
        }
        if !row.subtitle.isEmpty {
            parts.append(row.subtitle.replacingOccurrences(of: " · ", with: ", "))
        }
        if let level = row.signalLevel {
            var signal = "сигнал " + signalWord(level)
            if let exact = row.signalAccessibility {
                signal += ", " + exact.replacingOccurrences(of: "Сигнал ", with: "")
            }
            parts.append(signal)
        }
        if let today = row.todayText {
            parts.append(DeviceTexts.today + " " + traffic(today))
        }
        return parts.joined(separator: ", ")
    }
}
