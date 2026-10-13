import SwiftUI
import RouterCore

/// Login form: panel password + phone name → number in the Telegram bot (contract §7.6).
/// The password is never stored; the field is cleared as soon as it is sent.
struct LoginView: View {
    @Environment(RouterStore.self) var store
    @State var password = ""
    @State var deviceName = LoginTexts.defaultDeviceName
    @FocusState var focus: Field?

    enum Field: Hashable {
        case password
        case name
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                if let message = store.loginMessage {
                    Banner(tone: .err, text: message)
                }
                Card {
                    passwordField
                    nameField
                    LoginButton(canSubmit: canSubmit, busy: store.loginBusy) {
                        submit()
                    }
                }
                Text("Пароль не сохраняется. После входа на телефоне остаётся только ключ доступа в Keychain.")
                    .font(.footnote)
                    .foregroundStyle(Theme.dim)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background {
            AppBackground()
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            LogoView(size: 72)
            Text("Роутер")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(Theme.text)
            Text("Вход: пароль веб-панели и подтверждение в Telegram-боте.")
                .font(.subheadline)
                .foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
    }

    private var passwordField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LoginTexts.passwordField)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.dim)
            SecureField(LoginTexts.passwordField, text: $password)
                .textContentType(.password)
                .submitLabel(.next)
                .focused($focus, equals: .password)
                .onSubmit {
                    focus = .name
                }
                .fieldBackground()
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LoginTexts.nameField)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.dim)
            TextField(LoginTexts.nameField, text: $deviceName)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .focused($focus, equals: .name)
                .onSubmit {
                    submit()
                }
                .onChange(of: deviceName) { _, newValue in
                    let limited = Validation.limitDeviceNameInput(newValue)
                    if limited != newValue {
                        deviceName = limited
                    }
                }
                .fieldBackground()
            Text("Так телефон будет подписан в боте и в веб-панели.")
                .font(.footnote)
                .foregroundStyle(Theme.dim)
        }
    }

    private var canSubmit: Bool {
        return !password.isEmpty && Validation.isValidDeviceName(deviceName) && !store.loginBusy
    }

    private func submit() {
        guard canSubmit, store.loginBlockedSeconds(now: Date()) == 0 else {
            return
        }
        let secret = password
        password = ""
        focus = nil
        store.startLogin(password: secret, deviceName: deviceName)
    }
}

/// «Войти» with a spinner and a countdown while login is blocked (`429 locked / rate_limited`).
struct LoginButton: View {
    @Environment(RouterStore.self) var store
    let canSubmit: Bool
    let busy: Bool
    let action: () -> Void

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { context in
            let blocked = store.loginBlockedSeconds(now: context.date)
            AppButton(
                title: blocked > 0 ? LoginButton.waitText(blocked) : LoginTexts.loginButton,
                kind: .primary,
                isBusy: busy
            ) {
                action()
            }
            .disabled(!canSubmit || blocked > 0)
        }
    }

    /// «Войти можно через 42 с» / «… через 15 мин».
    static func waitText(_ seconds: Int) -> String {
        if seconds < 60 {
            return "Войти можно через \(seconds)" + Fmt.nbsp + "с"
        }
        return "Войти можно через " + Fmt.minutes((seconds + 59) / 60)
    }
}
