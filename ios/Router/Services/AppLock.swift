import Foundation
import Observation
import RouterCore

/// App lock with Face ID / passcode (contract §7.8).
///
/// - Locks on a cold start and when the app comes back after more than «Блокировать» seconds in the
///   background, if «Face ID при открытии» is on and the iPhone can ask (has a passcode).
/// - With «Сразу» and «Скрывать в переключателе приложений» ON the lock is set already when the app goes
///   to the background, so nothing flashes and the switcher shows the lock screen (stage 3 behaviour).
/// - With the toggle OFF (default, contract-stage4 §1.3) the switcher must keep showing the data, so the lock
///   is never set at background: «Сразу» and the delays are decided on the way back while the scene is
///   still `.inactive` (polling off), so the data never shows or polls for a moment before the lock.
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
        // Only when the snapshot is hidden anyway; otherwise the lock screen would replace the data in the
        // app switcher (the owner's complaint). `willEnterForeground` engages it on return (away >= 0).
        if !isLocked && AppSettings.hideInSwitcher && AppSettings.lockDelay <= 0 && AppLock.shouldLock(loggedIn: loggedIn) {
            engage()
        }
    }

    /// Back from the background, still `.inactive`: decide the delayed lock before the scene is active.
    /// No-op on the way to the background and for Face ID / Control Center (never backgrounded). Idempotent.
    func willEnterForeground(loggedIn: Bool) {
        guard let since = backgroundedAt else {
            return
        }
        backgroundedAt = nil
        guard loggedIn else {
            return
        }
        let away = Date().timeIntervalSince(since)
        if !isLocked && away >= Double(AppSettings.lockDelay) && AppLock.shouldLock(loggedIn: loggedIn) {
            engage()
        }
    }

    func didBecomeActive(loggedIn: Bool) {
        guard loggedIn else {
            reset()
            return
        }
        // In case SwiftUI coalesced the `.inactive` step away.
        willEnterForeground(loggedIn: loggedIn)
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
