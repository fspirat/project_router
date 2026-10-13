import SwiftUI
import RouterCore

/// Login form / number screen / the tabs, with the lock screen and the (optional) privacy cover on top.
struct RootView: View {
    @Environment(RouterStore.self) var store
    @Environment(AppLock.self) var lock
    @Environment(\.scenePhase) var scenePhase
    @AppStorage(AppSettings.lockOnOpenKey) var lockOnOpen = false
    @AppStorage(AppSettings.hideInSwitcherKey) var hideInSwitcher = false

    var body: some View {
        @Bindable var bindableStore = store
        ZStack {
            AppBackground()
            content
                // VoiceOver must not reach (or activate) the data under the lock screen.
                .accessibilityHidden(lock.isLocked && store.isLoggedIn)
        }
        .overlay {
            if lock.isLocked && store.isLoggedIn {
                LockView()
            }
        }
        .privacyCover(includeLock: false)
        .onChange(of: scenePhase, initial: true) { _, phase in
            handle(phase)
        }
        .onChange(of: store.session) { _, session in
            if session != .loggedIn {
                lock.reset()
            }
        }
        .onChange(of: lock.isLocked) { _, locked in
            if locked {
                store.dismissPresentations()
            }
        }
        .alert(LoginTexts.offerFaceID, isPresented: $bindableStore.offerFaceID) {
            Button("Включить") {
                enableLock()
            }
            Button("Не сейчас", role: .cancel) {}
        } message: {
            Text("Приложение будет спрашивать \(BiometricGate.methodName) при открытии. Изменить можно в Настройках.")
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.session {
        case .loggedIn:
            MainTabView()
        case .waitingForBot:
            LoginCodeView()
        case .loggedOut:
            LoginView()
        }
    }

    private func handle(_ phase: ScenePhase) {
        if phase != .active && hideInSwitcher {
            // System dialogs are drawn above the in-view privacy cover: close the «Проверить?» dialog
            // (it tells the VPN state) before the app-switcher snapshot. Without the cover (default) the
            // snapshot shows the screen anyway, so nothing is closed (contract-stage4 §1.3).
            store.showPingPreDialog = false
        }
        switch phase {
        case .background:
            // Locks here only with «Сразу» + «Скрывать в переключателе приложений» (AppLock).
            lock.didEnterBackground(loggedIn: store.isLoggedIn)
        case .inactive:
            // On the way back from the background: lock before the scene becomes active.
            lock.willEnterForeground(loggedIn: store.isLoggedIn)
        case .active:
            lock.didBecomeActive(loggedIn: store.isLoggedIn)
        default:
            break
        }
    }

    /// «Включить» in the offer after login: only after a successful Face ID.
    private func enableLock() {
        Task {
            let ok = await BiometricGate.authenticate(reason: SettingsTexts.unlockReason)
            if ok {
                lockOnOpen = true
            }
        }
    }
}
