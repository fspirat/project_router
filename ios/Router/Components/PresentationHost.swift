import SwiftUI
import RouterCore

/// A place that can show the toast, the «Проверить?» pre-dialog and the 428 confirm sheet: each tab root and
/// each app sheet. Only the topmost visible host shows them, so a confirm started inside a sheet (server card,
/// Settings) opens on top of that sheet, and a toast is never hidden under a sheet.
struct PresentationHostEntry: Equatable {
    let id: UUID
    let isSheet: Bool
}

struct PresentationHostModifier: ViewModifier {
    @Environment(RouterStore.self) private var store
    @Environment(AppLock.self) private var lock
    @AppStorage(AppSettings.themeKey) private var theme: ThemeChoice = .system
    let isSheet: Bool
    @State private var hostID = UUID()

    func body(content: Content) -> some View {
        @Bindable var bindableStore = store
        let isTop = store.hostStack.last?.id == hostID
        content
            .overlay(alignment: .bottom) {
                // While a 428 sheet is up the toast shows on that sheet (it would be hidden under it here).
                if isTop && store.pendingConfirm == nil {
                    ToastOverlay()
                }
            }
            .sheet(
                item: isTop ? $bindableStore.confirmSelection : .constant(nil),
                onDismiss: {
                    store.confirmSheetDidDismiss()
                }
            ) { value in
                ConfirmSheet(pending: value)
                    .overlay(alignment: .bottom) {
                        // Exactly one toast overlay at a time: here while the 428 is pending, on the host after.
                        if store.pendingConfirm != nil {
                            ToastOverlay()
                        }
                    }
                    .onAppear {
                        store.confirmSheetShown = true
                    }
                    .privacyCover(includeLock: true)
                    .environment(store)
                    .environment(lock)
                    .preferredColorScheme(theme.colorScheme)
            }
            // The stage 3 «Проверить?» pre-dialog, on whichever screen asked (Summary «Проверить» or
            // VPN «Проверить все серверы»): only the topmost host binds it, so it never shows twice.
            .confirmationDialog(
                PingPreDialog.title,
                isPresented: isTop ? $bindableStore.showPingPreDialog : .constant(false),
                titleVisibility: .visible
            ) {
                Button(PingPreDialog.confirm) {
                    store.startPing()
                }
                Button(PingPreDialog.cancel, role: .cancel) {}
            } message: {
                Text(PingPreDialog.text)
            }
            .onAppear {
                store.pushHost(hostID, isSheet: isSheet)
            }
            .onDisappear {
                store.popHost(hostID)
            }
    }
}

extension View {
    /// Toasts + the 428 confirm sheet for this part of the UI. The shell applies it to every tab root;
    /// `sheetChrome` / `appSheet` apply it to sheets. Screens never need to call it themselves.
    func presentationHost(isSheet: Bool) -> some View {
        modifier(PresentationHostModifier(isSheet: isSheet))
    }
}

extension RouterStore {
    func pushHost(_ id: UUID, isSheet: Bool) {
        hostStack.removeAll { $0.id == id }
        hostStack.append(PresentationHostEntry(id: id, isSheet: isSheet))
    }

    func popHost(_ id: UUID) {
        hostStack.removeAll { $0.id == id }
    }

    /// The confirm sheet binding: swiping the sheet away (nil) is «Отмена».
    var confirmSelection: PendingConfirm? {
        get {
            return pendingConfirm
        }
        set {
            if newValue == nil {
                cancelPending()
            } else {
                pendingConfirm = newValue
            }
        }
    }

    /// An app sheet (Settings or a screen's `appSheet`) is on top: `/net` pauses under it.
    var isSheetPresented: Bool {
        return isSettingsPresented || (hostStack.last?.isSheet ?? false)
    }
}
