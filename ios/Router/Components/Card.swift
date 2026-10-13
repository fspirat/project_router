import SwiftUI
import RouterCore

/// A card (panel): radius 14, `card` fill, 1 pt `border`, optional accent line on top.
struct Card<Content: View>: View {
    private let accent: Color?
    private let content: Content

    init(accent: Color? = nil, @ViewBuilder content: () -> Content) {
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card)
        .overlay(alignment: .top) {
            if let accent = accent {
                Rectangle()
                    .fill(accent)
                    .frame(height: 3)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.border, lineWidth: 1)
        }
    }
}

/// Card heading: an SF Symbol and a title (read as a header by VoiceOver).
struct CardTitle: View {
    let title: String
    let symbol: String

    init(_ title: String, symbol: String) {
        self.title = title
        self.symbol = symbol
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.dim)
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.text)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Small uppercase label above a value.
struct SectionLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(Theme.dim)
    }
}

/// A 1 pt divider in the `line` token.
struct LineDivider: View {
    var body: some View {
        Rectangle()
            .fill(Theme.line)
            .frame(height: 1)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}

/// A coloured dot for a level.
struct ToneDot: View {
    let tone: Tone
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(Theme.dot(tone))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// A chip: text in the level colour on its soft background with a ring.
struct ToneChip: View {
    let text: String
    let tone: Tone

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(Theme.levelText(tone))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Theme.soft(tone), in: Capsule())
            .overlay {
                Capsule().strokeBorder(Theme.ring(tone), lineWidth: 1)
            }
    }
}

/// A banner inside the Summary (offline, quiet window, warnings).
struct Banner: View {
    let tone: Tone
    let title: String?
    let text: String
    let symbol: String?
    let showsProgress: Bool

    init(tone: Tone, title: String? = nil, text: String, symbol: String? = nil, showsProgress: Bool = false) {
        self.tone = tone
        self.title = title
        self.text = text
        self.symbol = symbol
        self.showsProgress = showsProgress
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if showsProgress {
                ProgressView()
                    .tint(Theme.dot(tone))
            } else {
                Image(systemName: symbol ?? Theme.symbol(tone))
                    .foregroundStyle(Theme.dot(tone))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                if let title = title {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                }
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.soft(tone), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Theme.ring(tone), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A 6 pt meter bar: `acc`, `warn` from 65 %, `err` from 85 % (the tone comes from RouterCore).
struct MeterBar: View {
    let percent: Int
    let tone: Tone

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.surface)
                Capsule()
                    .fill(Theme.dot(tone))
                    .frame(width: max(0, geo.size.width * fraction))
            }
        }
        .frame(height: 6)
        .accessibilityHidden(true)
    }

    private var fraction: CGFloat {
        return CGFloat(min(100, max(0, percent))) / 100
    }
}

/// A label/value row («Температура — нет датчика»).
struct FactRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .foregroundStyle(Theme.dim)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}

/// The app logo: green gradient square with a router symbol.
struct LogoView: View {
    var size: CGFloat = 64

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(LinearGradient(colors: [Theme.logoTop, Theme.logoBottom], startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: size, height: size)
            .overlay {
                Image(systemName: "wifi.router")
                    .font(.system(size: size * 0.46, weight: .semibold))
                    .foregroundStyle(Color.white)
            }
            .accessibilityHidden(true)
    }
}
