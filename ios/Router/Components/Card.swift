import SwiftUI
import RouterCore

// Content-layer building blocks shared by every screen (stage 4: material cards, see GlassKit.swift).
// Numbers: `.monospacedDigit()` only — never `design: .monospaced` (contract-stage4 §9.1).

/// A card (panel): material + light rim, radius 24 (`CardSurface`), optional 3 pt accent line on top
/// and an optional level tint. Rows inside are plain views — never glass on glass.
struct Card<Content: View>: View {
    private let accent: Color?
    private let tint: Color?
    private let spacing: CGFloat
    private let content: Content

    init(accent: Color? = nil, tint: Color? = nil, spacing: CGFloat = 12, @ViewBuilder content: () -> Content) {
        self.accent = accent
        self.tint = tint
        self.spacing = spacing
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Metrics.cardRadius, style: .continuous)
        VStack(alignment: .leading, spacing: spacing) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(CardSurface(cornerRadius: Metrics.cardRadius, tint: tint))
        .overlay(alignment: .top) {
            if let accent = accent {
                Rectangle()
                    .fill(accent)
                    .frame(height: 3)
                    .accessibilityHidden(true)
            }
        }
        .clipShape(shape)
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

/// Card heading with something on the right (a count, a menu, a small button).
struct CardHeader<Trailing: View>: View {
    let title: String
    let symbol: String
    private let trailing: Trailing

    init(_ title: String, symbol: String, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.symbol = symbol
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            CardTitle(title, symbol: symbol)
            Spacer(minLength: 8)
            trailing
        }
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

/// A status chip (content, not tappable): text in the level colour on its soft background with a ring.
/// For tappable filter chips use `GlassChip`.
struct ToneChip: View {
    let text: String
    let tone: Tone
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage = systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            Text(text)
        }
        .font(.caption.weight(.medium))
        .lineLimit(1)
        .foregroundStyle(Theme.levelText(tone))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Theme.soft(tone), in: Capsule())
        .overlay {
            Capsule().strokeBorder(Theme.ring(tone), lineWidth: 1)
        }
    }
}

/// A banner inside a screen (offline, quiet window, warnings, errors of a section).
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
        .background(Theme.soft(tone), in: RoundedRectangle(cornerRadius: Metrics.innerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Metrics.innerRadius, style: .continuous)
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
                    .fill(Theme.tileFill)
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

/// A label/value row («Температура — нет датчика»). The value uses tabular digits, proportional letters.
struct FactRow: View {
    let label: String
    let value: String
    var valueColor: Color = Theme.text

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .foregroundStyle(Theme.dim)
            Spacer(minLength: 8)
            Text(value)
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .multilineTextAlignment(.trailing)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}

/// A list row inside a card: optional icon, title, subtitle, something on the right, optional chevron.
/// Make it tappable by wrapping it in `Button { … } label: { CardRow(…) }.buttonStyle(.plain)` or a
/// `NavigationLink(value:)` with `.buttonStyle(.plain)` — never with a swipe action.
struct CardRow<Trailing: View>: View {
    let title: String
    let subtitle: String?
    let systemImage: String?
    let iconColor: Color
    let showsChevron: Bool
    private let trailing: Trailing

    init(
        _ title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        iconColor: Color = Theme.dim,
        showsChevron: Bool = false,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.iconColor = iconColor
        self.showsChevron = showsChevron
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let systemImage = systemImage {
                Image(systemName: systemImage)
                    .font(.body)
                    .foregroundStyle(iconColor)
                    .frame(width: 24)
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle = subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            trailing
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.faint)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}

extension CardRow where Trailing == EmptyView {
    init(
        _ title: String,
        subtitle: String? = nil,
        systemImage: String? = nil,
        iconColor: Color = Theme.dim,
        showsChevron: Bool = false
    ) {
        self.init(title, subtitle: subtitle, systemImage: systemImage, iconColor: iconColor, showsChevron: showsChevron) {
            EmptyView()
        }
    }
}

/// Empty state. `.full` = the system `ContentUnavailableView` (a whole screen or a big section);
/// `.inline` = a quiet icon + text line inside a card.
struct EmptyStateView: View {
    enum Style {
        case full
        case inline
    }

    let title: String
    let systemImage: String
    var text: String? = nil
    var style: Style = .inline

    var body: some View {
        switch style {
        case .full:
            ContentUnavailableView(title, systemImage: systemImage, description: text.map { Text($0) })
        case .inline:
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(Theme.faint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                    if let text = text {
                        Text(text)
                            .font(.footnote)
                            .foregroundStyle(Theme.faint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
        }
    }
}

/// A search field inside a card (MyDirect «Найти домен…»). For a whole screen use `.searchable` instead.
struct SearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.dim)
                .accessibilityHidden(true)
            TextField(prompt, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.faint)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Очистить")
            }
        }
        .fieldBackground()
    }
}

/// One option of `SegmentedPicker`.
struct SegmentOption<Value: Hashable>: Identifiable {
    let value: Value
    let label: String

    init(_ value: Value, _ label: String) {
        self.value = value
        self.label = label
    }

    var id: Value {
        return value
    }
}

/// System segmented control for 2–4 fixed options (system Liquid Glass on iOS 26).
/// Selection only — it never starts a router action by itself.
struct SegmentedPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [SegmentOption<Value>]

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(options) { option in
                Text(option.label).tag(option.value)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel(title)
    }
}

/// Last known router data while the router is offline: dims the content (contract-stage4 §4.3).
/// Put `StaleDataNote()` above the dimmed block.
extension View {
    func staleDimmed(_ isStale: Bool) -> some View {
        self.opacity(isStale ? 0.55 : 1)
    }
}

/// «Последние известные данные роутера» (proposed, contract-stage4 §4.3).
struct StaleDataNote: View {
    var body: some View {
        Label(AppTexts.staleData, systemImage: "clock.arrow.circlepath")
            .font(.footnote)
            .foregroundStyle(Theme.dim)
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

/// App-side texts that RouterCore does not have (proposed in contract-stage4).
enum AppTexts {
    static let staleData = "Последние известные данные роутера"
    static let appDisabledTitle = "Приложение выключено"
}
