import SwiftUI

/// Opaque cover (logo on `bg`).
///
/// Stage 4 (contract-stage4 §1.3): the app-switcher snapshot shows the real screen by default. The cover is
/// drawn while the scene is not active only when Settings «Скрывать в переключателе приложений» is on.
/// Sheets (`includeLock: true`) show the lock screen while the app is locked (a sheet left open stays up
/// under the lock, contract-stage4 §1.3), so «Разблокировать» is reachable without swiping the sheet away.
///
/// Whatever is covered is also taken out of the accessibility tree and stops taking touches: an overlay
/// alone hides the content only visually, and VoiceOver could still read and activate the sheet's controls
/// while the app is locked.
struct PrivacyCoverModifier: ViewModifier {
    @Environment(\.scenePhase) var scenePhase
    @Environment(AppLock.self) var lock
    @AppStorage(AppSettings.hideInSwitcherKey) var hideInSwitcher = false
    let includeLock: Bool

    private var lockedHere: Bool {
        return includeLock && lock.isLocked
    }

    private var covered: Bool {
        return (hideInSwitcher && scenePhase != .active) || lockedHere
    }

    func body(content: Content) -> some View {
        content
            .accessibilityHidden(covered)
            .allowsHitTesting(!lockedHere)
            .overlay {
                if lockedHere {
                    LockView()
                } else if covered {
                    PrivacyCoverView()
                }
            }
    }
}

struct PrivacyCoverView: View {
    var body: some View {
        ZStack {
            Theme.bg
                .ignoresSafeArea()
            LogoView(size: 88)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Роутер")
        .accessibilityAddTraits(.isModal)
    }
}

extension View {
    func privacyCover(includeLock: Bool) -> some View {
        modifier(PrivacyCoverModifier(includeLock: includeLock))
    }

    /// Everything an app sheet needs: the shared objects, the theme, the privacy/lock cover, and a
    /// presentation host (toasts and 428 confirm sheets show on top of this sheet while it is open).
    /// (Sheets are separate presentations: the root overlays do not cover them.)
    /// Prefer `.appSheet(isPresented:)` / `.appSheet(item:)` on the presenting view — they apply this.
    /// The cover is outside the host, so the host's toast is covered too (never drawn above the logo or the
    /// lock screen).
    func sheetChrome(store: RouterStore, lock: AppLock, theme: ThemeChoice) -> some View {
        self
            .presentationHost(isSheet: true)
            .privacyCover(includeLock: true)
            .environment(store)
            .environment(lock)
            .preferredColorScheme(theme.colorScheme)
    }
}

// MARK: - App sheets

extension View {
    /// `.sheet(isPresented:)` with `sheetChrome` applied (store, lock, theme, cover, toast/confirm host).
    /// Use it for every sheet of the app (server card, device card, schedule, rename, revoke-all…).
    func appSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        modifier(AppSheetModifier(isPresented: isPresented, onDismiss: onDismiss, sheetContent: content))
    }

    /// `.sheet(item:)` with `sheetChrome` applied.
    func appSheet<Item: Identifiable, SheetContent: View>(
        item: Binding<Item?>,
        onDismiss: (() -> Void)? = nil,
        @ViewBuilder content: @escaping (Item) -> SheetContent
    ) -> some View {
        modifier(AppSheetItemModifier(item: item, onDismiss: onDismiss, sheetContent: content))
    }
}

struct AppSheetModifier<SheetContent: View>: ViewModifier {
    @Environment(RouterStore.self) private var store
    @Environment(AppLock.self) private var lock
    @AppStorage(AppSettings.themeKey) private var theme: ThemeChoice = .system
    @Binding var isPresented: Bool
    let onDismiss: (() -> Void)?
    let sheetContent: () -> SheetContent

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $isPresented, onDismiss: onDismiss) {
                sheetContent()
                    .sheetChrome(store: store, lock: lock, theme: theme)
            }
    }
}

struct AppSheetItemModifier<Item: Identifiable, SheetContent: View>: ViewModifier {
    @Environment(RouterStore.self) private var store
    @Environment(AppLock.self) private var lock
    @AppStorage(AppSettings.themeKey) private var theme: ThemeChoice = .system
    @Binding var item: Item?
    let onDismiss: (() -> Void)?
    let sheetContent: (Item) -> SheetContent

    func body(content: Content) -> some View {
        content
            .sheet(item: $item, onDismiss: onDismiss) { value in
                sheetContent(value)
                    .sheetChrome(store: store, lock: lock, theme: theme)
            }
    }
}
