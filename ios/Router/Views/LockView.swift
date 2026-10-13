import SwiftUI
import RouterCore

/// Lock screen: no data visible, Face ID / passcode to open.
struct LockView: View {
    @Environment(AppLock.self) var lock

    var body: some View {
        ZStack {
            Theme.bg
                .ignoresSafeArea()
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
                Button {
                    unlock()
                } label: {
                    HStack(spacing: 8) {
                        if lock.isAuthenticating {
                            ProgressView()
                        } else {
                            Image(systemName: "faceid")
                        }
                        Text("Разблокировать")
                    }
                }
                .buttonStyle(ActionButtonStyle(kind: .primary))
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
