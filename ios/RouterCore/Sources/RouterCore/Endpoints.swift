import Foundation

public enum HTTPMethod: String, Equatable, Sendable {
    case get = "GET"
    case post = "POST"
}

/// Speed test channel.
public enum SpeedVia: String, CaseIterable, Equatable, Sendable {
    case vpn
    case direct
}

/// Every action of `/router/app/v1` (contract §2.10, contract-stage4 §3, §3.4).
/// Build the case, check `validationError` (or let `APIClient.perform` refuse it locally), then send.
/// MACs are lowercased in the body; send `.diradd`/`.dirdel` only with a domain from `MyDirect.check`.
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
    /// `{"id"}`: TCP ping of one server, no confirm. Not for `direct`/`_direct`.
    case pingone(id: String)
    /// `{"id"}`: connect a node (428 high) or `"direct"` (428 critical, Face ID). Use `.switchDirect` for no VPN.
    case switchServer(id: String)
    /// `{"sid"}`: refresh one subscription (428 high).
    case subupdate(sid: String)
    /// `{"all":true}`: refresh every subscription (428 high).
    case subupdateAll
    /// `{"via"}`: job (202), no confirm.
    case speedtest(via: SpeedVia)
    /// `{"mac"}`: 428 high, red button (no Face ID).
    case block(mac: String)
    /// `{"mac"}`: no confirm.
    case unblock(mac: String)
    /// `{"mac","on"}`: 428 high.
    case direct(mac: String, on: Bool)
    /// `{"mac","off":"HHMM","on":"HHMM"}`: 428 medium; `off != on`.
    case schedule(mac: String, off: String, on: String)
    /// `{"mac","off":"","on":""}`: no confirm.
    case scheduleClear(mac: String)
    /// `{"d"}`: add a MyDirect domain (428 high).
    case diradd(domain: String)
    /// `{"d"}`: remove an `added` MyDirect domain (428 high, red button).
    case dirdel(domain: String)
    /// `{"name","on"}`: a service directly / through VPN (428 high).
    case svcdirect(name: String, on: Bool)
    /// `{"on"}`: zapret on/off (428 high).
    case zapretset(on: Bool)
    /// `{"n"}` (JSON int 1…3): no confirm; verify afterwards (`Zapret.verifyStrategy`).
    case zapretstrat(n: Int)
    /// `{}`: start the YouTube/Discord check, no confirm.
    case zapretcheck
    /// `{"on"}`: Telegram via Cloudflare (428 medium).
    case tgwsset(on: Bool)
    /// `{"mac","name"}`: own device name (`""` removes it), no confirm; works while the router is offline.
    case rename(mac: String, name: String)
    /// `POST /devices/revoke {"id"}`: revoke an app key. No server confirm (app dialog first).
    case revokeApp(id: String)
    /// `POST /devices/revoke {"web_ref"}`: close a web session. No server confirm (app dialog first).
    case revokeWeb(ref: String)
    /// `POST /devices/revoke-all {"web"}`: 428 critical (Face ID, red). Revokes this phone too → LOGOUT after 200.
    case revokeAll(web: Bool)

    /// `switch {"id":"direct"}`: all traffic without VPN.
    public static let switchDirect = RouterAction.switchServer(id: "direct")

    /// The action name used by the server (also the last path component for `/action/*`).
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
        case .pingone:
            return "pingone"
        case .switchServer:
            return "switch"
        case .subupdate, .subupdateAll:
            return "subupdate"
        case .speedtest:
            return "speedtest"
        case .block:
            return "block"
        case .unblock:
            return "unblock"
        case .direct:
            return "direct"
        case .schedule, .scheduleClear:
            return "schedule"
        case .diradd:
            return "diradd"
        case .dirdel:
            return "dirdel"
        case .svcdirect:
            return "svcdirect"
        case .zapretset:
            return "zapretset"
        case .zapretstrat:
            return "zapretstrat"
        case .zapretcheck:
            return "zapretcheck"
        case .tgwsset:
            return "tgwsset"
        case .rename:
            return "rename"
        case .revokeApp, .revokeWeb:
            return "revoke"
        case .revokeAll:
            return "revoke-all"
        }
    }

    /// Path relative to the base URL: `action/<name>`, `devices/revoke` or `devices/revoke-all`.
    public var path: String {
        switch self {
        case .revokeApp, .revokeWeb:
            return "devices/revoke"
        case .revokeAll:
            return "devices/revoke-all"
        default:
            return "action/" + name
        }
    }

    /// The server answers 428 without `confirm` (`APP_CONFIRMABLE`; schedule clear is not).
    public var isConfirmable: Bool {
        switch self {
        case .restart, .update, .reboot, .switchServer, .subupdate, .subupdateAll, .block, .direct, .schedule,
             .diradd, .dirdel, .svcdirect, .zapretset, .tgwsset, .revokeAll:
            return true
        case .ping, .ledset, .pingone, .speedtest, .unblock, .scheduleClear, .zapretstrat, .zapretcheck, .rename,
             .revokeApp, .revokeWeb:
            return false
        }
    }

    /// The server answers 202 with a job (`ping`, `speedtest`).
    public var isJob: Bool {
        switch self {
        case .ping, .speedtest:
            return true
        default:
            return false
        }
    }

    /// `switch {"id":"direct"}`.
    public var isSwitchDirect: Bool {
        if case .switchServer(let id) = self {
            return id == "direct"
        }
        return false
    }

    /// PW class: restarts PassWall; one per 15 s across all devices (`switch, restart, update, subupdate,
    /// direct, diradd, dirdel, svcdirect, zapretset`). Every PW control in the app is disabled during the lock-out.
    public var isPassWall: Bool {
        switch self {
        case .switchServer, .restart, .update, .subupdate, .subupdateAll, .direct, .diradd, .dirdel, .svcdirect, .zapretset:
            return true
        default:
            return false
        }
    }

    /// The danger the server is expected to send with its 428 (`nil` = no confirm).
    public var expectedDanger: Danger? {
        guard isConfirmable else {
            return nil
        }
        switch self {
        case .reboot, .revokeAll:
            return .critical
        case .switchServer(let id):
            return id == "direct" ? .critical : .high
        case .schedule, .tgwsset:
            return .medium
        default:
            return .high
        }
    }

    /// The app styles the confirm button red for these even though the server sends `high`
    /// (`block`, `dirdel`; `revoke-all` is critical anyway). Use `ConfirmPrompt.isDestructive(for:)`.
    public var forcesDestructiveConfirm: Bool {
        switch self {
        case .block, .dirdel, .revokeAll:
            return true
        default:
            return false
        }
    }

    /// Works while the router is offline (server-only): `rename` and the device revokes.
    public var worksOffline: Bool {
        switch self {
        case .rename, .revokeApp, .revokeWeb, .revokeAll:
            return true
        default:
            return false
        }
    }

    /// Ready-made Russian text when the parameters would be refused by the server (`400 bad_param` /
    /// `too_long`), else `nil`. Never send an action with a non-nil value.
    public var validationError: String? {
        return Validation.actionError(self)?.userMessage
    }

    /// The JSON body keys (without `confirm`), exactly as the server expects them.
    public var bodyFields: [String: JSONValue] {
        switch self {
        case .ping, .restart, .update, .reboot, .zapretcheck:
            return [:]
        case .ledset(let on), .zapretset(let on), .tgwsset(let on):
            return ["on": .bool(on)]
        case .pingone(let id), .switchServer(let id):
            return ["id": .string(id)]
        case .subupdate(let sid):
            return ["sid": .string(sid)]
        case .subupdateAll:
            return ["all": .bool(true)]
        case .speedtest(let via):
            return ["via": .string(via.rawValue)]
        case .block(let mac), .unblock(let mac):
            return ["mac": .string(mac.lowercased())]
        case .direct(let mac, let on):
            return ["mac": .string(mac.lowercased()), "on": .bool(on)]
        case .schedule(let mac, let off, let on):
            return ["mac": .string(mac.lowercased()), "off": .string(off), "on": .string(on)]
        case .scheduleClear(let mac):
            return ["mac": .string(mac.lowercased()), "off": .string(""), "on": .string("")]
        case .diradd(let d), .dirdel(let d):
            return ["d": .string(d)]
        case .svcdirect(let name, let on):
            return ["name": .string(name), "on": .bool(on)]
        case .zapretstrat(let n):
            return ["n": .int(n)]
        case .rename(let mac, let name):
            return ["mac": .string(mac.lowercased()), "name": .string(Validation.renameValue(name))]
        case .revokeApp(let id):
            return ["id": .string(id)]
        case .revokeWeb(let ref):
            return ["web_ref": .string(ref)]
        case .revokeAll(let web):
            return ["web": .bool(web)]
        }
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

    public static var zapret: Endpoint {
        return Endpoint(method: .get, path: "zapret", requiresAuth: true, timeout: normalTimeout)
    }

    public static var tgws: Endpoint {
        return Endpoint(method: .get, path: "tgws", requiresAuth: true, timeout: normalTimeout)
    }

    public static var mydirect: Endpoint {
        return Endpoint(method: .get, path: "mydirect", requiresAuth: true, timeout: normalTimeout)
    }

    public static var vds: Endpoint {
        return Endpoint(method: .get, path: "vds", requiresAuth: true, timeout: normalTimeout)
    }

    /// `GET /devices` (who has access: phones, web sessions, logins, login journal).
    public static var devices: Endpoint {
        return Endpoint(method: .get, path: "devices", requiresAuth: true, timeout: normalTimeout)
    }

    /// `POST /action/<name>` (or `/devices/revoke*`). Body = `action.bodyFields` (+ `confirm`), keys sorted.
    /// Timeout 30 s for `/action/*`, 15 s for `/devices/*`.
    public static func action(_ action: RouterAction, confirm: String? = nil) -> Endpoint {
        var fields = action.bodyFields
        if let c = confirm {
            fields["confirm"] = .string(c)
        }
        let body = encode(JSONValue.object(fields))
        let timeout = action.path.hasPrefix("action/") ? slowTimeout : normalTimeout
        return Endpoint(method: .post, path: action.path, body: body, requiresAuth: true, timeout: timeout)
    }

    // MARK: - Bodies

    struct LoginBody: Encodable {
        var password: String
        var device: DeviceInfo
    }

    struct LoginIDBody: Encodable {
        var login_id: String
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
