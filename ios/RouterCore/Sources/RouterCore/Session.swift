import Foundation

/// Keychain item names for the token (contract §7.7). The Keychain code lives in the app.
public enum KeychainConfig {
    public static let service = "xyz.fspirat.router"
    public static let account = "device-token"
}

/// Non-secret facts about this phone's access. Store next to the token (Keychain or UserDefaults).
public struct SessionInfo: Codable, Equatable, Sendable {
    public var deviceID: String
    /// 90 days since the last use (the server extends it).
    public var expires: Int
    /// Login + 365 days.
    public var hardExpires: Int

    public init(deviceID: String, expires: Int, hardExpires: Int) {
        self.deviceID = deviceID
        self.expires = expires
        self.hardExpires = hardExpires
    }

    public init(approved: ApprovedLogin) {
        self.init(deviceID: approved.deviceID, expires: approved.expires, hardExpires: approved.hardExpires)
    }

    /// Refresh from `/me`.
    public mutating func update(from me: MeResponse) {
        if !me.device.id.isEmpty {
            deviceID = me.device.id
        }
        if me.device.expires > 0 {
            expires = me.device.expires
        }
        if me.device.hardExpires > 0 {
            hardExpires = me.device.hardExpires
        }
    }
}

/// Expiry warnings (contract §7.7, §7.9). All (proposed).
public enum ExpiryNotice {
    public static let warnBefore: TimeInterval = 14 * 86400
    /// TestFlight builds live 90 days.
    public static let buildLifetime: TimeInterval = 90 * 86400

    /// «Вход действует до …» when `hardExpires - now < 14 days`, else `nil`.
    public static func loginWarning(hardExpires: Int, now: TimeInterval) -> String? {
        guard hardExpires > 0, Double(hardExpires) - now < warnBefore else {
            return nil
        }
        return "Вход действует до \(Fmt.dayMonth(hardExpires)). Потом нужно будет войти заново: пароль и число в Telegram."
    }

    /// Settings «Этот телефон»: «Вход до 11 января».
    public static func loginUntil(expires: Int) -> String {
        return "Вход до \(Fmt.dayMonth(expires))"
    }

    /// Settings «Этот телефон»: «Не дольше 13 октября».
    public static func notLongerThan(hardExpires: Int) -> String {
        return "Не дольше \(Fmt.dayMonth(hardExpires))"
    }

    /// «Сборка действует до …» (build date + 90 days).
    public static func buildValidUntil(buildDate: Int) -> String {
        return "Сборка действует до \(Fmt.dayMonth(buildDate + Int(buildLifetime)))"
    }

    /// Warning when the TestFlight build expires in ≤ 14 days, else `nil`.
    public static func buildWarning(buildDate: Int, now: TimeInterval) -> String? {
        let end = Double(buildDate) + buildLifetime
        guard buildDate > 0, end - now <= warnBefore else {
            return nil
        }
        return "Сборка TestFlight скоро истечёт — установи обновление из TestFlight."
    }
}

/// Links for the Settings sheet (contract §7.9).
public enum Links {
    public static let webPanel = URL(string: "https://fspirat.xyz/router/")!

    /// LuCI from `data.site.luci`, only if it matches `^https://[\w.-]+(:\d+)?/?$`.
    public static func luci(_ site: SiteInfo) -> URL? {
        guard Validation.isValidLuciURL(site.luci) else {
            return nil
        }
        return URL(string: site.luci)
    }

    /// `https://t.me/<bot>`, only if `bot` matches `^[A-Za-z0-9_]{5,32}$`.
    public static func bot(_ site: SiteInfo) -> URL? {
        guard Validation.isValidBotName(site.bot) else {
            return nil
        }
        return URL(string: "https://t.me/" + site.bot)
    }
}

/// Texts of the minimal Settings sheet (contract §7.9). (proposed)
public enum SettingsTexts {
    public static let timeZoneNote = "Время — роутера (Самара, UTC+4)"
    public static let logoutButton = "Выйти на этом iPhone"
    public static let logoutTitle = "Выйти на этом iPhone?"
    public static let logoutText = "Приложение забудет ключ доступа. Войти снова — пароль панели и число в Telegram."
    public static let logoutConfirm = "Выйти"
    public static let faceIDUsage = "Face ID защищает доступ к роутеру и опасные действия."
    public static let unlockReason = "Открыть приложение «Роутер»"

    /// `localizedReason` before a critical resend.
    public static func confirmReason(_ title: String) -> String {
        return "Подтвердить: \(title)"
    }
}
