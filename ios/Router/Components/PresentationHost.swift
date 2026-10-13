import SwiftUI
import RouterCore

/// A place that can show the toast and present the 428 confirm sheet: each tab root and each app sheet.
/// Only the topmost visible host shows them, so a confirm started inside a sheet (server card, Settings)
/// opens on top of that sheet, and a toast is never hidden under a sheet.
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
                if isTop {
                    ToastOverlay()
                }
            }
            .sheet(item: isTop ? $bindableStore.confirmSelection : .constant(nil)) { value in
                ConfirmSheet(pending: value)
                    .privacyCover(includeLock: true)
                    .environment(store)
                    .environment(lock)
                    .preferredColorScheme(theme.colorScheme)
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
