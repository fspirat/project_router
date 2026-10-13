import SwiftUI
import RouterCore

/// «Браузеры» (pushed from Settings; contract-stage4 §5.6.3): live web-panel sessions from `/devices`
/// with «Закрыть» → app dialog → `POST /devices/revoke {"web_ref"}`. Remembered browsers stay remembered
/// (only the session closes). Works offline (server-only).
struct BrowserSessionsView: View {
    @Environment(RouterStore.self) private var store
    @State private var now = Date()
    @State private var closeTarget: BrowserRow? = nil

    var body: some View {
        Form {
            Section {
                content
            } footer: {
                Text("Закрытая сессия выйдет из веб-панели. Запомненный браузер при следующем входе код из Telegram не спросит.")
            }
            .listRowBackground(Theme.card)
        }
        .sheetFormBackground()
        .refreshable { [store, kinds = store.settingsKinds] in
            await store.refresh(kinds)
        }
        .navigationTitle(AccessTexts.browsersTitle)
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            AccessTexts.webCloseTitle,
            isPresented: dialogShown,
            presenting: closeTarget
        ) { row in
            Button(AccessTexts.webCloseButton, role: .destructive) {
                store.closeWebSession(row)
            }
            Button("Отмена", role: .cancel) {}
        } message: { row in
            Text(AccessTexts.webCloseText(ip: row.ip.isEmpty ? "—" : row.ip))
        }
        .onAppear {
            now = Date()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let rows = store.accessBrowsers(now: now) {
            if rows.isEmpty {
                EmptyStateView(title: AccessTexts.emptyWeb, systemImage: "macwindow")
            } else {
                ForEach(rows) { row in
                    BrowserSessionRow(
                        row: row,
                        isBusy: store.isRevoking(web: row.id),
                        canClose: store.canPerform(row.revokeAction)
                    ) {
                        closeTarget = row
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

    private var dialogShown: Binding<Bool> {
        return Binding(
            get: { closeTarget != nil },
            set: { shown in
                if !shown {
                    closeTarget = nil
                }
            }
        )
    }
}

/// One web session: «Chrome · Windows», «IP …» · «был …», «вход …», and «Закрыть».
struct BrowserSessionRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let row: BrowserRow
    let isBusy: Bool
    let canClose: Bool
    let onClose: () -> Void

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 8))
        layout {
            info
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 0)
            }
            closeButton
        }
        .padding(.vertical, 2)
    }

    private var info: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(Theme.dim)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(row.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Text(metaLine)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Theme.dim)
                Text(row.createdText)
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Theme.dim)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([row.title, metaLine, row.createdText].joined(separator: ", "))
    }

    private var closeButton: some View {
        Button(role: .destructive, action: onClose) {
            if isBusy {
                ProgressView()
            } else {
                Text(AccessTexts.webCloseButton)
                    .font(.subheadline.weight(.semibold))
            }
        }
        .buttonStyle(.borderless)
        .tint(Theme.err)
        .disabled(!canClose || isBusy)
        .accessibilityLabel("Закрыть сессию «" + row.title + "»")
    }

    private var metaLine: String {
        var parts: [String] = []
        if let ip = row.ipText {
            parts.append(ip)
        }
        parts.append(row.seenText)
        return parts.joined(separator: " · ")
    }

    private var symbol: String {
        let t = row.title
        if t.contains("iPhone") || t.contains("Android") {
            return "iphone"
        }
        if t.contains("iPad") {
            return "ipad"
        }
        return "macwindow"
    }
}
