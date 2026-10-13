import Foundation
import XCTest
@testable import RouterCore

/// Settings: access list, login journal, app switcher privacy (contract-stage4 §1.3, §5.6, §10.8).
final class AccessTests: XCTestCase {

    func list() throws -> AccessList {
        return try decodeJSON(AccessList.self, SampleJSON.accessList)
    }

    func testPhones() throws {
        let p = Access.phones(try list(), now: nowT)
        XCTAssertEqual(p.count, 2)
        XCTAssertEqual(p[0].name, "iPhone владельца")
        XCTAssertEqual(p[0].tag, "этот телефон")
        XCTAssertTrue(p[0].isCurrent)
        XCTAssertNil(p[0].revokeAction)
        XCTAssertEqual(p[0].details, "iPhone18,1 · iOS 26.0 · приложение 1.1 (20)")
        XCTAssertEqual(p[0].seenText, "был в сети 1\u{00A0}мин назад")
        XCTAssertEqual(p[0].ipText, "IP 203.0.113.50")
        XCTAssertEqual(p[0].expiresText, "вход до 11 января")
        XCTAssertFalse(p[0].expiresSoon)
        XCTAssertEqual(p[1].details, "iPhone16,1 · iOS 18.1 · приложение 1.0 (12)")
        XCTAssertEqual(p[1].seenText, "был в сети 11.10 14:16")
        XCTAssertEqual(p[1].expiresText, "вход до 19 октября")
        XCTAssertTrue(p[1].expiresSoon, "513 440 s < 7 days")
        XCTAssertNil(p[1].tag)
        XCTAssertEqual(p[1].revokeAction, .revokeApp(id: "8df5a0cb8a35a59a"))
        let bare = try decodeJSON(AccessList.self, #"{"apps":[{"id":"0123456789abcdef","name":"","model":"","os":"","app":"","seen":0,"last_ip":"","expires":1791900000}]}"#)
        let b = Access.phones(bare, now: nowT)[0]
        XCTAssertEqual(b.name, "Телефон")
        XCTAssertEqual(b.details, "")
        XCTAssertEqual(b.seenText, "был в сети —")
        XCTAssertNil(b.ipText)
    }

    func testBrowsersAndLogs() throws {
        let l = try list()
        let w = Access.browsers(l, now: nowT)
        XCTAssertEqual(w.count, 1)
        XCTAssertEqual(w[0].id, "8207c706de3f72c7")
        XCTAssertEqual(w[0].title, "Chrome · Windows")
        XCTAssertEqual(w[0].ipText, "IP 203.0.113.50")
        XCTAssertEqual(w[0].seenText, "был 4\u{00A0}мин назад")
        XCTAssertEqual(w[0].createdText, "вход сегодня 12:26")
        XCTAssertEqual(w[0].revokeAction, .revokeWeb(ref: "8207c706de3f72c7"))
        XCTAssertEqual(AccessTexts.webCloseText(ip: w[0].ip), "Браузер с IP 203.0.113.50 выйдет из панели. Если он запомнен, при следующем входе код из Telegram не спросят.")

        let logins = Access.logins(l, now: nowT)
        XCTAssertEqual(logins.map { $0.text }, ["вошёл", "неверное число"])
        XCTAssertEqual(logins.map { $0.tone }, [.ok, .err])
        XCTAssertEqual(logins[0].name, "iPhone владельца")
        XCTAssertEqual(logins[0].time, "сегодня 14:06")
        XCTAssertEqual(logins[1].ipText, "IP 198.51.100.99")

        let auth = Access.authLog(l, now: nowT)
        XCTAssertEqual(auth.map { $0.text }, [
            "Вход в приложение", "Приложение: пароль верный, ждёт числа в боте", "Приложение: вход отклонён в боте",
            "Вход в веб-панель", "Пароль верный, код отправлен в Telegram", "Неверный пароль или код"
        ])
        XCTAssertEqual(auth.map { $0.tone }, [.ok, .info, .err, .ok, .info, .warn])
        XCTAssertEqual(Set(auth.map { $0.id }).count, 6)
    }

    func testWordMaps() {
        let results = ["pending", "approved", "issued", "expired", "denied", "notme", "cancelled"]
        XCTAssertEqual(results.map { Access.loginResult($0).text }, [
            "ждёт числа в боте", "одобрен, ключ ещё не забран", "вошёл", "время вышло", "неверное число", "нажато «Это не я»", "отменён в приложении"
        ])
        XCTAssertEqual(results.map { Access.loginResult($0).tone }, [.neutral, .neutral, .ok, .neutral, .err, .err, .neutral])
        XCTAssertEqual(Access.loginResult("other").text, "other")
        let codes = ["OK", "FAIL", "LOCKED", "CODE", "CODEFAIL", "LOGOUT", "LOGOUT_ALL", "APP_LOGIN", "APP_OK", "APP_DENIED", "APP_REVOKE", "APP_BADTOKEN", "APP_URLTOKEN"]
        XCTAssertEqual(codes.map { Access.authWhat($0).tone }, [.ok, .warn, .err, .info, .warn, .info, .info, .info, .ok, .err, .info, .warn, .err])
        XCTAssertEqual(Access.authWhat("LOCKED").text, "Вход закрыт после ошибок")
        XCTAssertEqual(Access.authWhat("APP_URLTOKEN").text, "Ключ попал в адрес запроса")
        XCTAssertEqual(Access.authWhat("LOGOUT_ALL").text, "Выход на всех устройствах")
        XCTAssertEqual(Access.authWhat("NEW_CODE").text, "NEW_CODE")
        XCTAssertEqual(Access.authWhat("NEW_CODE").tone, .info)
    }

    func testUserAgents() {
        XCTAssertEqual(Access.uaSummary("Mozilla/5.0 (iPhone; CPU iPhone OS 26_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Mobile/15E148 Safari/604.1"), "Safari · iPhone")
        XCTAssertEqual(Access.uaSummary("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/141.0 Mobile/15E148 Safari/604.1"), "Chrome · iPhone")
        XCTAssertEqual(Access.uaSummary("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"), "Safari · Mac")
        XCTAssertEqual(Access.uaSummary("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0 Safari/537.36 Edg/141.0"), "Edge · Windows")
        XCTAssertEqual(Access.uaSummary("Mozilla/5.0 (X11; Linux x86_64; rv:140.0) Gecko/20100101 Firefox/140.0"), "Firefox · Linux")
        XCTAssertEqual(Access.uaSummary("Mozilla/5.0 (Linux; Android 15) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0 YaBrowser/25.8 Mobile Safari/537.36"), "Яндекс Браузер · Android")
        XCTAssertEqual(Access.uaSummary("Mozilla/5.0 (Windows NT 10.0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0 Safari/537.36 OPR/120.0"), "Opera · Windows")
        XCTAssertEqual(Access.uaSummary("curl/8.0"), "curl/8.0")
        XCTAssertEqual(Access.uaSummary(String(repeating: "x", count: 60)), String(repeating: "x", count: 40))
        XCTAssertEqual(Access.uaSummary(""), "Браузер")
    }

    func testTexts() {
        XCTAssertEqual(AccessTexts.revokeTitle("Второй iPhone"), "Отозвать доступ «Второй iPhone»?")
        XCTAssertEqual(AccessTexts.revokeTitle(""), "Отозвать доступ «телефон»?")
        XCTAssertEqual(SettingsTexts.hideInSwitcherTitle, "Скрывать в переключателе приложений")
        XCTAssertEqual(AccessTexts.revokeAllToggle, "Также закрыть все сессии веб-панели")
    }

    func testSwitcherPrivacy() {
        XCTAssertEqual(SwitcherPrivacy.storageKey, "hideInSwitcher")
        XCTAssertFalse(SwitcherPrivacy.defaultValue, "data is not hidden by default")
        XCTAssertFalse(SwitcherPrivacy.showsCover(hideInSwitcher: false, isActive: false))
        XCTAssertTrue(SwitcherPrivacy.showsCover(hideInSwitcher: true, isActive: false))
        XCTAssertFalse(SwitcherPrivacy.showsCover(hideInSwitcher: true, isActive: true))
        // «Сразу» with the toggle off: lock on the way back, not on the way out
        XCTAssertFalse(SwitcherPrivacy.locksOnBackground(lockDelay: 0, hideInSwitcher: false))
        XCTAssertTrue(SwitcherPrivacy.locksOnReturn(away: 0, lockDelay: 0))
        XCTAssertTrue(SwitcherPrivacy.locksOnReturn(away: 0.2, lockDelay: 0))
        // «Сразу» with the toggle on: stage 3 behaviour
        XCTAssertTrue(SwitcherPrivacy.locksOnBackground(lockDelay: 0, hideInSwitcher: true))
        // delays: decided on return
        XCTAssertFalse(SwitcherPrivacy.locksOnBackground(lockDelay: 60, hideInSwitcher: true))
        XCTAssertFalse(SwitcherPrivacy.locksOnReturn(away: 59, lockDelay: 60))
        XCTAssertTrue(SwitcherPrivacy.locksOnReturn(away: 60, lockDelay: 60))
        XCTAssertTrue(SwitcherPrivacy.locksOnReturn(away: 301, lockDelay: 300))
        XCTAssertFalse(SwitcherPrivacy.closesDialogsOnInactive(hideInSwitcher: false))
        XCTAssertTrue(SwitcherPrivacy.closesDialogsOnInactive(hideInSwitcher: true))
    }
}
