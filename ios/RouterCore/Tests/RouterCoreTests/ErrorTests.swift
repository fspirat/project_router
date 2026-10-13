import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import RouterCore

final class ErrorTests: XCTestCase {

    private func http(_ status: Int, _ body: String, headers: [String: String] = [:]) -> APIError {
        return APIError.fromHTTP(status: status, body: Data(body.utf8), headers: headers)
    }

    func testLogoutOnlyForTokenCodes() {
        for code in ["token_missing", "token_invalid", "token_expired", "token_revoked"] {
            let e = http(401, #"{"error":"\#(code)","message":"x"}"#)
            XCTAssertTrue(e.isAuthFailure, code)
        }
        let bad = http(401, #"{"error":"bad_password","message":"Неверный пароль. Осталось попыток: 4.","left":4}"#)
        XCTAssertFalse(bad.isAuthFailure)
        XCTAssertEqual(bad.left, 4)
        XCTAssertEqual(bad.userMessage, "Неверный пароль. Осталось попыток: 4.")

        XCTAssertFalse(http(401, "not json").isAuthFailure)
        XCTAssertFalse(http(403, #"{"error":"browser_request","message":"x"}"#).isAuthFailure)
        XCTAssertFalse(http(403, #"{"error":"token_invalid"}"#).isAuthFailure)
        XCTAssertTrue(APIError.notLoggedIn.isAuthFailure)
    }

    func testServerMessageIsShownVerbatim() {
        let e = http(401, #"{"error":"token_revoked","message":"Доступ этого телефона отозван — войди заново."}"#)
        XCTAssertEqual(e.userMessage, "Доступ этого телефона отозван — войди заново.")
        XCTAssertTrue(e.bodyIsJSON)
        let locked = http(429, #"{"error":"locked","message":"Слишком много неверных попыток. Вход с этого адреса закрыт ещё на 15 мин.","retry_after":874}"#)
        XCTAssertEqual(locked.retryAfter, 874)
        XCTAssertEqual(locked.userMessage, "Слишком много неверных попыток. Вход с этого адреса закрыт ещё на 15 мин.")
        XCTAssertFalse(locked.isRateLimited)
    }

    func testRateLimitedSuffixAndHeaderFallback() {
        let server = http(429, #"{"error":"rate_limited","message":"Слишком часто — подожди немного.","retry_after":15}"#, headers: ["retry-after": "15"])
        XCTAssertTrue(server.isRateLimited)
        XCTAssertEqual(server.userMessage, "Слишком часто — подожди немного. Повтори через 15 с.")
        XCTAssertEqual(server.baseMessage, "Слишком часто — подожди немного.")

        let nginx = http(429, #"{"error":"rate_limited","retry_after":2}"#, headers: ["retry-after": "2"])
        XCTAssertEqual(nginx.userMessage, "Слишком часто — подожди немного. Повтори через 2 с.")

        let headerOnly = http(429, #"{"error":"rate_limited"}"#, headers: ["retry-after": " 120 "])
        XCTAssertEqual(headerOnly.retryAfter, 120)
        XCTAssertEqual(headerOnly.userMessage, "Слишком часто — подожди немного. Повтори через 2 мин.")

        let busy = http(429, #"{"error":"busy","message":"Роутер отвечает медленно: другие запросы к нему ещё ждут ответа. Повтори через несколько секунд.","retry_after":3}"#)
        XCTAssertTrue(busy.isBusy)
        XCTAssertTrue(busy.isTransient)
        XCTAssertEqual(busy.userMessage, "Роутер отвечает медленно: другие запросы к нему ещё ждут ответа. Повтори через несколько секунд.")
    }

    func testNginxBodiesWithoutMessage() {
        let unavailable = http(502, #"{"error":"server_unavailable"}"#)
        XCTAssertEqual(unavailable.userMessage, "Сервер панели не ответил — попробуй через минуту.")
        XCTAssertFalse(unavailable.entersOfflineMode)
        XCTAssertTrue(unavailable.isTransient)
        XCTAssertEqual(http(413, #"{"error":"too_large"}"#).userMessage, "Слишком большой запрос.")
        XCTAssertEqual(http(404, #"{"error":"not_found"}"#).userMessage, "Не найдено.")
    }

    func testOfflineClassification() {
        let off = http(502, #"{"error":"router_offline","message":"Роутер не на связи: туннель до сервера оборван или дома нет интернета."}"#)
        XCTAssertTrue(off.entersOfflineMode)
        XCTAssertTrue(off.isOffline)
        XCTAssertFalse(off.mayHaveExecuted)
        let timeout = http(504, #"{"error":"router_timeout","message":"Роутер не ответил вовремя."}"#)
        XCTAssertTrue(timeout.entersOfflineMode)
        XCTAssertTrue(timeout.mayHaveExecuted)
        XCTAssertEqual(timeout.actionMessage, "Роутер не ответил вовремя. Действие могло выполниться — проверь состояние через минуту.")
        XCTAssertEqual(off.actionMessage, off.userMessage)
        let badReply = http(502, #"{"error":"router_bad_reply","message":"Роутер ответил непонятно — попробуй ещё раз."}"#)
        XCTAssertTrue(badReply.isBadReply)
        XCTAssertFalse(badReply.entersOfflineMode)

        let net = APIError.transport(URLError(.notConnectedToInternet))
        XCTAssertEqual(net.kind, .noConnection)
        XCTAssertTrue(net.isOffline)
        XCTAssertFalse(net.entersOfflineMode)
        XCTAssertEqual(net.userMessage, "Нет связи с сервером. Проверь интернет и попробуй ещё раз.")
        XCTAssertTrue(net.isTransient)

        XCTAssertEqual(APIError.transport(URLError(.cancelled)).kind, .cancelled)
        XCTAssertEqual(APIError.transport(CancellationError()).kind, .cancelled)
        XCTAssertEqual(APIError.transport(CancellationError()).userMessage, "")
    }

    func testNonJSONBodies() {
        let e500 = http(500, "<html>Fatal error</html>")
        XCTAssertFalse(e500.bodyIsJSON)
        XCTAssertEqual(e500.code, "")
        XCTAssertEqual(e500.userMessage, "Ошибка на сервере — попробуй через минуту.")
        let e404 = http(404, "<html>nope</html>")
        XCTAssertEqual(e404.userMessage, "Запрос не принят (код 404).")
        XCTAssertEqual(http(400, "").userMessage, "Запрос не принят (код 400).")
    }

    func testRouterCodes() {
        let notInstalled = http(503, #"{"error":"not installed","message":"Не установлено на роутере.","source":"router"}"#)
        XCTAssertEqual(notInstalled.source, "router")
        XCTAssertEqual(notInstalled.userMessage, "Не установлено на роутере.")
        XCTAssertFalse(notInstalled.isAppDisabled)
        XCTAssertEqual(http(400, #"{"error":"bad node","source":"router"}"#).userMessage, "Такого сервера нет — обнови список.")
        XCTAssertEqual(http(500, #"{"error":"subscribe.lua not found","source":"router"}"#).userMessage, "На роутере нет скрипта подписок PassWall.")
        XCTAssertEqual(http(500, #"{"error":"weird thing","source":"router"}"#).userMessage, "Роутер не смог выполнить действие.")
        let busy = http(409, #"{"error":"busy","message":"Другое действие ещё выполняется — подожди немного.","source":"router"}"#)
        XCTAssertTrue(busy.isBusy)
        XCTAssertFalse(busy.isTransient)
    }

    func testFallbackTableWithoutMessage() {
        let expected: [String: String] = [
            "bad_param": "Неверные данные запроса — обнови приложение.",
            "confirm_invalid": "Подтверждение не подошло — повтори действие.",
            "token_missing": "Нужно войти.",
            "token_invalid": "Ключ не подходит — войди заново.",
            "token_expired": "Срок входа истёк — войди заново.",
            "token_revoked": "Доступ этого телефона отозван — войди заново.",
            "not_in_v1": "Это действие пока есть только в веб-панели.",
            "busy": "Другое действие ещё выполняется — подожди немного.",
            "login_denied": "Вход отклонён в Telegram.",
            "login_expired": "Время на подтверждение вышло — начни вход заново.",
            "app_disabled": "Приложение выключено на сервере. Веб-панель работает.",
            "tg_unavailable": "Telegram-бот недоступен — войти в приложение сейчас нельзя.",
            "router_offline": "Роутер не на связи: туннель до сервера оборван или дома нет интернета.",
            "router_timeout": "Роутер не ответил вовремя.",
            "server_error": "Ошибка на сервере — попробуй через минуту.",
            "server_config": "Сервер не настроен: нет ключа роутера (нужен Deploy server).",
            "router_token": "Роутер отклонил ключ сервера — нужен Deploy server.",
            "too_many_devices": "Уже 10 телефонов с доступом — отзови старый в Настройках, в веб-панели или командой /apps в боте.",
            "locked": "Вход временно закрыт после неверных попыток.",
            "method": "Неверный метод запроса — обнови приложение.",
            "browser_request": "Запросы из браузера сюда не принимаются.",
            "token_in_url": "Ключ нельзя передавать в адресе запроса. Если это был настоящий ключ, он уже отозван — войди заново.",
            "not_json": "Тело запроса должно быть JSON."
        ]
        for (code, text) in expected {
            XCTAssertEqual(http(400, #"{"error":"\#(code)"}"#).userMessage, text, code)
        }
        let empty = http(400, #"{"error":"bad_param","message":""}"#)
        XCTAssertEqual(empty.userMessage, "Неверные данные запроса — обнови приложение.")
    }

    func testAppDisabledAndLoginReset() {
        let off = http(503, #"{"error":"app_disabled","message":"Приложение выключено на сервере. Веб-панель работает."}"#)
        XCTAssertTrue(off.isAppDisabled)
        XCTAssertFalse(off.isTransient)
        XCTAssertFalse(off.isAuthFailure)
        XCTAssertTrue(http(410, #"{"error":"login_denied","message":"Вход отклонён в Telegram."}"#).isLoginReset)
        XCTAssertTrue(http(410, #"{"error":"login_expired"}"#).isLoginReset)
        XCTAssertTrue(http(409, #"{"error":"too_many_devices"}"#).isLoginReset)
        XCTAssertTrue(APIError.loginTimedOut.isLoginReset)
        XCTAssertEqual(APIError.loginTimedOut.userMessage, "Время на подтверждение вышло — начни вход заново.")
    }

    func testPingJobMessages() {
        let slow = APIError(kind: .http, status: 504, code: "router_timeout", serverMessage: "Роутер не ответил вовремя.")
        XCTAssertEqual(ActionTexts.pingJobErrorMessage(slow), "Проверка идёт дольше обычного — результат появится в Сводке через минуту.")
        XCTAssertEqual(ActionTexts.pingJobErrorMessage(APIError.jobTimedOut), ActionTexts.pingSlow)
        let off = APIError(kind: .http, status: 502, code: "router_offline", serverMessage: "Роутер не на связи: туннель до сервера оборван или дома нет интернета.")
        XCTAssertEqual(ActionTexts.pingJobErrorMessage(off), off.userMessage)
    }
}
