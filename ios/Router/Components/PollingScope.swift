import SwiftUI
import RouterCore

/// Declares the reads a screen (or a card, or a sheet) needs while it is on display (contract-stage4 §4).
/// The store polls the union of all visible scopes while the app is active and unlocked; kinds that are due
/// are read as soon as the scope appears. Changing `kinds` (e.g. another chart range) updates the scope.
///
/// Apply it to the root of every screen and of every pushed detail view or sheet that needs data:
/// a pushed view hides its parent (its scope disappears), a sheet does not.
struct PollingScopeModifier: ViewModifier {
    @Environment(RouterStore.self) private var store
    let kinds: Set<ReadKind>
    @State private var scopeID = UUID()
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                isVisible = true
                store.setScope(scopeID, kinds: kinds)
            }
            .onDisappear {
                isVisible = false
                store.removeScope(scopeID)
            }
            .onChange(of: kinds) { _, newKinds in
                if isVisible {
                    store.setScope(scopeID, kinds: newKinds)
                }
            }
    }
}

extension View {
    /// `.pollingScope([.status, .data(.week), .vds])`.
    func pollingScope(_ kinds: Set<ReadKind>) -> some View {
        modifier(PollingScopeModifier(kinds: kinds))
    }
}
