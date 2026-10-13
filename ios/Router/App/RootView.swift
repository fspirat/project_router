import SwiftUI
import RouterCore

/// Login form / number screen / Summary, with the lock screen and the privacy cover on top.
struct RootView: View {
    @Environment(RouterStore.self) var store
    @Environment(AppLock.self) var lock
    @Environment(\.scenePhase) var scenePhase
    @AppStorage(AppSettings.lockOnOpenKey) var lockOnOpen = false

    var body: some View {
        @Bindable var bindableStore = store
        ZStack {
            Theme.bg
                .ignoresSafeArea()
            content
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
            SummaryView()
        case .waitingForBot:
            LoginCodeView()
        case .loggedOut:
            LoginView()
        }
    }

    private func handle(_ phase: ScenePhase) {
        switch phase {
        case .background:
            lock.didEnterBackground(loggedIn: store.isLoggedIn)
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
