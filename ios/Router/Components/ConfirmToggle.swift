import SwiftUI
import RouterCore

/// A system toggle that never flips by itself: it always shows the **server** value (`isOn`); a tap only
/// asks for the change (`onRequest` → `store.perform`, which shows the server's 428 confirm). The switch moves
/// after the router has applied it and the next read says so (contract-stage4 §5.4.1).
struct ConfirmToggle: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    let isOn: Bool
    var isBusy: Bool = false
    let isEnabled: Bool
    var accessibilityHint: String = "Изменение нужно будет подтвердить"
    let onRequest: @MainActor () -> Void

    var body: some View {
        Toggle(isOn: request) {
            HStack(alignment: .center, spacing: 12) {
                if let systemImage = systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(Theme.dim)
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
                            .foregroundStyle(Theme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Выполняется")
                }
            }
        }
        .tint(Theme.acc)
        .frame(minHeight: 44)
        .disabled(!isEnabled)
        .accessibilityHint(accessibilityHint)
    }

    /// Reads the server value; a tap that would change it asks for the action instead of storing anything.
    private var request: Binding<Bool> {
        let current = isOn
        let ask = onRequest
        return Binding(
            get: {
                current
            },
            set: { @MainActor newValue in
                if newValue != current {
                    ask()
                }
            }
        )
    }
}
