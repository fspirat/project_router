import Foundation

// Settings → «Доступ к роутеру», «Журнал входов», «Выход» (contract-stage4 §5.6), app switcher privacy (§1.3).

public struct PhoneRow: Equatable, Sendable, Identifiable {
    public var id: String
    /// `name` or «Телефон».
    public var name: String
    /// «iPhone18,1 · iOS 26.0 · приложение 1.1 (20)».
    public var details: String
    /// «был в сети 1 мин назад».
    public var seenText: String
    /// «IP 203.0.113.50» or `nil`.
    public var ipText: String?
    /// «вход до 11 января».
    public var expiresText: String
    /// `expires − now < 7 days` → err.
    public var expiresSoon: Bool
    public var isCurrent: Bool
    /// «этот телефон» for the current one.
    public var tag: String?

    /// «Отозвать» (app dialog first, no Face ID); never for this phone.
    public var revokeAction: RouterAction? {
        return isCurrent ? nil : .revokeApp(id: id)
    }
}

public struct BrowserRow: Equatable, Sendable, Identifiable {
    /// `ref`.
    public var id: String
    /// «Chrome · Windows».
    public var title: String
    /// «IP 203.0.113.50».
    public var ipText: String?
    /// «был 4 мин назад».
    public var seenText: String
    /// «вход сегодня 12:33».
    public var createdText: String
    public var ip: String

    /// «Закрыть» (app dialog first).
    public var revokeAction: RouterAction {
        return .revokeWeb(ref: id)
    }
}

public struct AccessLogRow: Equatable, Sendable, Identifiable {
    public var id: String
    public var ts: Int
    /// «сегодня 14:06».
    public var time: String
    /// Logins: the phone name; auth log: "".
    public var name: String
    /// «вошёл», «Вход в веб-панель», …
    public var text: String
    /// «IP 203.0.113.50» or `nil`.
    public var ipText: String?
    public var tone: Tone
}

public enum AccessTexts {
    public static let title = "Доступ к роутеру"
    public static let phonesTitle = "Телефоны"
    public static let browsersTitle = "Браузеры"
    public static let thisPhone = "этот телефон"
    public static let emptyPhones = "Приложение ещё ни на одном телефоне не входило."
    /// (proposed)
    public static let emptyWeb = "Открытых сессий веб-панели нет."
    public static let revokeButton = "Отозвать"
    public static let revokeText = "Приложение на этом телефоне сразу выйдет и больше не сможет управлять роутером. Вернуть доступ — войти в приложении заново: пароль и подтверждение в Telegram. Бот пришлёт сообщение об отзыве."
    /// (proposed)
    public static let webCloseTitle = "Закрыть сессию веб-панели?"
    public static let webCloseButton = "Закрыть"
    public static let loginsTitle = "Журнал входов"
    public static let appLoginsTitle = "Входы в приложение"
    public static let authLogTitle = "Все входы и выходы"
    public static let revokeAllRow = "Выйти везде — телефоны и браузеры"
    public static let revokeAllToggle = "Также закрыть все сессии веб-панели"
    public static let revokeAllContinue = "Продолжить"
    /// (proposed) Login screen banner after `revoke-all`.
    public static let revokedAllBanner = "Вы вышли на всех устройствах. Войти заново — пароль и число в Telegram."

    /// «Отозвать доступ «<nm>»?».
    public static func revokeTitle(_ name: String) -> String {
        return "Отозвать доступ «\(name.isEmpty ? "телефон" : name)»?"
    }

    /// (proposed) «Браузер с IP … выйдет из панели. …».
    public static func webCloseText(ip: String) -> String {
        return "Браузер с IP \(ip) выйдет из панели. Если он запомнен, при следующем входе код из Telegram не спросят."
    }
}

