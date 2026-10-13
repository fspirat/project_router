import SwiftUI
import RouterCore

/// The 428 dialog (contract §2.11, contract-stage4 §3.3): the server's title, text and button shown verbatim,
/// an optional app warning line above the text, «Отмена», a red button for `danger == critical`, block,
/// dirdel, revoke-all (or when the screen asks), Face ID before the resend for critical actions.
/// Presented by the topmost presentation host; screens never present it themselves.
struct ConfirmSheet: View {
    @Environment(RouterStore.self) var store
    @AppStorage(AppSettings.biometricForDangerKey) var biometricForDanger = true
    let pending: PendingConfirm

    var body: some View {
        let prompt = pending.prompt
        let destructive = pending.isDestructive
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: pending.symbol)
                        .font(.title2)
                        .foregroundStyle(destructive ? Theme.err : Theme.acc)
                        .accessibilityHidden(true)
                    Text(prompt.displayTitle)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityAddTraits(.isHeader)
                if let note = pending.request.note, !note.isEmpty {
                    Label(note, systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
                VStack(spacing: 10) {
                    AppButton(
                        title: store.confirmError == nil ? prompt.displayButton : "Повторить",
                        kind: destructive ? .destructiveFill : .primary,
                        isBusy: store.confirmBusy
                    ) {
                        store.confirmPending()
                    }
                    .disabled(store.confirmBusy)
                    AppButton(title: "Отмена", kind: .secondary) {
                        store.cancelPending()
                    }
                    .disabled(store.confirmBusy)
                }
                .padding(.top, 4)
            }
            .padding(20)
        }
        .sheetSurface()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(store.confirmBusy)
    }
}
