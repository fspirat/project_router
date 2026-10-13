import SwiftUI
import RouterCore

/// Lock screen: no data visible, Face ID / passcode to open.
struct LockView: View {
    @Environment(AppLock.self) var lock

    var body: some View {
        ZStack {
            AppBackground()
            VStack(spacing: 18) {
                LogoView(size: 88)
                Text("Роутер")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Text("Приложение заблокировано")
                    .font(.subheadline)
                    .foregroundStyle(Theme.dim)
                if lock.lastAttemptFailed {
                    Text("Не получилось подтвердить — попробуй ещё раз.")
                        .font(.footnote)
                        .foregroundStyle(Theme.warn)
                        .multilineTextAlignment(.center)
                }
                AppButton(title: "Разблокировать", systemImage: "faceid", kind: .primary, isBusy: lock.isAuthenticating) {
                    unlock()
                }
                .frame(maxWidth: 320)
                .disabled(lock.isAuthenticating)
            }
            .padding(24)
        }
        .accessibilityAddTraits(.isModal)
    }

    private func unlock() {
        Task {
            await lock.unlock()
        }
    }
}
