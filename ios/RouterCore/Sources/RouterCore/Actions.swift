import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Confirm (428)

public enum Danger: String, Equatable, Sendable {
    case critical
    case high
    case medium

    /// Unknown values are treated as `critical` (the strictest).
    public init(serverValue: String) {
        self = Danger(rawValue: serverValue) ?? .critical
    }
}

/// The 428 `confirm_required` body (contract §2.11). Show `title`, `text`, «Отмена» and `button` verbatim.
public struct ConfirmPrompt: Decodable, Equatable, Sendable {
    /// 32 lowercase hex, single use. Resend it as `confirm` within `expiresIn`.
    public var confirm: String
    public var expiresIn: Int
    public var danger: Danger
    public var title: String
    public var text: String
    public var button: String
    public var message: String
    /// When the client received it (unix seconds, set by `APIClient`).
    public var receivedAt: TimeInterval

    public init(confirm: String, expiresIn: Int, danger: Danger, title: String, text: String, button: String, message: String = "Нужно подтверждение.", receivedAt: TimeInterval = 0) {
        self.confirm = confirm
        self.expiresIn = expiresIn
        self.danger = danger
        self.title = title
        self.text = text
        self.button = button
        self.message = message
        self.receivedAt = receivedAt
    }

    public init(from decoder: Decoder) throws {
        let v = try JSONValue.decodeObject(from: decoder)
        guard let c = v.str("confirm"), Validation.isValidConfirm(c) else {
            throw JSONValue.shapeError(decoder, "confirm")
        }
        confirm = c
        expiresIn = v.num("expires_in") ?? 60
        danger = Danger(serverValue: v.str("danger") ?? "")
        title = v.str("title") ?? ""
        text = v.str("text") ?? ""
        button = v.str("button") ?? ""
        message = v.str("message") ?? ""
        receivedAt = 0
    }

    /// `danger == critical`: destructive (red) confirm button.
    public var isDestructive: Bool {
        return danger == .critical
    }

    /// `danger == critical`: run Face ID / passcode after the tap and before the resend
    /// (when the setting «Для опасных действий» is on).
    public var requiresBiometrics: Bool {
        return danger == .critical
    }

    /// Title to show; falls back to the server `message`.
    public var displayTitle: String {
        if !title.isEmpty {
            return title
        }
        return message.isEmpty ? "Нужно подтверждение." : message
    }

    /// Confirm button label; falls back to «Подтвердить» (proposed).
    public var displayButton: String {
        return button.isEmpty ? "Подтвердить" : button
    }

    /// The resend is allowed only while the dialog has been open < min(55, expiresIn − 5) s.
    /// Otherwise start again without `confirm` (a fresh 428).
    public func canResend(now: TimeInterval) -> Bool {
        let limit = min(55.0, Double(expiresIn) - 5)
        return now - receivedAt < limit
    }
}

// MARK: - Outcomes and jobs

/// The result of `APIClient.perform(_:confirm:)` for 200, 202 and 428.
/// Every other status is thrown as `APIError`.
public enum ActionOutcome: Equatable, Sendable {
    /// 200: the router body, e.g. `{"ok":true}` or the new LED state.
    case done(JSONValue)
    /// 428: show the dialog, then call `perform(action, confirm: prompt.confirm)`.
    case confirm(ConfirmPrompt)
    /// 202: poll with `waitForJob(id:pollEvery:)`.
    case job(id: String, pollEvery: Int)
}

/// 202 body `{"job":"<16 hex>","poll_every":3}`.
public struct JobStart: Decodable, Equatable, Sendable {
    public var job: String
    public var pollEvery: Int

    public init(from decoder: Decoder) throws {
        let v = try JSONValue.decodeObject(from: decoder)
        guard let id = v.str("job"), Validation.isValidJobID(id) else {
            throw JSONValue.shapeError(decoder, "job")
        }
        job = id
        pollEvery = v.num("poll_every") ?? 3
    }
}

/// A finished job.
public struct JobDone: Equatable, Sendable {
    public var action: String
    public var http: Int
    /// The raw router JSON.
    public var result: JSONValue
    /// For `ping`: the result decoded as a full status (replace the stored status with it).
    public var status: RouterStatus?

    public init(action: String, http: Int, result: JSONValue, status: RouterStatus?) {
        self.action = action
        self.http = http
        self.result = result
        self.status = status
    }
}

/// `GET /jobs/{id}` body.
public enum JobStatus: Decodable, Equatable, Sendable {
    case running(action: String)
    case done(JobDone)
    /// `state: "error"`; the error carries `http`, `error`, `message`, `source`.
    case failed(action: String, error: APIError)

