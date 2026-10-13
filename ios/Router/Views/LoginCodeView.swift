import SwiftUI
import RouterCore

/// The number screen: press the same number in the Telegram bot (contract §7.6 step 3–4).
struct LoginCodeView: View {
    @Environment(RouterStore.self) var store

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Подтверди вход в Telegram")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .multilineTextAlignment(.center)
                    .padding(.top, 32)
                if let challenge = store.challenge {
                    ChallengeNumber(number: challenge.number)
                    Text(LoginTexts.pressNumber(challenge.number))
                        .font(.body)
                        .foregroundStyle(Theme.text)
                        .multilineTextAlignment(.center)
                    Countdown(total: challenge.expiresIn)
                }
                Text("Бот прислал сообщение «Вход в приложение» с тремя числами и кнопкой «Это не я». Неверное число отклонит вход.")
                    .font(.footnote)
                    .foregroundStyle(Theme.dim)
                    .multilineTextAlignment(.center)
                Button {
                    store.cancelLogin()
                } label: {
                    Text(LoginTexts.cancelButton)
                }
                .buttonStyle(ActionButtonStyle(kind: .secondary))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background {
            Theme.bg.ignoresSafeArea()
        }
    }
}

/// The big number.
struct ChallengeNumber: View {
    let number: Int

    var body: some View {
        Text(verbatim: String(number))
            .font(.system(size: 88, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Theme.accText)
            .minimumScaleFactor(0.5)
            .lineLimit(1)
            .padding(.horizontal, 28)
            .padding(.vertical, 8)
            .background(Theme.accSoft, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(Theme.accRing, lineWidth: 1)
            }
            .accessibilityLabel("Число \(number)")
    }
}

/// «Ждём нажатия в боте…» with the seconds left and a progress bar.
struct Countdown: View {
    @Environment(RouterStore.self) var store
    let total: Int

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            let left = store.loginSecondsLeft(now: context.date)
            let maximum = Double(max(total, 1))
            VStack(spacing: 8) {
                ProgressView(value: min(Double(left), maximum), total: maximum)
                    .tint(Theme.acc)
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Ждём нажатия в боте… \(left) с")
                        .font(.subheadline)
                        .foregroundStyle(Theme.dim)
                        .monospacedDigit()
                }
            }
        }
    }
}
