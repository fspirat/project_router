import SwiftUI
import RouterCore

// «Этот телефон», «Тема», «Ссылки», «О приложении» (contract-stage4 §5.6.2, §5.6.6 = stage 3 §7.9).

/// «Этот телефон» (`/me`): name, «Вход до …», «Не дольше …», the 14-day warning.
struct SettingsPhoneSection: View {
    @Environment(RouterStore.self) private var store

    var body: some View {
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
        } header: {
            Text("Этот телефон")
        }
        .listRowBackground(Theme.card)
    }

    private var deviceName: String {
        if let name = store.me?.device.name, !name.isEmpty {
            return name
        }
        return "—"
    }
}

/// «Тема»: Как в системе / Светлая / Тёмная (system menu picker; glass on iOS 26).
struct SettingsThemeSection: View {
    @AppStorage(AppSettings.themeKey) private var theme: ThemeChoice = .system

    var body: some View {
        Section {
            Picker(selection: $theme) {
                ForEach(ThemeChoice.allCases) { choice in
                    Text(choice.title).tag(choice)
                }
            } label: {
                Label("Тема", systemImage: "circle.lefthalf.filled")
            }
            .pickerStyle(.menu)
            .tint(Theme.dim)
        } header: {
            Text("Оформление")
        }
        .listRowBackground(Theme.card)
    }
}

/// «Ссылки»: web panel, LuCI (`site.luci`, validated) and the bot (`site.bot`, validated), opened in Safari.
struct SettingsLinksSection: View {
    @Environment(RouterStore.self) private var store

    var body: some View {
        Section {
            Link(destination: Links.webPanel) {
                LinkRow(title: "Веб-панель", caption: webPanelCaption, systemImage: "globe")
            }
            if let luci = luciURL {
                Link(destination: luci) {
                    LinkRow(title: "LuCI роутера", caption: SettingsTexts.luciCaption, systemImage: "wifi.router")
                }
            }
            if let bot = botURL {
                Link(destination: bot) {
                    LinkRow(title: "Telegram-бот", caption: "@" + (store.latestData?.site.bot ?? ""), systemImage: "paperplane")
                }
            }
        } header: {
            Text("Ссылки")
        } footer: {
            Text("Открываются в Safari, вход там свой.")
        }
        .listRowBackground(Theme.card)
    }

    /// «fspirat.xyz/router/».
    private var webPanelCaption: String {
        return (Links.webPanel.host ?? "") + Links.webPanel.path
    }

    /// Only a `data.site.luci` that passes validation, like the web panel.
    private var luciURL: URL? {
        guard let site = store.latestData?.site else {
            return nil
        }
        return Links.luci(site)
    }

    private var botURL: URL? {
        guard let site = store.latestData?.site else {
            return nil
        }
        return Links.bot(site)
    }
}

/// One link row: icon, title, a grey caption, the «opens outside» arrow.
private struct LinkRow: View {
    let title: String
    let caption: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(Theme.acc)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(Theme.text)
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(Theme.dim)
            }
            Spacer(minLength: 8)
            Image(systemName: "arrow.up.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.dim)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(caption == SettingsTexts.luciCaption ? caption : "Откроется в Safari")
        .accessibilityAddTraits(.isLink)
    }
}

/// «О приложении»: version (build), and the build date + expiry only when CI wrote one (TestFlight builds).
struct SettingsAboutSection: View {
    var body: some View {
        Section {
            LabeledContent("Версия", value: AppConfig.appString)
            if let built = AppConfig.buildDate {
                LabeledContent("Дата сборки", value: AppFormat.dateDMY(built))
                Text(ExpiryNotice.buildValidUntil(buildDate: built))
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

    private var buildWarning: String? {
        guard let built = AppConfig.buildDate else {
            return nil
        }
        return ExpiryNotice.buildWarning(buildDate: built, now: Date().timeIntervalSince1970)
    }
}
