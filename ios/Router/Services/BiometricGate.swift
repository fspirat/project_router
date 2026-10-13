import Foundation
import LocalAuthentication

/// Face ID / Touch ID with the passcode fallback (`.deviceOwnerAuthentication`, contract §7.8).
enum BiometricGate {
    enum Availability {
        /// Face ID, Touch ID or at least the passcode can be asked.
        case available(LABiometryType)
        /// The iPhone has no passcode at all: nothing can be asked, so the app does not lock.
        case noPasscode
        case unavailable
    }

    static func availability() -> Availability {
        let context = LAContext()
        var error: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            return .available(context.biometryType)
        }
        if let e = error, e.code == LAError.Code.passcodeNotSet.rawValue {
            return .noPasscode
        }
        return .unavailable
    }

    static var canAuthenticate: Bool {
        if case .available = availability() {
            return true
        }
        return false
    }

    /// «Face ID», «Touch ID» or «код-пароль» for texts.
    static var methodName: String {
        switch availability() {
        case .available(let type):
            switch type {
            case .faceID:
                return "Face ID"
            case .touchID:
                return "Touch ID"
            default:
                return "код-пароль"
            }
        case .noPasscode, .unavailable:
            return "код-пароль"
        }
    }

    /// Asks Face ID (or the passcode). `false` when cancelled, failed or impossible.
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            return false
        }
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { success, _ in
                continuation.resume(returning: success)
            }
        }
    }

    /// Before a dangerous action (`danger == critical`). Like `authenticate`, but when the iPhone
    /// has no passcode at all the action is allowed: the phone itself is unprotected then, and the
    /// app does not lock either. Any other failure to ask → `false` (cancel silently).
    static func confirmDangerous(reason: String) async -> Bool {
        switch availability() {
        case .available:
            return await authenticate(reason: reason)
        case .noPasscode:
            return true
        case .unavailable:
            return false
        }
    }
}
