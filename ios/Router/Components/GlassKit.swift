import SwiftUI
import RouterCore

// Liquid Glass design kit for «Роутер» (stage 4; guide: docs/ios/liquid-glass.md).
// Deployment target iOS 17, built with the iOS 26 SDK, Swift 5 mode.
// Rule of thumb: real Liquid Glass (glassEffect / .glass button styles) only on the
// control layer — buttons, chips, floating toasts. Content cards use standard materials.
// Every iOS 26 symbol is used only inside `if #available(iOS 26.0, *)`; never store a `Glass` in a property.

// MARK: - Metrics

enum Metrics {
    static let screenPadding: CGFloat = 16
    static let cardSpacing: CGFloat = 14
    static let cardRadius: CGFloat = 24
    static let tileRadius: CGFloat = 18
    static let innerRadius: CGFloat = 14
}

// MARK: - App background (content layer, under everything)

/// Soft tinted gradient: `bg` plus a green glow top-left and a blue glow bottom-right.
/// Gives Liquid Glass (tab bar, toolbar, buttons) something to refract, in light and dark.
struct AppBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        ZStack {
            Theme.bg
            RadialGradient(
                colors: [Theme.acc.opacity(dark ? 0.20 : 0.16), Color.clear],
                center: .topLeading,
                startRadius: 0,
                endRadius: 460
            )
            RadialGradient(
                colors: [Theme.info.opacity(dark ? 0.16 : 0.10), Color.clear],
                center: .bottomTrailing,
                startRadius: 0,
                endRadius: 520
            )
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension View {
    /// Screen root (ScrollView, List or Form inside a NavigationStack): hide the default
    /// list background and put the app gradient behind everything, edge to edge.
    func appScreenBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background {
                AppBackground()
            }
    }
}

// MARK: - Cards (content layer: material, not Liquid Glass)

/// Card surface: regular material + optional level tint + a light «rim» on top.
/// Reduce Transparency makes the material opaque by itself; Increase Contrast gets a solid border.
struct CardSurface: ViewModifier {
    var cornerRadius: CGFloat = Metrics.cardRadius
    var tint: Color? = nil
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let dark = scheme == .dark
        content
            .background {
                shape
                    .fill(Material.regular)
                    .overlay {
                        if let tint = tint {
                            shape.fill(tint.opacity(dark ? 0.12 : 0.07))
                        }
                    }
            }
            .overlay {
                if contrast == .increased {
                    shape.strokeBorder(Theme.border2, lineWidth: 1)
                } else {
                    shape.strokeBorder(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(dark ? 0.16 : 0.80),
                                Color.white.opacity(dark ? 0.04 : 0.30)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                }
            }
    }
}

/// One hero element per screen may be real glass (e.g. the verdict on «Сводка»).
/// iOS 26: tinted regular glass; earlier: the card material.
struct HeroGlassSurface: ViewModifier {
    var cornerRadius: CGFloat = Metrics.cardRadius
    var tint: Color? = nil

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(
                    Glass.regular.tint(tint?.opacity(0.22)),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
        } else {
            content
                .modifier(CardSurface(cornerRadius: cornerRadius, tint: tint))
        }
    }
}

/// Tile inside a card (stats, meters, service tiles): a quiet fill, never glass on glass.
struct TileSurface: ViewModifier {
    var tone: Tone? = nil
    var cornerRadius: CGFloat = Metrics.innerRadius

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        content
            .background(tone.map { Theme.soft($0) } ?? Theme.tileFill, in: shape)
            .overlay {
                shape.strokeBorder(tone.map { Theme.ring($0) } ?? Color.primary.opacity(0.06), lineWidth: 1)
            }
    }
}

extension View {
    /// Padded card: `VStack { … }.glassCard()`.
    func glassCard(cornerRadius: CGFloat = Metrics.cardRadius, tint: Color? = nil) -> some View {
        self
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(CardSurface(cornerRadius: cornerRadius, tint: tint))
    }

    /// The single hero card of a screen (real glass on iOS 26).
    func heroGlassCard(cornerRadius: CGFloat = Metrics.cardRadius, tint: Color? = nil) -> some View {
        self
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(HeroGlassSurface(cornerRadius: cornerRadius, tint: tint))
    }