extension SettingsTexts {
    /// New toggle (contract-stage4 §1.3), default off.
    public static let hideInSwitcherTitle = "Скрывать в переключателе приложений"
    /// (proposed)
    public static let hideInSwitcherFooter = "Вместо экрана в переключателе приложений будет значок. Face ID при возврате работает, как настроено выше."
    public static let faceIDOnOpen = "Face ID при открытии"
    public static let lockAfter = "Блокировать"
    public static let faceIDForActions = "Face ID для опасных действий"
    /// (proposed)
    public static let faceIDForActionsFooter = "Спрашивается перед «Напрямую, без VPN», перезагрузкой роутера и «Выйти везде»."
    public static let luciCaption = "откроется в Safari со своим входом"
}

/// App switcher privacy and the lock moment (contract-stage4 §1.3). Pure decisions for `AppLock` and the cover.
public enum SwitcherPrivacy {
    /// `@AppStorage` key and default (off: the switcher shows the real screen).
    public static let storageKey = "hideInSwitcher"
    public static let defaultValue = false

    /// Show the opaque cover? Only with the toggle on and the scene not active.
    public static func showsCover(hideInSwitcher: Bool, isActive: Bool) -> Bool {
        return hideInSwitcher && !isActive
    }

    /// Engage the lock already in `didEnterBackground`? Only for «Сразу» **with** the toggle on
    /// (otherwise the lock screen would end up in the switcher snapshot).
    public static func locksOnBackground(lockDelay: TimeInterval, hideInSwitcher: Bool) -> Bool {
        return lockDelay <= 0 && hideInSwitcher
    }

    /// Engage on the way back (`willEnterForeground`, the app was really backgrounded `away` seconds):
    /// `away >= lockDelay` («Сразу» = 0 → always).
    public static func locksOnReturn(away: TimeInterval, lockDelay: TimeInterval) -> Bool {
        return away >= max(0, lockDelay)
    }

    /// Auto-close the «Проверить?» pre-dialog when the scene becomes `.inactive`? Only with the toggle on.
    public static func closesDialogsOnInactive(hideInSwitcher: Bool) -> Bool {
        return hideInSwitcher
    }
}

public enum Access {
    public static func phones(_ list: AccessList, now: TimeInterval) -> [PhoneRow] {
        return list.apps.map { x in
            var parts: [String] = []
            if !x.model.isEmpty {
                parts.append(x.model)
            }
            let os = Fmt.osText(x.os)
            if !os.isEmpty {
                parts.append(os)
            }
            if !x.app.isEmpty {
                parts.append("приложение " + x.app)
            }
            return PhoneRow(
                id: x.id,
                name: x.name.isEmpty ? "Телефон" : x.name,
                details: parts.joined(separator: " · "),
                seenText: "был в сети " + Fmt.seenText(x.seen, now: now),
                ipText: x.lastIP.isEmpty ? nil : "IP " + x.lastIP,
                expiresText: "вход до " + Fmt.dayMonth(x.expires),
                expiresSoon: Double(x.expires) - now < 7 * 86400,
                isCurrent: x.current,
                tag: x.current ? AccessTexts.thisPhone : nil
            )
        }
    }

    public static func browsers(_ list: AccessList, now: TimeInterval) -> [BrowserRow] {
        return list.web.map { w in
            BrowserRow(
                id: w.ref,
                title: uaSummary(w.ua),
                ipText: w.ip.isEmpty ? nil : "IP " + w.ip,
                seenText: "был " + Fmt.seenText(w.seen, now: now),
                createdText: "вход " + Fmt.when(w.created, now: now),
                ip: w.ip
            )
        }
    }

    public static func logins(_ list: AccessList, now: TimeInterval) -> [AccessLogRow] {
        return list.logins.enumerated().map { i, l in
            let r = loginResult(l.result)
            return AccessLogRow(
                id: "l\(i)", ts: l.ts, time: Fmt.when(l.ts, now: now), name: l.name, text: r.text,
                ipText: l.ip.isEmpty ? nil : "IP " + l.ip, tone: r.tone
            )
        }
    }

