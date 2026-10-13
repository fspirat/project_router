import SwiftUI
import RouterCore

/// Minimal stage 3 Settings (contract §7.9): Face ID, theme, this phone, logout, links, about.
/// The device list and revocation are stage 4 (web panel and bot /apps for now).
struct SettingsView: View {
    @Environment(RouterStore.self) var store
    @Environment(\.dismiss) var dismiss
    @AppStorage(AppSettings.lockOnOpenKey) var lockOnOpen = false
    @AppStorage(AppSettings.lockDelayKey) var lockDelay = 0
    @AppStorage(AppSettings.biometricForDangerKey) var biometricForDanger = true
    @AppStorage(AppSettings.themeKey) var theme: ThemeChoice = .system
    @State var lockToggle = false
    @State var dangerToggle = true
    @State var authBusy = false
    @State var confirmLogout = false
    @State var loggingOut = false

    var body: some View {
        NavigationStack {
            Form {
                securitySection
                themeSection
                deviceSection
                linksSection
                aboutSection
            }
            .scrollContentBackground(.hidden)
            .background {
                Theme.bg.ignoresSafeArea()
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog(SettingsTexts.logoutTitle, isPresented: $confirmLogout, titleVisibility: .visible) {
                Button(SettingsTexts.logoutConfirm, role: .destructive) {
                    logout()
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text(SettingsTexts.logoutText)
            }
        }
        .onAppear {
            lockToggle = lockOnOpen
            dangerToggle = biometricForDanger
        }
        .onChange(of: lockToggle) { _, newValue in
            lockToggleChanged(newValue)
        }
        .onChange(of: dangerToggle) { _, newValue in
            dangerToggleChanged(newValue)
        }
        .task { [store] in
            await store.read(.me)
        }
    }

    // MARK: - Sections

    private var canAuthenticate: Bool {
        return BiometricGate.canAuthenticate
    }

    private var securitySection: some View {
        Section {
            Toggle(isOn: $lockToggle) {
                Label("Face ID при открытии", systemImage: "faceid")
            }
            .tint(Theme.acc)
            .disabled(!canAuthenticate || authBusy)
            Picker("Блокировать", selection: $lockDelay) {
                Text("Сразу").tag(0)
                Text("Через 1 минуту").tag(60)
                Text("Через 5 минут").tag(300)
            }
            .disabled(!lockOnOpen)
            Toggle(isOn: $dangerToggle) {
                Label("Face ID для опасных действий", systemImage: "exclamationmark.shield")
            }
            .tint(Theme.acc)
            .disabled(authBusy)
        } header: {
            Text("Защита")
        } footer: {
            if canAuthenticate {
                Text("Для опасных действий (перезагрузка роутера) Face ID спрашивается после кнопки подтверждения.")
            } else {
                Text("На iPhone не задан код-пароль — блокировка приложения недоступна.")
            }
        }
        .listRowBackground(Theme.card)
    }

    private var themeSection: some View {
        Section {
            Picker("Тема", selection: $theme) {
                ForEach(ThemeChoice.allCases) { choice in
                    Text(choice.title).tag(choice)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text("Тема")
        }
        .listRowBackground(Theme.card)
    }

    private var deviceSection: some View {
        Section {
            LabeledContent("Название", value: deviceName)
            if let info = store.sessionInfo {
                if info.expires > 0 {
                    Text(ExpiryNotice.loginUntil(expires: info.expires))
                        .foregroundStyle(Theme.text)
                }
                if info.hardExpires > 0 {
                    Text(ExpiryNotice.notLongerThan(hardExpires: info.hardExpires))
                        .foregroundStyle(Theme.text)
                }
                if let warning = ExpiryNotice.loginWarning(hardExpires: info.hardExpires, now: Date().timeIntervalSince1970) {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(Theme.warn)
                }
            }
            Button(role: .destructive) {
                confirmLogout = true
            } label: {
                HStack {
                    Text(SettingsTexts.logoutButton)
                    if loggingOut {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(loggingOut)
        } header: {
            Text("Этот телефон")
        } footer: {
            Text("Список телефонов с доступом и отзыв доступа пока в веб-панели (раздел «Безопасность») и в боте командой /apps.")
        }
        .listRowBackground(Theme.card)
    }

    private var linksSection: some View {
        Section {
            Link(destination: Links.webPanel) {
                Label("Веб-панель", systemImage: "globe")
            }
            Link(destination: luciURL) {
                Label("LuCI роутера", systemImage: "wifi.router")
            }
            if let bot = botURL {
                Link(destination: bot) {
                    Label("Telegram-бот", systemImage: "paperplane")
                }
            }
        } header: {
            Text("Ссылки")
        } footer: {
            Text("Открываются в Safari, вход там свой.")
        }
        .listRowBackground(Theme.card)
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Версия", value: AppConfig.appString)
            if let built = AppConfig.buildDate {
                LabeledContent("Дата сборки", value: AppFormat.dateDMY(built))
                Text("Сборка TestFlight работает до \(AppFormat.dateDMY(built + Int(ExpiryNotice.buildLifetime)))")
                    .foregroundStyle(buildWarning == nil ? Theme.text : Theme.warn)
                if let warning = buildWarning {
                    Label(warning, systemImage: "hourglass")
                        .foregroundStyle(Theme.warn)
                }
            }
        } header: {
            Text("О приложении")
        } footer: {
            Text(SettingsTexts.timeZoneNote)
        }
        .listRowBackground(Theme.card)
    }

    // MARK: - Values

    private var deviceName: String {
        if let name = store.me?.device.name, !name.isEmpty {
            return name
        }
        return "—"
    }

    private var luciURL: URL {
        if let site = store.dayData?.site, let url = Links.luci(site) {
            return url
        }
        return AppConfig.fallbackLuciURL
    }

    private var botURL: URL? {
        guard let site = store.dayData?.site else {
            return nil
        }
        return Links.bot(site)
    }

    private var buildWarning: String? {
        guard let built = AppConfig.buildDate else {
            return nil
        }
        return ExpiryNotice.buildWarning(buildDate: built, now: Date().timeIntervalSince1970)
    }

    // MARK: - Actions

    /// Turning the lock on needs a successful Face ID first; turning it off does not.
    private func lockToggleChanged(_ newValue: Bool) {
        if newValue == lockOnOpen {
            return
        }
        if !newValue {
            lockOnOpen = false
            return
        }
        authBusy = true
        Task {
            let ok = await BiometricGate.authenticate(reason: SettingsTexts.unlockReason)
            authBusy = false
            if ok {
                lockOnOpen = true
            } else {
                lockToggle = false
            }
        }
    }

    /// Turning Face ID for dangerous actions off is itself protected by Face ID.
    private func dangerToggleChanged(_ newValue: Bool) {
        if newValue == biometricForDanger {
            return
        }
        if newValue {
            biometricForDanger = true
            return
        }
        authBusy = true
        Task {
            let ok = await BiometricGate.confirmDangerous(reason: "Отключить Face ID для опасных действий")
            authBusy = false
            if ok {
                biometricForDanger = false
            } else {
                dangerToggle = true
            }
        }
    }

    private func logout() {
        loggingOut = true
        Task {
            await store.logoutFromSettings()
            loggingOut = false
        }
    }
}
