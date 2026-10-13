import SwiftUI

/// Opaque cover (logo on `bg`) shown whenever the scene is not active, so the app switcher
/// never shows router data (contract §7.8). Sheets get it too, plus while the app is locked.
struct PrivacyCoverModifier: ViewModifier {
    @Environment(\.scenePhase) var scenePhase
    @Environment(AppLock.self) var lock
    let includeLock: Bool

    func body(content: Content) -> some View {
        content
            .overlay {
                if scenePhase != .active || (includeLock && lock.isLocked) {
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
    }
}

extension View {
    func privacyCover(includeLock: Bool) -> some View {
        modifier(PrivacyCoverModifier(includeLock: includeLock))
    }

    /// Everything a sheet needs: the shared objects, the theme and the privacy cover.
    /// (Sheets are separate presentations: the root overlay does not cover them.)
    func sheetChrome(store: RouterStore, lock: AppLock, theme: ThemeChoice) -> some View {
        self
            .privacyCover(includeLock: true)
            .environment(store)
            .environment(lock)
            .preferredColorScheme(theme.colorScheme)
    }
}
