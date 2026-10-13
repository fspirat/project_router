import SwiftUI

@main
struct RouterApp: App {
    @State private var store: RouterStore
    @State private var lock: AppLock
    @AppStorage(AppSettings.themeKey) private var theme: ThemeChoice = .system

    init() {
        let initialStore = RouterStore()
        let lockAtLaunch = AppLock.shouldLock(loggedIn: initialStore.isLoggedIn)
        _store = State(initialValue: initialStore)
        _lock = State(initialValue: AppLock(lockAtLaunch: lockAtLaunch))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(lock)
                .preferredColorScheme(theme.colorScheme)
        }
    }
}
