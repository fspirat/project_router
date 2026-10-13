import SwiftUI
import RouterCore

/// «Журнал входов» (pushed from Settings; contract-stage4 §5.6.4): «Входы в приложение» (`logins`, last 20)
/// and «Все входы и выходы» (`auth_log`, last ≤ 30), newest first, times in Samara. Read-only.
struct LoginJournalView: View {
    @Environment(RouterStore.self) private var store
    @State private var now = Date()

    var body: some View {
        Form {
            Section {
                rows(store.accessAppLogins(now: now), empty: "Входов в приложение пока не было.")
            } header: {
                Text(AccessTexts.appLoginsTitle)
            }
            .listRowBackground(Theme.card)

            Section {
                rows(store.accessAuthLog(now: now), empty: "Записей пока нет.")
            } header: {
                Text(AccessTexts.authLogTitle)
            } footer: {
                Text(SettingsTexts.timeZoneNote)
            }
            .listRowBackground(Theme.card)
        }
        .sheetFormBackground()
        .refreshable { [store, kinds = store.settingsKinds] in
            await store.refresh(kinds)
        }
        .navigationTitle(AccessTexts.loginsTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            now = Date()
        }
    }

    @ViewBuilder
    private func rows(_ list: [AccessLogRow]?, empty: String) -> some View {
        if let list = list {
            if list.isEmpty {
                EmptyStateView(title: empty, systemImage: "tray")
            } else {
                ForEach(list) { row in
                    AccessLogRowView(row: row)
                }
            }
        } else if let error = store.readError(.devices) {
            AccessReadErrorRow(text: error)
        } else {
            AccessLoadingRow()
        }
    }
}

/// One journal line: level icon, the event words, «время · имя · IP» below.
/// The level is also said as a word for VoiceOver (colour alone is not enough).
struct AccessLogRowView: View {
    let row: AccessLogRow

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.dot(row.tone))
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.text)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(metaLine)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Theme.dim)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var metaLine: String {
        var parts = [row.time]
        if !row.name.isEmpty {
            parts.append(row.name)
        }
        if let ip = row.ipText {
            parts.append(ip)
        }
        return parts.joined(separator: " · ")
    }

    /// Neutral rows (pending, expired…) get a quiet clock instead of the «checking» symbol.
    private var symbol: String {
        switch row.tone {
        case .neutral:
            return "circle.dashed"
        default:
            return Theme.symbol(row.tone)
        }
    }

    private var levelWord: String? {
        switch row.tone {
        case .ok:
            return "успешно"
        case .warn:
            return "внимание"
        case .err:
            return "тревога"
        case .info, .neutral:
            return nil
        }
    }

    private var accessibilityText: String {
        var parts: [String] = []
        if let word = levelWord {
            parts.append(word)
        }
        parts.append(row.text)
        parts.append(metaLine)
        return parts.joined(separator: ", ")
    }
}
