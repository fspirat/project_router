import SwiftUI

/// All app buttons: primary (accent fill), secondary, destructive outline (Summary «Перезагрузить роутер»),
/// destructive fill (red confirm button: `danger: critical`, block, dirdel, revoke-all).
/// One style type with a `kind`, so a view can pick the kind at run time.
///
/// Stage 4: views do not use this style directly — use `.appButtonStyle(kind)` / `AppButton` (GlassKit.swift):
/// iOS 26 gets the system Liquid Glass styles, iOS 17–25 falls back to this capsule style.
struct ActionButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
        case destructiveOutline
        case destructiveFill
    }

    var kind: Kind = .primary

    func makeBody(configuration: Configuration) -> some View {
        StyledButtonBody(configuration: configuration, kind: kind)
    }
}

private struct StyledButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let kind: ActionButtonStyle.Kind
    @Environment(\.isEnabled) var isEnabled

    var body: some View {
        let shape = Capsule()
        configuration.label
            .font(.body.weight(.semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(textColor)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(fillColor, in: shape)
            .overlay {
                shape.strokeBorder(borderColor, lineWidth: 1)
            }
            .contentShape(shape)
            .opacity(isEnabled ? 1 : 0.45)
    }

    private var pressed: Bool {
        return configuration.isPressed
    }

    private var textColor: Color {
        switch kind {
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

    private var fillColor: Color {
        switch kind {
        case .primary:
            return pressed ? Theme.accPressed : Theme.acc
        case .secondary:
            return pressed ? Theme.hover : Theme.surface
        case .destructiveOutline:
            return pressed ? Theme.errSoft : Color.clear
        case .destructiveFill:
            return pressed ? Theme.errFillPressed : Theme.errFill
        }
    }

    private var borderColor: Color {
        switch kind {
        case .primary, .destructiveFill:
            return Color.clear
        case .secondary:
            return Theme.border2
        case .destructiveOutline:
            return Theme.errBorder
        }
    }
}

/// Text field look for the login form.
struct FieldBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.border2, lineWidth: 1)
            }
    }
}

extension View {
    func fieldBackground() -> some View {
        modifier(FieldBackground())
    }
}
