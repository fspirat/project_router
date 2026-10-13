import SwiftUI
import RouterCore

/// «Доступ к роутеру» (contract-stage4 §5.6.3–5.6.4, `GET /devices`): phones with the app (this one marked,
/// the others with «Отозвать»), a row to the web-panel sessions («Браузеры») and to «Журнал входов».
/// `onRevoke` asks the parent to show the app dialog before anything is sent.
struct SettingsAccessSection: View {
    @Environment(RouterStore.self) private var store
    let now: Date
    let onRevoke: (PhoneRow) -> Void

    var body: some View {
        Section {
            phones
            NavigationLink {
                BrowserSessionsView()
            } label: {
                browsersLabel
            }
            NavigationLink {
                LoginJournalView()
            } label: {
                Label(AccessTexts.loginsTitle, systemImage: "list.bullet.rectangle")
            }
        } header: {
            Text(AccessTexts.title)
        } footer: {
            Text("Не больше 10 телефонов: на одиннадцатом вход не пройдёт, пока не отзовёшь лишний. «Отозвать» — приложение на том телефоне сразу выйдет.")
        }
        .listRowBackground(Theme.card)
    }

    @ViewBuilder
    private var phones: some View {
        if let rows = store.accessPhones(now: now) {
            if rows.isEmpty {
                EmptyStateView(title: AccessTexts.emptyPhones, systemImage: "iphone")
            } else {
                ForEach(rows) { row in
                    PhoneAccessRow(
                        row: row,
                        isBusy: store.isRevoking(phone: row.id),
                        canRevoke: canRevoke(row)
                    ) {
                        onRevoke(row)
                    }
                }
            }
            if let error = store.readError(.devices) {
                AccessReadErrorRow(text: error)
            }
        } else if let error = store.readError(.devices) {
            AccessReadErrorRow(text: error)
        } else {
            AccessLoadingRow()
        }
    }

    private var browsersLabel: some View {
        HStack {
            Label(AccessTexts.browsersTitle, systemImage: "macwindow")
            Spacer(minLength: 8)
            if let rows = store.accessBrowsers(now: now) {
                Text(rows.isEmpty ? "нет" : Fmt.count(rows.count, "сессия", "сессии", "сессий"))
                    .monospacedDigit()
                    .foregroundStyle(Theme.dim)
            }
        }
    }

    private func canRevoke(_ row: PhoneRow) -> Bool {
        guard let action = row.revokeAction else {
            return false
        }
        return store.canPerform(action)
    }
}

/// One phone: name (+ «этот телефон»), model · iOS · app version, «был в сети …» · IP, «вход до …»
/// (red with an icon when less than 7 days are left), and «Отозвать» for the other phones.
struct PhoneAccessRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let row: PhoneRow
    let isBusy: Bool
    let canRevoke: Bool
    let onRevoke: () -> Void

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
        layout {
            info
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 0)
            }
            if !row.isCurrent && row.revokeAction != nil {
                revokeButton
            }
        }
        .padding(.vertical, 2)
    }

    private var info: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "iphone")
                .font(.title3)
                .foregroundStyle(row.isCurrent ? Theme.acc : Theme.dim)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(row.name)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    if let tag = row.tag {
                        ToneChip(text: tag, tone: .ok)
                    }
                }
                if !row.details.isEmpty {
                    Text(row.details)
                        .font(.footnote)
                        .foregroundStyle(Theme.dim)
                }
                Text(metaLine)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Theme.dim)
                expires
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var expires: some View {
        if row.expiresSoon {
            Label(row.expiresText, systemImage: "exclamationmark.circle.fill")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.err)
        } else {
            Text(row.expiresText)
                .font(.footnote)
                .foregroundStyle(Theme.dim)
        }
    }

    private var revokeButton: some View {
        Button(role: .destructive, action: onRevoke) {
            if isBusy {
                ProgressView()
            } else {
                Text(AccessTexts.revokeButton)
                    .font(.subheadline.weight(.semibold))
            }
        }
        // Borderless: in a Form row only this control reacts, not the whole row.
        .buttonStyle(.borderless)
        .tint(Theme.err)
        .disabled(!canRevoke || isBusy)
        .accessibilityLabel(AccessTexts.revokeButton + " доступ «" + row.name + "»")
    }

    private var metaLine: String {
        var parts = [row.seenText]
        if let ip = row.ipText {
            parts.append(ip)
        }
        return parts.joined(separator: " · ")
    }

    private var accessibilityText: String {
        var parts = [row.name]
        if let tag = row.tag {
            parts.append(tag)
        }
        if !row.details.isEmpty {
            parts.append(row.details)
        }
        parts.append(metaLine)
        parts.append(row.expiresSoon ? row.expiresText + ", скоро истекает" : row.expiresText)
        return parts.joined(separator: ", ")
    }
}

/// `/devices` not loaded yet: a spinner; after 15 s a «Повторить» read (never an action).
struct AccessLoadingRow: View {
    @Environment(RouterStore.self) private var store
    @State private var slow = false
    @State private var retrying = false

    var body: some View {
        HStack(spacing: 10) {
            if slow && !retrying {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(Theme.dim)
                    .accessibilityHidden(true)
                Text("Список ещё не загрузился.")
                    .foregroundStyle(Theme.dim)
                Spacer(minLength: 8)
                Button("Повторить") {
                    retry()
                }
                .buttonStyle(.borderless)
                .tint(Theme.acc)
            } else {
                ProgressView()
                Text("Загружаю список…")
                    .foregroundStyle(Theme.dim)
            }
        }
        .task {
            do {
                try await Task.sleep(nanoseconds: 15_000_000_000)
            } catch {
                return
            }
            slow = true
        }
    }

    private func retry() {
        retrying = true
        Task { @MainActor in
            await store.refresh([.devices])
            retrying = false
        }
    }
}

/// A failed `/devices` read while an older list is shown (or nothing could be loaded).
struct AccessReadErrorRow: View {
    let text: String

    var body: some View {
        Label(text, systemImage: Theme.symbol(.warn))
            .font(.footnote)
            .foregroundStyle(Theme.warn)
            .accessibilityLabel("Внимание: " + text)
    }
}