    public init(from decoder: Decoder) throws {
        let v = try JSONValue.decodeObject(from: decoder)
        let state = v.str("state") ?? ""
        let action = v.str("action") ?? ""
        if state == "done" {
            let result = v["result"] ?? JSONValue.null
            var status: RouterStatus? = nil
            if action == "ping" && result.isObject {
                status = RouterStatus(json: result)
            }
            self = .done(JobDone(action: action, http: v.num("http") ?? 200, result: result, status: status))
            return
        }
        if state == "error" {
            var message: String? = nil
            if let m = v["message"], case .string(let text) = m, !text.isEmpty {
                message = text
            }
            var source: String? = nil
            if let s = v["source"], case .string(let text) = s {
                source = text
            }
            let error = APIError(
                kind: .http,
                status: v.num("http") ?? 500,
                code: v.str("error") ?? "server_error",
                serverMessage: message,
                source: source,
                bodyIsJSON: true
            )
            self = .failed(action: action, error: error)
            return
        }
        self = .running(action: action)
    }
}

// MARK: - Client: actions

extension APIClient {
    /// `POST /action/<name>` with an optional `confirm` (contract §2.10–2.11).
    /// Never retries. `confirm` is refused locally for non-confirmable actions.
    public func perform(_ action: RouterAction, confirm: String? = nil) async throws -> ActionOutcome {
        if let c = confirm {
            guard action.isConfirmable, Validation.isValidConfirm(c) else {
                throw APIError.client(code: "bad_param", message: nil)
            }
        }
        let r = try await send(Endpoint.action(action, confirm: confirm))
        if r.status == 202 {
            let start = try APIClient.decode(JobStart.self, from: r.body, status: r.status)
            return .job(id: start.job, pollEvery: start.pollEvery)
        }
        if r.status >= 200 && r.status < 300 {
            let trimmed = String(decoding: r.body, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return .done(.null)
            }
            return .done(try APIClient.decode(JSONValue.self, from: r.body, status: r.status))
        }
        if r.status == 428 {
            if var prompt = try? JSONDecoder().decode(ConfirmPrompt.self, from: r.body) {
                prompt.receivedAt = clock.now()
                return .confirm(prompt)
            }
        }
        throw APIError.fromHTTP(status: r.status, body: r.body, headers: r.headers)
    }

    /// `ledset`: returns the new LED state from the 200 body.
    public func setLED(on: Bool) async throws -> LedState {
        let outcome = try await perform(.ledset(on: on))
        guard case .done(let value) = outcome, value.isObject else {
            throw APIError.badResponse(status: 200)
        }
        return LedState(json: value)
    }

    /// `GET /jobs/{id}` once.
    public func job(id: String) async throws -> JobStatus {
        guard Validation.isValidJobID(id) else {
            throw APIError.client(code: "not_found", message: nil)
        }
        return try await request(Endpoint.job(id: id), as: JobStatus.self)
    }

    /// Polls the job every `pollEvery` s until done.
    /// - Returns: the finished job.
    /// - Throws: the job's own error (`state: "error"`), a non-transient request error
    ///   (auth, 404, 400), or `APIError.jobTimedOut` after `timeout` (160 s).
    ///   Transient errors (no connection, 429, 5xx) are skipped until the timeout.
    public func waitForJob(id: String, pollEvery: Int, timeout: TimeInterval = 160) async throws -> JobDone {
        let started = clock.now()
        let interval = TimeInterval(min(max(pollEvery, 1), 10))
        while true {
            try await clock.sleep(interval)
            try Task.checkCancellation()
            var current: JobStatus? = nil
            do {
                current = try await job(id: id)
            } catch let e as APIError {
                if !e.isTransient {
                    throw e
                }
            }
            if let st = current {
                switch st {
                case .done(let d):
                    return d
                case .failed(_, let e):
                    throw e
                case .running:
                    break
                }
            }
            if clock.now() - started >= timeout {
                throw APIError.jobTimedOut
            }
        }
    }
}

// MARK: - Texts and behaviour after actions

public enum ActionTexts {
    /// Toast after a finished ping job.
    public static let pingDone = "Проверка серверов завершена."
    /// Busy label of «Проверить».
    public static let pingBusy = "Проверяю, ~20 сек…"
    /// (proposed) A ping job answered 504 or ran longer than the client limit.
    public static let pingSlow = "Проверка идёт дольше обычного — результат появится в Сводке через минуту."
    /// (proposed, inventory §7.10) The job returned the data of an older check.
    public static let staleResult = "Показаны данные последней проверки"

