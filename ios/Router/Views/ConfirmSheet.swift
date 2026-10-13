import SwiftUI
import RouterCore

/// The 428 dialog (contract §2.11): the server's title, text and button shown verbatim,
/// «Отмена», a red button when `danger == critical`, Face ID before the resend for critical actions.
struct ConfirmSheet: View {
    @Environment(RouterStore.self) var store
    @AppStorage(AppSettings.biometricForDangerKey) var biometricForDanger = true
    let pending: PendingConfirm

    var body: some View {
        let prompt = pending.prompt
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: pending.button.symbol)
                        .font(.title2)
                        .foregroundStyle(prompt.isDestructive ? Theme.err : Theme.acc)
                        .accessibilityHidden(true)
                    Text(prompt.displayTitle)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityAddTraits(.isHeader)
                Text(prompt.text.isEmpty ? "Действие затронет работу роутера. Продолжить?" : prompt.text)
                    .font(.body)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if prompt.requiresBiometrics && biometricForDanger {
                    Label("Перед отправкой спросим \(BiometricGate.methodName).", systemImage: "faceid")
                        .font(.footnote)
                        .foregroundStyle(Theme.dim)
                }
                if let error = store.confirmError {
                    Banner(tone: .warn, text: error)
                }
                Button {
                    store.confirmPending()
                } label: {
                    HStack(spacing: 8) {
                        if store.confirmBusy {
                            ProgressView()
                        }
                        Text(store.confirmError == nil ? prompt.displayButton : "Повторить")
                    }
                }
                .buttonStyle(ActionButtonStyle(kind: prompt.isDestructive ? .destructiveFill : .primary))
                .disabled(store.confirmBusy)
                Button {
                    store.cancelPending()
                } label: {
                    Text("Отмена")
                }
                .buttonStyle(ActionButtonStyle(kind: .secondary))
                .disabled(store.confirmBusy)
            }
            .padding(20)
        }
        .background {
            Theme.raise.ignoresSafeArea()
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(store.confirmBusy)
    }
}
