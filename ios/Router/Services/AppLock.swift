import Foundation
import Observation
import RouterCore

/// App lock with Face ID / passcode (contract §7.8).
///
/// - Locks on a cold start and when the app comes back after more than «Блокировать» seconds in the
///   background, if «Face ID при открытии» is on and the iPhone can ask (has a passcode).
/// - With «Сразу» the lock is set already when the app goes to the background, so nothing flashes.
/// - Asks automatically once per lock; after «Отмена» the lock screen shows a button.
///   (Face ID itself makes the app inactive for a moment; that never locks or re-asks.)
@Observable
@MainActor
final class AppLock {
    var isLocked: Bool = false
    var isAuthenticating: Bool = false
    var lastAttemptFailed: Bool = false

    @ObservationIgnored private var backgroundedAt: Date?
    @ObservationIgnored private var promptPending: Bool = false

    init(lockAtLaunch: Bool) {
        isLocked = lockAtLaunch
        promptPending = lockAtLaunch
    }

    /// Lock is on in Settings, the user is logged in and the iPhone can ask.
    nonisolated static func shouldLock(loggedIn: Bool) -> Bool {
        return loggedIn && AppSettings.lockOnOpen && BiometricGate.canAuthenticate
    }

    func didEnterBackground(loggedIn: Bool) {
        backgroundedAt = Date()
        if !isLocked && AppSettings.lockDelay <= 0 && AppLock.shouldLock(loggedIn: loggedIn) {
            engage()
        }
    }

    func didBecomeActive(loggedIn: Bool) {
        guard loggedIn else {
            reset()
            return
        }
        if let since = backgroundedAt {
            backgroundedAt = nil
            let away = Date().timeIntervalSince(since)
            if !isLocked && away >= Double(AppSettings.lockDelay) && AppLock.shouldLock(loggedIn: loggedIn) {
                engage()
            }
        }
        if isLocked && promptPending && !isAuthenticating {
            promptPending = false
            Task {
                await self.unlock()
            }
        }
    }

    /// Face ID / passcode; unlocks on success.
    func unlock() async {
        guard isLocked, !isAuthenticating else {
            return
        }
        if !BiometricGate.canAuthenticate {
            // The passcode was removed meanwhile: the app does not lock without one.
            isLocked = false
            lastAttemptFailed = false
            return
        }
        isAuthenticating = true
        let ok = await BiometricGate.authenticate(reason: SettingsTexts.unlockReason)
        isAuthenticating = false
        if ok {
            isLocked = false
            lastAttemptFailed = false
        } else {
            lastAttemptFailed = true
        }
    }

    /// Logged out: nothing to protect.
    func reset() {
        isLocked = false
        promptPending = false
        lastAttemptFailed = false
        backgroundedAt = nil
    }

    private func engage() {
        isLocked = true
        promptPending = true
        lastAttemptFailed = false
    }
}
