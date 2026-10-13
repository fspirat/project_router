import Foundation
import UIKit

/// `@AppStorage` keys, and plain reads of the same values for code outside views.
/// These are settings, not secrets.
enum AppSettings {
    /// "system" / "light" / "dark" (`ThemeChoice`).
    static let themeKey = "theme"
    /// Face ID when opening the app. Off until the user accepts the offer after login.
    static let lockOnOpenKey = "lockOnOpen"
    /// Seconds in the background before the lock: 0 / 60 / 300.
    static let lockDelayKey = "lockDelay"
    /// Face ID before `danger == critical` actions (reboot). Default on.
    static let biometricForDangerKey = "biometricForDanger"
    /// Non-secret `SessionInfo` (device id, expiry dates) next to the Keychain token.
    static let sessionInfoKey = "sessionInfo"
    /// Set on the first launch of an install. Missing → a fresh (re)install: a Keychain token left by
    /// the previous install is deleted and revoked (`RouterStore.init`).
    static let installMarkerKey = "installMarker"

    static let lockDelayOptions: [Int] = [0, 60, 300]

    static var lockOnOpen: Bool {
        return UserDefaults.standard.object(forKey: lockOnOpenKey) as? Bool ?? false
    }

    static var lockDelay: Int {
        let value = UserDefaults.standard.object(forKey: lockDelayKey) as? Int ?? 0
        return max(0, value)
    }

    static var biometricForDanger: Bool {
        return UserDefaults.standard.object(forKey: biometricForDangerKey) as? Bool ?? true
    }
}

/// Values for the login `device` object (contract §2.1). RouterCore sanitizes them again.
enum DeviceIdentity {
    /// Hardware identifier from `utsname.machine`, e.g. "iPhone15,2".
    static var model: String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"], !simulated.isEmpty {
            return simulated
        }
        var info = utsname()
        _ = uname(&info)
        let machine = withUnsafeBytes(of: &info.machine) { raw -> String in
            let bytes = raw.prefix(while: { $0 != 0 })
            return String(decoding: bytes, as: UTF8.self)
        }
        return machine
    }

    /// "iOS 18.1".
    @MainActor
    static var osString: String {
        return "iOS " + UIDevice.current.systemVersion
    }
}