    /// Stand-alone tile in a grid (outside a card): smaller material card.
    func glassTile(cornerRadius: CGFloat = Metrics.tileRadius, tint: Color? = nil) -> some View {
        self
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(CardSurface(cornerRadius: cornerRadius, tint: tint))
    }

    /// Tile inside a card.
    func innerTile(tone: Tone? = nil, cornerRadius: CGFloat = Metrics.innerRadius) -> some View {
        self
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .modifier(TileSurface(tone: tone, cornerRadius: cornerRadius))
    }
}

// MARK: - Chips and filters (control layer: interactive glass in a container)

/// Surface of one chip. iOS 26: interactive glass, selected = glass tinted with `acc` at 35 % (contract-stage4
/// §8 rule 7) and a neutral label, so the label contrast does not depend on the backdrop; the selection also
/// shows in the weight, the checkmark (where used) and the `.isSelected` trait.
/// `isInteractive: false` for a chip that is not a control (no touch reaction on inert glass).
struct ChipSurface: ViewModifier {
    let isSelected: Bool
    var isInteractive: Bool = true

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            let base: Glass = isSelected ? Glass.regular.tint(Theme.acc.opacity(0.35)) : Glass.regular
            let glass: Glass = base.interactive(isInteractive)
            content
                .foregroundStyle(Theme.text)
                .glassEffect(glass, in: Capsule())
        } else {
            content
                .foregroundStyle(isSelected ? Theme.onAcc : Theme.text)
                .background(isSelected ? AnyShapeStyle(Theme.acc) : AnyShapeStyle(Material.thin), in: Capsule())
                .overlay {
                    Capsule().strokeBorder(isSelected ? Color.clear : Theme.border, lineWidth: 1)
                }
        }
    }
}

extension View {
    func glassChip(selected: Bool, interactive: Bool = true) -> some View {
        modifier(ChipSurface(isSelected: selected, isInteractive: interactive))
    }
}

/// A tappable filter / sort chip («Все», «В сети», «По пингу»…). Selection only — never an action.
struct GlassChip: View {
    let title: String
    var systemImage: String? = nil
    var count: Int? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage = systemImage {
                    Image(systemName: systemImage)
                        .imageScale(.small)
                        .accessibilityHidden(true)
                }
                Text(title)
                if let count = count {
                    Text(String(count))
                        .monospacedDigit()
                        .opacity(0.7)
                }
            }
            .font(.subheadline.weight(isSelected ? .semibold : .regular))
            .lineLimit(1)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassChip(selected: isSelected)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Horizontal chip row. iOS 26: one GlassEffectContainer for all chips (one render pass,
/// shapes can morph). Container spacing is smaller than the HStack spacing so chips do not
/// melt together at rest. Place it outside the 16-pt padded column: it pads itself.
struct GlassChipRow<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            row
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.vertical, 4)
        }
        .scrollClipDisabled()
    }

    @ViewBuilder
    private var row: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 4) {
                HStack(spacing: 8) {
                    content
                }
            }
        } else {
            HStack(spacing: 8) {
                content
            }
        }
    }
}

/// A group of interactive glass controls (mode segments, a card's action buttons): iOS 26 puts them in one
/// `GlassEffectContainer` (one render pass, shared sampling); a plain stack earlier. The container spacing is
/// smaller than the stack spacing, so the shapes never melt together at rest.
struct GlassGroup<Content: View>: View {
    var axis: Axis = .horizontal
    var spacing: CGFloat = 8
    var containerSpacing: CGFloat = 0
    private let content: Content

    init(axis: Axis = .horizontal, spacing: CGFloat = 8, containerSpacing: CGFloat = 0, @ViewBuilder content: () -> Content) {
        self.axis = axis
        self.spacing = spacing
        self.containerSpacing = containerSpacing
        self.content = content()
    }

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: containerSpacing) {
                stack
            }
        } else {
            stack
        }
    }

    @ViewBuilder
    private var stack: some View {
        if axis == .horizontal {
            HStack(spacing: spacing) {
                content
            }
        } else {
            VStack(spacing: spacing) {
                content
            }
        }
    }
}

// MARK: - Buttons

extension ActionButtonStyle.Kind {
    /// Label colour per kind — the same mapping as ActionButtonStyle (contract §6).
    var labelColor: Color {
        switch self {
        case .primary:
            return Theme.onAcc
        case .secondary:
            return Theme.text
        case .destructiveOutline:
            return Theme.err
        case .destructiveFill:
            return Color.white
        }
    }
}

