import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Transport

/// Sends one request and returns the body and the HTTP response for ANY status code.
/// Throws only when there is no HTTP response (network error, cancellation).
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// The default transport: an ephemeral `URLSession` without cookies or cache.
/// Uses `dataTask` + a continuation, so it works the same on Apple platforms and Linux.
public final class URLSessionTransport: HTTPTransport, @unchecked Sendable {
    public let session: URLSession

    public init(session: URLSession) {
        self.session = session
    }

    public convenience init() {
        self.init(session: URLSession(configuration: URLSessionTransport.makeConfiguration()))
    }

    /// Ephemeral, no cookies, no URL cache. The per-request `timeoutInterval` (15 or 30 s)
    /// is set on each request; the session default is 30 s so it never cuts a valid reply.
    public static func makeConfiguration() -> URLSessionConfiguration {
        let c = URLSessionConfiguration.ephemeral
        c.httpShouldSetCookies = false
        c.httpCookieAcceptPolicy = .never
        c.httpCookieStorage = nil
        c.urlCache = nil
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        c.timeoutIntervalForRequest = Endpoint.slowTimeout
        c.timeoutIntervalForResource = 120
        return c
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let box = DataTaskBox()
        let session = self.session
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<(Data, HTTPURLResponse), Error>) in
                let task = session.dataTask(with: request) { data, response, error in
                    if let error = error {
                        cont.resume(throwing: error)
                        return
                    }
                    guard let http = response as? HTTPURLResponse else {
                        cont.resume(throwing: URLError(.badServerResponse))
                        return
                    }
                    cont.resume(returning: (data ?? Data(), http))
                }
                if box.attach(task) {
                    task.resume()
                } else {
                    cont.resume(throwing: CancellationError())
                }
            }
        }, onCancel: {
            box.cancel()
        })
    }
}

/// Holds the data task so a Swift task cancellation can cancel it.
final class DataTaskBox: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionDataTask?
    private var cancelled = false

    /// Returns false when already cancelled (the task must not be started).
    func attach(_ t: URLSessionDataTask) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if cancelled {
            return false
        }
        task = t
        return true
    }

    func cancel() {
        lock.lock()
        cancelled = true
        let t = task
        lock.unlock()
        t?.cancel()
    }
}

// MARK: - Clock

/// Injectable time source and sleep (tests use an instant fake).
public struct RuntimeClock: Sendable {
    /// Unix seconds.
    public var now: @Sendable () -> TimeInterval
    public var sleep: @Sendable (TimeInterval) async throws -> Void

    public init(now: @escaping @Sendable () -> TimeInterval, sleep: @escaping @Sendable (TimeInterval) async throws -> Void) {
        self.now = now
        self.sleep = sleep
    }

    public static let live = RuntimeClock(
        now: { Date().timeIntervalSince1970 },
        sleep: { seconds in
            guard seconds.isFinite, seconds > 0 else {
                return
            }
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        }
    )
}

// MARK: - Token holder

/// Thread-safe in-memory token holder for `APIClient(tokenProvider:)`.
/// Load it from Keychain at launch; clear it on LOGOUT.
public final class TokenBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: String?

    public init(_ token: String? = nil) {
        value = token
    }

    public var token: String? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    public func set(_ token: String?) {
        lock.lock()
        value = token
        lock.unlock()
    }
}

// MARK: - Response

/// A raw HTTP response. `headers` keys are lowercased.
public struct HTTPResponseData: Equatable, Sendable {
    public var status: Int
    public var body: Data
    public var headers: [String: String]

    public init(status: Int, body: Data, headers: [String: String]) {
        self.status = status
        self.body = body
        self.headers = headers
    }
}

// MARK: - Client

/// The `/router/app/v1` client.
///
/// - Sends `Authorization: Bearer <token>` (header only, never in the URL) on authed routes.
/// - Never sends a missing or malformed token (`token_invalid` counts toward fail2ban):
///   throws `APIError.notLoggedIn` instead, without a request.
/// - Never sends cookies, `Origin` or any query parameter except `range`.
/// - Never retries a POST.
public final class APIClient: @unchecked Sendable {
    /// Ends with "/".
    public let baseURL: URL
    public let transport: HTTPTransport
    public let clock: RuntimeClock
    private let tokenProvider: @Sendable () -> String?

    /// `https://fspirat.xyz/router/app/v1/` (the `APP_BASE_URL` default; not a secret).
    public static let defaultBaseURL = URL(string: "https://fspirat.xyz/router/app/v1/")!

    public init(
        baseURL: URL,
        transport: HTTPTransport = URLSessionTransport(),
        clock: RuntimeClock = .live,
        tokenProvider: @escaping @Sendable () -> String?
    ) {
        let s = baseURL.absoluteString
        if s.hasSuffix("/") {
            self.baseURL = baseURL
        } else {
            self.baseURL = URL(string: s + "/") ?? baseURL
        }
        self.transport = transport
        self.clock = clock
        self.tokenProvider = tokenProvider
    }

    /// Builds the `URLRequest` (exposed for tests). Throws `APIError` (kind `.client`).
    public func makeRequest(_ endpoint: Endpoint) throws -> URLRequest {
        guard APIClient.isSafePath(endpoint.path) else {
            throw APIError.client(code: "bad_param", message: nil)
        }
        var base = baseURL.absoluteString
        if !base.hasSuffix("/") {
            base += "/"
        }
        guard base.lowercased().hasPrefix("https://"), var comps = URLComponents(string: base + endpoint.path) else {
            throw APIError.client(code: "bad_param", message: nil)
        }
        comps.fragment = nil
        if let range = endpoint.range {
            comps.queryItems = [URLQueryItem(name: "range", value: range.rawValue)]
        } else {
            comps.query = nil
        }
        guard let url = comps.url, !url.absoluteString.contains("fsr1_") else {
            throw APIError.client(code: "bad_param", message: nil)
        }

        var req = URLRequest(url: url)
        req.httpMethod = endpoint.method.rawValue
        req.timeoutInterval = endpoint.timeout
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.httpShouldHandleCookies = false
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if endpoint.requiresAuth {
            guard let token = tokenProvider(), Validation.isValidToken(token) else {
                throw APIError.notLoggedIn
            }
            req.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }
        if endpoint.method == .post {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = endpoint.body ?? Data("{}".utf8)
        }
        return req
    }