    public static func authLog(_ list: AccessList, now: TimeInterval) -> [AccessLogRow] {
        return list.authLog.enumerated().map { i, e in
            let r = authWhat(e.what)
            return AccessLogRow(
                id: "a\(i)", ts: e.ts, time: Fmt.when(e.ts, now: now), name: "", text: r.text,
                ipText: e.ip.isEmpty ? nil : "IP " + e.ip, tone: r.tone
            )
        }
    }

    /// (proposed) Word and level of an app login result.
    public static func loginResult(_ result: String) -> (text: String, tone: Tone) {
        switch result {
        case "pending":
            return ("ждёт числа в боте", .neutral)
        case "approved":
            return ("одобрен, ключ ещё не забран", .neutral)
        case "issued":
            return ("вошёл", .ok)
        case "expired":
            return ("время вышло", .neutral)
        case "denied":
            return ("неверное число", .err)
        case "notme":
            return ("нажато «Это не я»", .err)
        case "cancelled":
            return ("отменён в приложении", .neutral)
        default:
            return (result, .neutral)
        }
    }

    /// (proposed) Word and level of an `auth_log.what` code; unknown → the raw code (info).
    public static func authWhat(_ what: String) -> (text: String, tone: Tone) {
        switch what {
        case "OK":
            return ("Вход в веб-панель", .ok)
        case "FAIL":
            return ("Неверный пароль или код", .warn)
        case "LOCKED":
            return ("Вход закрыт после ошибок", .err)
        case "CODE":
            return ("Пароль верный, код отправлен в Telegram", .info)
        case "CODEFAIL":
            return ("Код в Telegram не отправился", .warn)
        case "LOGOUT":
            return ("Выход из веб-панели", .info)
        case "LOGOUT_ALL":
            return ("Выход на всех устройствах", .info)
        case "APP_LOGIN":
            return ("Приложение: пароль верный, ждёт числа в боте", .info)
        case "APP_OK":
            return ("Вход в приложение", .ok)
        case "APP_DENIED":
            return ("Приложение: вход отклонён в боте", .err)
        case "APP_REVOKE":
            return ("Доступ приложения отозван", .info)
        case "APP_BADTOKEN":
            return ("Приложение: неверный ключ", .warn)
        case "APP_URLTOKEN":
            return ("Ключ попал в адрес запроса", .err)
        default:
            return (what, .info)
        }
    }

    /// (proposed) «Chrome · Windows», «Safari · iPhone»; unknown → the first 40 characters; empty → «Браузер».
    public static func uaSummary(_ ua: String) -> String {
        let u = ua
        func has(_ s: String) -> Bool {
            return u.range(of: s) != nil
        }
        var browser: String? = nil
        if has("YaBrowser/") {
            browser = "Яндекс Браузер"
        } else if has("Edg/") || has("EdgA/") || has("EdgiOS/") {
            browser = "Edge"
        } else if has("OPR/") || has("Opera") {
            browser = "Opera"
        } else if has("Firefox/") || has("FxiOS/") {
            browser = "Firefox"
        } else if has("CriOS/") || has("Chrome/") {
            browser = "Chrome"
        } else if has("Safari/") {
            browser = "Safari"
        }
        var os: String? = nil
        if has("iPhone") {
            os = "iPhone"
        } else if has("iPad") {
            os = "iPad"
        } else if has("Android") {
            os = "Android"
        } else if has("Windows") {
            os = "Windows"
        } else if has("Macintosh") || has("Mac OS X") {
            os = "Mac"
        } else if has("Linux") {
            os = "Linux"
        }
        let parts = [browser, os].compactMap { $0 }
        if !parts.isEmpty {
            return parts.joined(separator: " · ")
        }
        let trimmed = u.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "Браузер"
        }
        return String(trimmed.prefix(40))
    }
}
