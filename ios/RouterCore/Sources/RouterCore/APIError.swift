import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Every failure of a request to `/router/app/v1`, contract §3.
///
/// `error` codes are plain strings (router codes contain spaces, e.g. "not installed").
public struct APIError: Error, Equatable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        /// The server answered with a non-2xx status (JSON or not).
        case http
        /// No HTTP response: offline, DNS, TLS, timeout.
        case noConnection
        /// 2xx with a body that cannot be used (not JSON, wrong shape, captive portal).
        case badResponse
        /// The request was not sent: no token, invalid input, or a local timeout.
        case client
        /// The task was cancelled. Show nothing.
        case cancelled
    }

    public var kind: Kind
    /// HTTP status; 0 when there was no response.
    public var status: Int
    /// Body `error` ("" when absent or not JSON).
    public var code: String
    /// Body `message` when it is a non-empty string.
    public var serverMessage: String?
    /// Body `retry_after`, else the `Retry-After` header (seconds).
    public var retryAfter: Int?
    /// `left` of `401 bad_password`.
    public var left: Int?
    /// `"router"` when the code came from the router CGI.
    public var source: String?
    /// The error body was a JSON object.
    public var bodyIsJSON: Bool

    public init(
        kind: Kind,
        status: Int = 0,
        code: String = "",
        serverMessage: String? = nil,
        retryAfter: Int? = nil,
        left: Int? = nil,
        source: String? = nil,
        bodyIsJSON: Bool = false
    ) {
        self.kind = kind
        self.status = status
        self.code = code
        self.serverMessage = serverMessage
        self.retryAfter = retryAfter
        self.left = left
        self.source = source
        self.bodyIsJSON = bodyIsJSON
    }

    // MARK: - Construction

    /// Builds the error for a non-2xx response. `headers` keys must be lowercased.
    public static func fromHTTP(status: Int, body: Data, headers: [String: String]) -> APIError {
        var e = APIError(kind: .http, status: status)
        if let json = try? JSONValue.parse(body), json.isObject {
            e.bodyIsJSON = true
            e.code = json.str("error") ?? ""
            if let m = json["message"], case .string(let text) = m, !text.isEmpty {
                e.serverMessage = text
            }
            if let s = json["source"], case .string(let text) = s {
                e.source = text
            }
            e.left = json.num("left")
            e.retryAfter = json.num("retry_after")
        }
        if e.retryAfter == nil, let h = headers["retry-after"] {
            e.retryAfter = Int(h.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return e
    }

    /// Maps an error thrown by the transport.
    public static func transport(_ error: Error) -> APIError {
        if let e = error as? APIError {
            return e
        }
        if error is CancellationError {
            return APIError(kind: .cancelled)
        }
        if let u = error as? URLError, u.code == .cancelled {
            return APIError(kind: .cancelled)
        }
        return APIError(kind: .noConnection)
    }

    /// A local error: the request was not sent.
    public static func client(code: String, message: String?, status: Int = 0) -> APIError {
        return APIError(kind: .client, status: status, code: code, serverMessage: message)
    }

    /// No usable token in the app: behaves like `401 token_missing` (LOGOUT), nothing is sent.
    public static let notLoggedIn = APIError(
        kind: .client, status: 401, code: "token_missing", serverMessage: "Нужно войти."
    )

    /// The login countdown ran out locally.
    public static let loginTimedOut = APIError(
        kind: .client, status: 410, code: "login_expired",
        serverMessage: "Время на подтверждение вышло — начни вход заново."
    )

    /// A job did not finish within the client limit (160 s).
    public static let jobTimedOut = APIError(
        kind: .client, status: 0, code: "job_timeout",
        serverMessage: ActionTexts.pingSlow
    )

    static func badResponse(status: Int) -> APIError {
        return APIError(kind: .badResponse, status: status, code: "bad_response")
    }

    // MARK: - Classification

    /// The four `token_*` codes that log out (contract §3.1).
    public static let logoutCodes: Set<String> = ["token_missing", "token_invalid", "token_expired", "token_revoked"]

    /// LOGOUT: stop polling, delete the token, show the login screen with `userMessage`.
    /// Only `401 token_*` (or a missing/malformed local token). `bad_password` is NOT a logout.
    public var isAuthFailure: Bool {
        guard APIError.logoutCodes.contains(code) else {
            return false
        }
        if kind == .http {
            return status == 401
        }
        return kind == .client
    }

    /// `router_offline` (502) or `router_timeout` (504). On `/status` outside a quiet
    /// window this switches offline mode on (contract §7.5).
    public var entersOfflineMode: Bool {
        return kind == .http && (code == "router_offline" || code == "router_timeout")
    }

    /// `entersOfflineMode` or no connection at all. Offline MODE uses `entersOfflineMode` only:
    /// a network error means the phone or the server is the problem, not the router.
    public var isOffline: Bool {
        return entersOfflineMode || kind == .noConnection
    }

    public var isNoConnection: Bool {
        return kind == .noConnection
    }

    public var isCancelled: Bool {
        return kind == .cancelled
    }

    /// `503 app_disabled`: full-screen state, keep the token.
    public var isAppDisabled: Bool {
        return code == "app_disabled"
    }

    /// `429 rate_limited` (server or nginx).
    public var isRateLimited: Bool {
        return status == 429 && code == "rate_limited"
    }

    /// `409 busy` or `429 busy`.
    public var isBusy: Bool {
        return code == "busy"
    }

    /// `502 router_bad_reply`: on reads keep the old data, retry on the next tick.
    public var isBadReply: Bool {
        return code == "router_bad_reply"
    }

    /// `504 router_timeout`: an action may have run anyway.
    public var mayHaveExecuted: Bool {
        return kind == .http && code == "router_timeout"
    }

    /// Back to the login form: `login_denied`, `login_expired`, `too_many_devices`.
    public var isLoginReset: Bool {
        return code == "login_denied" || code == "login_expired" || code == "too_many_devices"
    }

    /// Worth retrying on the next tick / poll: no connection, unusable 2xx body, 429, 5xx (not `app_disabled`).
    public var isTransient: Bool {
        switch kind {
        case .noConnection, .badResponse:
            return true
        case .http:
            if code == "app_disabled" || code == "tg_unavailable" {
                return false
            }
            return status == 429 || status >= 500
        case .client, .cancelled:
            return false
        }
    }

    // MARK: - Messages (contract §3.2)

    /// Fallback texts keyed by `error`, used when the body has no `message`.
    public static let fallbackTexts: [String: String] = [
        "bad_param": "Неверные данные запроса — обнови приложение.",
        "token_in_url": "Ключ нельзя передавать в адресе запроса. Если это был настоящий ключ, он уже отозван — войди заново.",
        "too_long": "Слишком длинное значение.",
        "confirm_invalid": "Подтверждение не подошло — повтори действие.",
        "confirm_required": "Нужно подтверждение.",
        "token_missing": "Нужно войти.",
        "token_invalid": "Ключ не подходит — войди заново.",
        "token_expired": "Срок входа истёк — войди заново.",
        "token_revoked": "Доступ этого телефона отозван — войди заново.",
        "bad_password": "Неверный пароль.",
        "browser_request": "Запросы из браузера сюда не принимаются.",
        "not_found": "Не найдено.",
        "not_in_v1": "Это действие пока есть только в веб-панели.",
        "method": "Неверный метод запроса — обнови приложение.",
        "busy": "Другое действие ещё выполняется — подожди немного.",
        "too_many_devices": "Уже 10 телефонов с доступом — отзови старый в Настройках, в веб-панели или командой /apps в боте.",
        "login_denied": "Вход отклонён в Telegram.",
        "login_expired": "Время на подтверждение вышло — начни вход заново.",
        "too_large": "Слишком большой запрос.",
        "not_json": "Тело запроса должно быть JSON.",
        "rate_limited": "Слишком часто — подожди немного.",
        "locked": "Вход временно закрыт после неверных попыток.",
        "server_error": "Ошибка на сервере — попробуй через минуту.",
        "server_config": "Сервер не настроен: нет ключа роутера (нужен Deploy server).",
        "router_token": "Роутер отклонил ключ сервера — нужен Deploy server.",
        "router_offline": "Роутер не на связи: туннель до сервера оборван или дома нет интернета.",
        "router_timeout": "Роутер не ответил вовремя.",
        "router_bad_reply": "Роутер ответил непонятно — попробуй ещё раз.",
        "app_disabled": "Приложение выключено на сервере. Веб-панель работает.",
        "tg_unavailable": "Telegram-бот недоступен — войти в приложение сейчас нельзя.",
        "server_unavailable": "Сервер панели не ответил — попробуй через минуту.",
        "bad mac": "Неверный адрес устройства (MAC).",
        "bad node": "Такого сервера нет — обнови список.",
        "bad via": "Неизвестный вид теста.",
        "domain": "Нужен домен вида site.ru.",
        "time": "Неверное время.",
        "resolve": "Не удалось узнать IP сервера.",
        "no target": "Нет такого сервиса.",
        "no rule": "В PassWall нет правила MyDirect.",
        "bad sub": "Нет такой подписки — обнови список.",
        "bad on": "Неверный режим.",
        "bad strategy": "Нет такой стратегии.",
        "not installed": "Не установлено на роутере.",
        "nft": "Роутер не смог изменить правила.",
        "subscribe.lua not found": "На роутере нет скрипта подписок PassWall."
    ]

    public static let routerFailedText = "Роутер не смог выполнить действие."
    public static let serverErrorText = "Ошибка на сервере — попробуй через минуту."
    /// (proposed) No HTTP response.
    public static let noConnectionText = "Нет связи с сервером. Проверь интернет и попробуй ещё раз."
    /// (proposed) 2xx with an unusable body (for example a captive portal page).
    public static let badResponseText = "Сервер ответил непонятно — проверь интернет и попробуй ещё раз."
    /// (proposed) Appended to action errors on 504.
    public static let mayHaveExecutedText = "Действие могло выполниться — проверь состояние через минуту."

    /// The message without the retry suffix.
    public var baseMessage: String {
        switch kind {
        case .cancelled:
            return ""
        case .noConnection:
            return APIError.noConnectionText
        case .badResponse:
            return APIError.badResponseText
        case .client:
            if let m = serverMessage, !m.isEmpty {
                return m
            }
            if let t = APIError.fallbackTexts[code] {
                return t
            }
            return APIError.fallbackTexts["bad_param"] ?? ""
        case .http:
            if let m = serverMessage, !m.isEmpty {
                return m
            }
            if let t = APIError.fallbackTexts[code] {
                return t
            }
            if source == "router" {
                return APIError.routerFailedText
            }
            if status >= 500 {
                return APIError.serverErrorText
            }
            return "Запрос не принят (код \(status))."
        }
    }

    /// Ready-to-show Russian text (contract §3.2). For `429 rate_limited` with
    /// `retry_after` it ends with « Повтори через N с.» (or «… M мин.» above 90 s).
    public var userMessage: String {
        var text = baseMessage
        if kind == .http, code == "rate_limited", let r = retryAfter, r > 0 {
            text += Fmt.retrySuffix(r)
        }
        return text
    }

    /// `userMessage` for an action: on 504 adds «Действие могло выполниться…».
    public var actionMessage: String {
        if mayHaveExecuted {
            return userMessage + " " + APIError.mayHaveExecutedText
        }
        return userMessage
    }
}

extension APIError: LocalizedError {
    public var errorDescription: String? {
        return userMessage
    }
}
