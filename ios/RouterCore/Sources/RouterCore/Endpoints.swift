import Foundation

public enum HTTPMethod: String, Equatable, Sendable {
    case get = "GET"
    case post = "POST"
}

/// The stage 3 actions (`POST /action/<name>`, contract §2.10).
public enum RouterAction: Equatable, Sendable {
    /// Job (202), no confirm. App pre-dialog only when `Summary.needsPingPreDialog`.
    case ping
    /// 428 confirm, danger high.
    case restart
    /// 428 confirm, danger high.
    case update
    /// 428 confirm, danger critical (Face ID).
    case reboot
    /// No confirm; `on` must be a JSON bool.
    case ledset(on: Bool)

    /// The path name after `action/`.
    public var name: String {
        switch self {
        case .ping:
            return "ping"
        case .restart:
            return "restart"
        case .update:
            return "update"
        case .reboot:
            return "reboot"
        case .ledset:
            return "ledset"
        }
    }

    /// The server answers 428 without `confirm`.
    public var isConfirmable: Bool {
        switch self {
        case .restart, .update, .reboot:
            return true
        case .ping, .ledset:
            return false
        }
    }

    /// The server answers 202 with a job.
    public var isJob: Bool {
        if case .ping = self {
            return true
        }
        return false
    }
}

/// Login `device` object. Values are sanitized on init (never rejected).
public struct DeviceInfo: Encodable, Equatable, Sendable {
    /// Trimmed, no control characters, ≤ 40 code points.
    public var name: String
    /// `utsname.machine`, e.g. "iPhone15,2"; printable ASCII ≤ 32.
    public var model: String
    /// "iOS 18.1"; printable ASCII ≤ 32.
    public var os: String
    /// "1.0 (42)"; printable ASCII ≤ 32.
    public var app: String

    public init(name: String, model: String = "", os: String = "", app: String = "") {
        self.name = Validation.sanitizeDeviceName(name)
        self.model = Validation.sanitizeASCII(model)
        self.os = Validation.sanitizeASCII(os)
        self.app = Validation.sanitizeASCII(app)
    }
}

/// One request to `/router/app/v1`. Build with the static constructors.
public struct Endpoint: Equatable, Sendable {
    public var method: HTTPMethod
    /// Relative to the base URL, no leading slash, e.g. "status", "action/restart", "jobs/<id>".
    public var path: String
    /// The only allowed query parameter (`/data`).
    public var range: DataRange?
    /// JSON body for POST (`{}` when nil).
    public var body: Data?
    public var requiresAuth: Bool
    /// `URLRequest.timeoutInterval` (contract §1.5).
    public var timeout: TimeInterval

    public init(method: HTTPMethod, path: String, range: DataRange? = nil, body: Data? = nil, requiresAuth: Bool, timeout: TimeInterval) {
        self.method = method
        self.path = path
        self.range = range
        self.body = body
        self.requiresAuth = requiresAuth
        self.timeout = timeout
    }

    /// `/status` and every `/action/*`.
    public static let slowTimeout: TimeInterval = 30
    /// Everything else.
    public static let normalTimeout: TimeInterval = 15

    public static func login(password: String, device: DeviceInfo) -> Endpoint {
        return Endpoint(method: .post, path: "auth/login", body: encode(LoginBody(password: password, device: device)), requiresAuth: false, timeout: normalTimeout)
    }

    public static func poll(loginID: String) -> Endpoint {
        return Endpoint(method: .post, path: "auth/poll", body: encode(LoginIDBody(login_id: loginID)), requiresAuth: false, timeout: normalTimeout)
    }

    public static func cancelLogin(loginID: String) -> Endpoint {
        return Endpoint(method: .post, path: "auth/cancel", body: encode(LoginIDBody(login_id: loginID)), requiresAuth: false, timeout: normalTimeout)
    }

    public static var logout: Endpoint {
        return Endpoint(method: .post, path: "auth/logout", body: Data("{}".utf8), requiresAuth: true, timeout: normalTimeout)
    }

    public static var me: Endpoint {
        return Endpoint(method: .get, path: "me", requiresAuth: true, timeout: normalTimeout)
    }

    public static var status: Endpoint {
        return Endpoint(method: .get, path: "status", requiresAuth: true, timeout: slowTimeout)
    }

    public static var net: Endpoint {
        return Endpoint(method: .get, path: "net", requiresAuth: true, timeout: normalTimeout)
    }

    public static var led: Endpoint {
        return Endpoint(method: .get, path: "led", requiresAuth: true, timeout: normalTimeout)
    }

    public static func data(range: DataRange) -> Endpoint {
        return Endpoint(method: .get, path: "data", range: range, requiresAuth: true, timeout: normalTimeout)
    }

    public static func job(id: String) -> Endpoint {
        return Endpoint(method: .get, path: "jobs/" + id, requiresAuth: true, timeout: normalTimeout)
    }

    /// `POST /action/<name>`. Body: `{}`, `{"confirm":…}`, `{"on":bool}` or `{"confirm":…,"on":bool}`.
    public static func action(_ action: RouterAction, confirm: String? = nil) -> Endpoint {
        var on: Bool? = nil
        if case .ledset(let value) = action {
            on = value
        }
        let body = encode(ActionBody(confirm: confirm, on: on))
        return Endpoint(method: .post, path: "action/" + action.name, body: body, requiresAuth: true, timeout: slowTimeout)
    }

    // MARK: - Bodies

    struct LoginBody: Encodable {
        var password: String
        var device: DeviceInfo
    }

    struct LoginIDBody: Encodable {
        var login_id: String
    }

    struct ActionBody: Encodable {
        var confirm: String?
        var on: Bool?
    }

    static func encode<T: Encodable>(_ value: T) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(value) {
            return data
        }
        return Data("{}".utf8)
    }
}
