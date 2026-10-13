import SwiftUI
import RouterCore

/// «Журнал» tab root (contract-stage4 §5.5, plan §2): period 24 ч / 7 дн / 30 дн, level chips
/// Все / Ошибки / Внимание / Действия, search, rows grouped by Samara day.
/// The shell (TabRoot) gives the NavigationStack, title, gear, status pill, toasts and confirm sheets.
/// Read-only: nothing here starts a router action; pull-to-refresh only re-reads `/data`.
struct JournalView: View {
    @Environment(RouterStore.self) private var store
    /// UI state only (not router data), restored per scene.
    @SceneStorage("journalRange") private var range: DataRange = .day
    @SceneStorage("journalFilter") private var filter: JournalFilter = .all
    @State private var query = ""

    var body: some View {
        let kinds = store.journalKinds(range)
        ScreenScroll(refresh: kinds) {
            JournalContent(range: $range, filter: $filter, query: $query)
        }
        .searchable(text: $query, prompt: Text(JournalTexts.searchPrompt))
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .pollingScope(kinds)
        .onAppear {
            consumeLink()
        }
        .onChange(of: store.journalLink) { _, _ in
            consumeLink()
        }
    }

    /// «Все в журнале» from VPN: filter «Все», the same range, no search (contract-stage4 §5.1.5).
    private func consumeLink() {
        guard let link = store.journalLink else {
            return
        }
        range = link.range
        filter = .all
        query = ""
        store.journalLink = nil
    }
}