    /// Message for a failed ping job: 504 / client timeout → «Проверка идёт дольше обычного…».
    public static func pingJobErrorMessage(_ error: APIError) -> String {
        if error.code == "router_timeout" || error.code == "job_timeout" {
            return pingSlow
        }
        return error.userMessage
    }

    /// `result.ping.updated < jobStartedAt - 5` → show `staleResult`.
    public static func isStale(_ status: RouterStatus, jobStartedAt: TimeInterval) -> Bool {
        guard let updated = status.ping?.updated else {
            return false
        }
        return Double(updated) < jobStartedAt - 5
    }
}

/// Router buttons on «Сводка».
public enum SummaryButton: String, CaseIterable, Sendable {
    case check
    case restartVPN
    case updateSubs
    case reboot
    case led

    public var title: String {
        switch self {
        case .check:
            return "Проверить"
        case .restartVPN:
            return "Перезапустить VPN"
        case .updateSubs:
            return "Обновить подписки"
        case .reboot:
            return "Перезагрузить роутер"
        case .led:
            return "Подсветка"
        }
    }

    /// SF Symbol.
    public var symbol: String {
        switch self {
        case .check:
            return "arrow.clockwise"
        case .restartVPN:
            return "arrow.counterclockwise"
        case .updateSubs:
            return "arrow.down"
        case .reboot:
            return "power"
        case .led:
            return "lightbulb"
        }
    }
}

/// What to do after a 200 (contract §7.2).
public struct ActionAftermath: Equatable, Sendable {
    /// During it: `/status` errors are suppressed (no offline mode), `/net` is paused, the banner shows.
    public var quietWindow: TimeInterval
    /// Re-read `/status` after this many seconds (`nil` = no extra read).
    public var rereadStatusAfter: TimeInterval?
    /// Buttons disabled for `disabledFor` seconds.
    public var disabledButtons: [SummaryButton]
    public var disabledFor: TimeInterval
    public var banner: String?
    public var toast: String?

    public init(quietWindow: TimeInterval, rereadStatusAfter: TimeInterval?, disabledButtons: [SummaryButton], disabledFor: TimeInterval, banner: String?, toast: String?) {
        self.quietWindow = quietWindow
        self.rereadStatusAfter = rereadStatusAfter
        self.disabledButtons = disabledButtons
        self.disabledFor = disabledFor
        self.banner = banner
        self.toast = toast
    }

    public static func after(_ action: RouterAction) -> ActionAftermath {
        switch action {
        case .restart:
            return ActionAftermath(
                quietWindow: 15, rereadStatusAfter: 15,
                disabledButtons: [.check, .restartVPN, .updateSubs, .reboot], disabledFor: 15,
                banner: "VPN перезапускается…", toast: "VPN перезапускается."
            )
        case .update:
            return ActionAftermath(
                quietWindow: 0, rereadStatusAfter: 60,
                disabledButtons: [.restartVPN, .updateSubs], disabledFor: 15,
                banner: nil,
                toast: "Подписки обновляются — список серверов обновится через 1–2 минуты, потом VPN перезапустится на несколько секунд."
            )
        case .reboot:
            return ActionAftermath(
                quietWindow: 150, rereadStatusAfter: 150,
                disabledButtons: [.check, .restartVPN, .updateSubs, .reboot, .led], disabledFor: 150,
                banner: "Роутер перезагружается…",
                toast: "Роутер перезагружается. Приложение само обновится, когда он вернётся."
            )
        case .ping:
            return ActionAftermath(
                quietWindow: 0, rereadStatusAfter: nil,
                disabledButtons: [], disabledFor: 0,
                banner: nil, toast: ActionTexts.pingDone
            )
        case .ledset(let on):
            return ActionAftermath(
                quietWindow: 0, rereadStatusAfter: nil,
                disabledButtons: [], disabledFor: 0,
                banner: nil, toast: on ? "Подсветка роутера включена." : "Подсветка роутера выключена."
            )
        }
    }
}

/// App pre-dialog before «Проверить» (contract §7.4). No Face ID, no server confirm.
public enum PingPreDialog {
    public static let title = "VPN сейчас не проходит. Проверить?"
    public static let text = "Если проверка снова не пройдёт, роутер сам переключит сервер, и VPN перезапустится на несколько секунд."
    public static let cancel = "Отмена"
    public static let confirm = "Проверить"

    /// `ping != nil && ping.socks == true && ping.real == 0` (`null` does not count).
    public static func isNeeded(_ status: RouterStatus?) -> Bool {
        guard let p = status?.ping else {
            return false
        }
        return p.socks == true && p.real == 0
    }
}