extension View {
    /// The app's four button kinds. iOS 26: system Liquid Glass button styles
    /// (press reaction, morphing, accessibility settings come for free); earlier: ActionButtonStyle.
    /// Full width: give the label `.frame(maxWidth: .infinity)` (AppButton does it).
    @ViewBuilder
    func appButtonStyle(_ kind: ActionButtonStyle.Kind) -> some View {
        if #available(iOS 26.0, *) {
            switch kind {
            case .primary:
                self
                    .buttonStyle(.glassProminent)
                    .tint(Theme.acc)
                    .foregroundStyle(kind.labelColor)
                    .controlSize(.large)
            case .secondary, .destructiveOutline:
                self
                    .buttonStyle(.glass)
                    .foregroundStyle(kind.labelColor)
                    .controlSize(.large)
            case .destructiveFill:
                self
                    .buttonStyle(.glassProminent)
                    .tint(Theme.errFill)
                    .foregroundStyle(kind.labelColor)
                    .controlSize(.large)
            }
        } else {
            self.buttonStyle(ActionButtonStyle(kind: kind))
        }
    }
}

/// Full-width action button: icon + text, optional spinner while busy.
struct AppButton: View {
    let title: String
    var systemImage: String? = nil
    var kind: ActionButtonStyle.Kind = .primary
    var isBusy: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView()
                } else if let systemImage = systemImage {
                    Image(systemName: systemImage)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
            }
            // Colour on the label itself: wins over any style default on every iOS version.
            .foregroundStyle(kind.labelColor)
            .frame(maxWidth: .infinity)
        }
        .appButtonStyle(kind)
    }
}

/// Small round icon button inside content (e.g. «Проверить сейчас» next to a server row, the sheet's close
/// button). The 30-pt label plus the circle style's insets give a ≥ 44-pt circle (HIG tap target).
struct GlassIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 30, height: 30)
                .contentShape(Circle())
        }
        .glassIconStyle()
        .accessibilityLabel(accessibilityLabel)
    }
}

extension View {
    @ViewBuilder
    func glassIconStyle() -> some View {
        if #available(iOS 26.0, *) {
            self
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
        } else {
            self
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
        }
    }
}

// MARK: - Floating elements (toast, «VPN перезапускается…» pill)

/// Floating capsule over content: the right place for real glass.
struct FloatingSurface: ViewModifier {
    var tint: Color? = nil

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(Glass.regular.tint(tint?.opacity(0.25)), in: Capsule())
        } else {
            content
                .background(Material.regular, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(Theme.border, lineWidth: 1)
                }
        }
    }
}

extension View {
    func floatingGlass(tint: Color? = nil) -> some View {
        self
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .modifier(FloatingSurface(tint: tint))
    }
}

// MARK: - Sheets

extension View {
    /// iOS 26: no custom background, so the system Liquid Glass sheet shows (inset at .medium,
    /// more opaque at .large). Earlier iOS: the opaque `raise` colour as before.
    /// For a ScrollView/VStack sheet (ConfirmSheet, server card, schedule sheet).
    @ViewBuilder
    func sheetSurface() -> some View {
        if #available(iOS 26.0, *) {
            self
        } else {
            self.background {
                Theme.raise.ignoresSafeArea()
            }
        }
    }

    /// For a `Form` / `List` inside a sheet (Settings, rename): the grouped background is hidden;
    /// iOS 26 shows the glass sheet behind the rows, earlier iOS the `bg` colour as in stage 3.
    /// Rows keep `.listRowBackground(Theme.card)`.
    @ViewBuilder
    func sheetFormBackground() -> some View {
        if #available(iOS 26.0, *) {
            self
                .scrollContentBackground(.hidden)
        } else {
            self
                .scrollContentBackground(.hidden)
                .background {
                    Theme.bg.ignoresSafeArea()
                }
        }
    }
}

// MARK: - Layout helpers

extension View {
    /// Cancels the 16-pt screen padding of `ScreenScroll` for edge-to-edge rows (`GlassChipRow` pads itself).
    func fullBleed() -> some View {
        self.padding(.horizontal, -Metrics.screenPadding)
    }

    /// Live numbers (speed, ping): rolling digits on change; respects Reduce Motion by itself.
    func numericValue<V: Equatable>(_ value: V) -> some View {
        self
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(.default, value: value)
    }
}