    /// Sends the request and returns the response for any HTTP status.
    /// Throws `APIError` only for `.client`, `.noConnection` and `.cancelled`.
    public func send(_ endpoint: Endpoint) async throws -> HTTPResponseData {
        let request = try makeRequest(endpoint)
        do {
            let (data, response) = try await transport.send(request)
            return HTTPResponseData(status: response.statusCode, body: data, headers: APIClient.headerMap(response))
        } catch {
            throw APIError.transport(error)
        }
    }

    /// 2xx → decoded `T`; anything else → `APIError`.
    public func request<T: Decodable>(_ endpoint: Endpoint, as type: T.Type) async throws -> T {
        let r = try await send(endpoint)
        guard r.status >= 200 && r.status < 300 else {
            throw APIError.fromHTTP(status: r.status, body: r.body, headers: r.headers)
        }
        return try APIClient.decode(T.self, from: r.body, status: r.status)
    }

    // MARK: - Reads

    public func status() async throws -> RouterStatus {
        return try await request(Endpoint.status, as: RouterStatus.self)
    }

    public func net() async throws -> NetStats {
        return try await request(Endpoint.net, as: NetStats.self)
    }

    public func led() async throws -> LedState {
        return try await request(Endpoint.led, as: LedState.self)
    }

    public func data(range: DataRange = .day) async throws -> DataResponse {
        return try await request(Endpoint.data(range: range), as: DataResponse.self)
    }

    public func me() async throws -> MeResponse {
        return try await request(Endpoint.me, as: MeResponse.self)
    }

    /// `GET /zapret`. 502/504 here must NOT switch offline mode on (only `/status` does).
    public func zapret() async throws -> ZapretState {
        return try await request(Endpoint.zapret, as: ZapretState.self)
    }

    /// `GET /tgws`.
    public func tgws() async throws -> TgwsState {
        return try await request(Endpoint.tgws, as: TgwsState.self)
    }

    /// `GET /mydirect`. `500 no rule` → show the message instead of the lists.
    public func mydirect() async throws -> MyDirectList {
        return try await request(Endpoint.mydirect, as: MyDirectList.self)
    }

    /// `GET /vds` (server file; works offline).
    public func vds() async throws -> VdsResponse {
        return try await request(Endpoint.vds, as: VdsResponse.self)
    }

    /// `GET /devices` (who has access; server-only, works offline).
    public func accessList() async throws -> AccessList {
        return try await request(Endpoint.devices, as: AccessList.self)
    }

    // MARK: - Auth

    /// `POST /auth/login`. Refuses locally (no request) an empty/oversized password or an empty name.
    public func login(password: String, device: DeviceInfo) async throws -> LoginChallenge {
        guard Validation.isValidPassword(password) else {
            throw APIError.client(code: "bad_param", message: LoginTexts.passwordRequired)
        }
        guard !device.name.isEmpty else {
            throw APIError.client(code: "bad_param", message: LoginTexts.nameRequired)
        }
        return try await request(Endpoint.login(password: password, device: device), as: LoginChallenge.self)
    }

    /// `POST /auth/poll`.
    public func poll(loginID: String) async throws -> PollResult {
        guard Validation.isValidLoginID(loginID) else {
            throw APIError.client(code: "bad_param", message: nil)
        }
        return try await request(Endpoint.poll(loginID: loginID), as: PollResult.self)
    }

    /// `POST /auth/cancel`. Any 200 means the login is closed.
    public func cancelLogin(loginID: String) async throws -> CancelResult {
        guard Validation.isValidLoginID(loginID) else {
            throw APIError.client(code: "bad_param", message: nil)
        }
        return try await request(Endpoint.cancelLogin(loginID: loginID), as: CancelResult.self)
    }

    /// `POST /auth/logout`. The caller deletes the token whatever this returns or throws.
    public func logout() async throws {
        _ = try await request(Endpoint.logout, as: JSONValue.self)
    }

    // MARK: - Helpers

    static func decode<T: Decodable>(_ type: T.Type, from data: Data, status: Int) throws -> T {
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.badResponse(status: status)
        }
    }

    static func headerMap(_ response: HTTPURLResponse) -> [String: String] {
        var out: [String: String] = [:]
        for (key, value) in response.allHeaderFields {
            guard let k = key as? String else {
                continue
            }
            if let v = value as? String {
                out[k.lowercased()] = v
            } else {
                out[k.lowercased()] = "\(value)"
            }
        }
        return out
    }

    /// Lowercase letters, digits, `-` (`devices/revoke-all`) and single slashes; no leading slash, no `..`.
    static func isSafePath(_ path: String) -> Bool {
        if path.isEmpty || path.hasPrefix("/") || path.hasSuffix("/") || path.contains("//") || path.hasPrefix("-") {
            return false
        }
        for u in path.unicodeScalars {
            let v = u.value
            let ok = (v >= 0x61 && v <= 0x7A) || (v >= 0x30 && v <= 0x39) || v == 0x2F || v == 0x2D
            if !ok {
                return false
            }
        }
        return true
    }
}
