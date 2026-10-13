import SwiftUI
import RouterCore

/// One journal event inside a day card (contract-stage4 §5.5): kind icon in the level colour, text (wraps),
/// time «14:10» (Samara, tabular digits) and the level as a word («Ошибка», «Внимание», «Успех», «Действие») —
/// colour AND word. Plain content: not tappable, no swipe actions, no glass per row.
struct JournalRowView: View {
    let row: JournalRow
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            JournalLevelIcon(symbol: row.symbol, level: row.level)
            VStack(alignment: .leading, spacing: 6) {
                if typeSize.isAccessibilitySize {
                    time
                    text
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        text
                        time
                    }
                }
                ToneChip(text: row.chip, tone: row.level)
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(JournalRowView.voiceLabel(row))
    }

    private var text: some View {
        Text(row.text)
            .font(.body)
            .foregroundStyle(Theme.text)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var time: some View {
        Text(row.time)
            .font(.subheadline)
            .monospacedDigit()
            .foregroundStyle(Theme.dim)
            .lineLimit(1)
            .fixedSize()
    }

    /// «Ошибка, 19:40. Роутер пропал со связи».
    static func voiceLabel(_ row: JournalRow) -> String {
        return row.chip + ", " + row.time + ". " + row.text
    }
}

/// The kind symbol (wifi.slash, power, …) on a soft disc in the level colour. Decorative for VoiceOver
/// (the row label says the level as a word).
private struct JournalLevelIcon: View {
    let symbol: String
    let level: Tone
    /// Not private: a private stored property would make the memberwise initializer private.
    @ScaledMetric(relativeTo: .body) var size: CGFloat = 32

    var body: some View {
        Image(systemName: symbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.dot(level))
            .frame(width: size, height: size)
            .background(Theme.soft(level), in: Circle())
            .overlay {
                Circle().strokeBorder(Theme.ring(level), lineWidth: 1)
            }
            .accessibilityHidden(true)
    }
}
