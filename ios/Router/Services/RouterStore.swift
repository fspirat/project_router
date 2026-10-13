import Foundation
import Observation
import RouterCore

/// Where the user is: login form, waiting for the bot, or inside the app.
enum SessionState: Equatable {
    case loggedOut
    case waitingForBot
    case loggedIn
}

/// The reads that are polled while «Сводка» is on screen (contract §7.1).
enum ReadKind: Hashable, CaseIterable {
    case status
    case net
    case data
    case led
    case me

    /// Seconds between reads.
    var interval: TimeInterval {
        switch self {
        case .status:
            return 30
        case .net:
            return 3
        case .data:
            return 60
        case .led:
            return 300
        case .me:
            return 1800
        }
    }
}

/// A 428 dialog waiting for the user.
struct PendingConfirm: Identifiable, Equatable {
    let action: RouterAction
    let button: SummaryButton
    let prompt: ConfirmPrompt

    var id: String {
        return prompt.confirm
    }
}

/// The single app state (inventory §9.1): session, data, polling and actions.
///
/// - Data lives only in memory; the token is in Keychain, `SessionInfo` (not secret) in UserDefaults.
/// - Polling runs only while the Summary is visible and the app is active (`runPolling()` is started
///   from the view's `.task(id:)` and cancelled with it). One request per kind at a time.
/// - Any `401 token_*` → LOGOUT: token deleted, polling stopped, login screen with the server message.
@Observable
@MainActor
final class RouterStore {
    let client: APIClient
    let loginFlow: LoginFlow
    let keychain: KeychainStore
    let tokenBox: TokenBox

    // MARK: Session and login

    var session: SessionState = .loggedOut
    var sessionInfo: SessionInfo? = nil
    var me: MeResponse? = nil
    /// Banner on the login form (errors, «Срок входа истёк…» after a logout).
    var loginMessage: String? = nil
    var loginBusy: Bool = false
    /// `429 locked / rate_limited` on login: «Войти» is disabled until then.
    var loginBlockedUntil: Date? = nil
    var challenge: LoginChallenge? = nil
    var loginDeadline: Date? = nil
    var offerFaceID: Bool = false

    // MARK: Data (memory only)

    var status: RouterStatus? = nil
    var net: NetStats? = nil
    var led: LedState? = nil
    var dayData: DataResponse? = nil
    /// The last successful `/status` (or ping job result).
    var lastStatusAt: Date? = nil
    var firstLoadFinished: Bool = false
    /// Offline mode (contract §7.5).
    var offline: Bool = false
    /// `503 app_disabled`: full-screen state, the token is kept.
    var appDisabled: Bool = false
    /// A `/status` error that is not offline mode (server down, no connection, …).
    var statusError: String? = nil

    // MARK: Actions and presentation

    var runningAction: SummaryButton? = nil
    var disabledButtons: Set<SummaryButton> = []
    var quietBanner: String? = nil
    var ledBusy: Bool = false
    var pendingConfirm: PendingConfirm? = nil
    var confirmBusy: Bool = false
    var confirmError: String? = nil
    var showPingPreDialog: Bool = false
    var isSettingsPresented: Bool = false
    var toast: ToastMessage? = nil
    var successTick: Int = 0
    var errorTick: Int = 0

    // MARK: Bookkeeping (not observed)

    /// The «Интернет сейчас» card is on screen (`/net` is polled only then).
    @ObservationIgnored var netCardVisible: Bool = false
    /// Bumped on every login/logout: late answers of an old session are dropped.
    @ObservationIgnored var sessionEpoch: Int = 0
    @ObservationIgnored var inFlight: Set<ReadKind> = []
    @ObservationIgnored var retryUntil: [ReadKind: Date] = [:]
    @ObservationIgnored var lastReadAt: [ReadKind: Date] = [:]
    @ObservationIgnored var badReplyStreak: Int = 0
    @ObservationIgnored var quietUntil: Date? = nil
    @ObservationIgnored var disabledUntil: [SummaryButton: Date] = [:]
    @ObservationIgnored var timers: [Task<Void, Never>] = []
    @ObservationIgnored var actionTask: Task<Void, Never>? = nil
    @ObservationIgnored var loginTask: Task<Void, Never>? = nil
    @ObservationIgnored var pollingCount: Int = 0

    init(keychain: KeychainStore = KeychainStore(), baseURL: URL = AppConfig.baseURL) {
        let box = TokenBox()
        let apiClient = APIClient(baseURL: baseURL, tokenProvider: { box.token })
        self.keychain = keychain
        self.tokenBox = box
        self.client = apiClient
        self.loginFlow = LoginFlow(client: apiClient)
        // First launch of this install: Keychain outlives a delete + reinstall, UserDefaults (and the
        // Face ID setting) do not. A token left from the old install is deleted here and revoked on the
        // server below, so a reinstall never opens the app logged in without the lock.
        var leftover: String? = nil
        if !UserDefaults.standard.bool(forKey: AppSettings.installMarkerKey) {
            UserDefaults.standard.set(true, forKey: AppSettings.installMarkerKey)
            leftover = keychain.readToken()
            keychain.deleteToken()
            RouterStore.clearSessionInfo()
        }
        if let token = keychain.readToken() {
            box.set(token)
            session = .loggedIn
            sessionInfo = RouterStore.loadSessionInfo()
        } else {
            session = .loggedOut
            sessionInfo = nil
            RouterStore.clearSessionInfo()
        }
        if let old = leftover {
            RouterStore.revokeDetached(old, like: apiClient)
        }
    }

    var isLoggedIn: Bool {
        return session == .loggedIn
    }

    var pollingActive: Bool {
        return pollingCount > 0
    }

    var isQuiet: Bool {
        guard let until = quietUntil else {
            return false
        }
        return until > Date()
    }

    // MARK: - Login (contract §7.6)

    func loginBlockedSeconds(now: Date) -> Int {
        guard let until = loginBlockedUntil else {
            return 0
        }
        let left = until.timeIntervalSince(now)
        if left <= 0 {
            return 0
        }
        return Int(left.rounded(.up))
    }

    func loginSecondsLeft(now: Date) -> Int {
        guard let deadline = loginDeadline else {
            return 0
        }
        return LoginFlow.secondsLeft(deadline: deadline.timeIntervalSince1970, now: now.timeIntervalSince1970)
    }

    /// `POST /auth/login`, then the number screen and polling. The password is used once and not kept.
    func startLogin(password: String, deviceName: String) {
        guard session == .loggedOut, !loginBusy, loginBlockedSeconds(now: Date()) == 0 else {
            return
        }
        let device = DeviceInfo(
            name: deviceName,
            model: DeviceIdentity.model,
            os: DeviceIdentity.osString,
            app: AppConfig.appString
        )
        guard !device.name.isEmpty else {
            loginMessage = LoginTexts.nameRequired
            return
        }
        guard Validation.isValidPassword(password) else {
            loginMessage = LoginTexts.passwordRequired
            return
        }
        loginBusy = true
        loginMessage = nil
        let flow = loginFlow
        loginTask?.cancel()
        loginTask = Task { [weak self] in
            var started: LoginChallenge? = nil
            var failure: Error? = nil
            do {
                started = try await flow.start(password: password, device: device)
            } catch {
                failure = error
            }
            guard let self = self else {
                return
            }
            self.loginBusy = false
            if let error = failure {
                self.loginFailed(error)
                return
            }
            guard let challenge = started else {
                return
            }
            self.challenge = challenge
            self.loginDeadline = Date().addingTimeInterval(TimeInterval(max(0, challenge.expiresIn)))
            self.session = .waitingForBot
            await self.waitForApproval(challenge)
        }
    }

    func waitForApproval(_ challenge: LoginChallenge) async {
        let loginID = challenge.loginID
        do {
            let approved = try await loginFlow.waitForApproval(challenge, onTick: { [weak self] left in
                guard let self = self else {
                    return
                }
                await self.loginTick(left, loginID: loginID)
            })
            guard self.challenge?.loginID == loginID else {
                // «Отмена» was pressed while the approving poll was in flight: the server has already
                // issued a device. Revoke the token nobody will use (it would hold a slot for 90 days).
                RouterStore.revokeDetached(approved.token, like: client)
                return
            }
            finishLogin(approved)
        } catch {
            guard self.challenge?.loginID == loginID else {
                // The user pressed «Отмена».
                return
            }
            self.challenge = nil
            loginDeadline = nil
            session = .loggedOut
            let e = RouterStore.apiError(error)
            if e.isCancelled {
                return
            }
            loginMessage = e.userMessage
        }
    }

    func loginTick(_ secondsLeft: Int, loginID: String) {
        guard challenge?.loginID == loginID else {
            return
        }
        loginDeadline = Date().addingTimeInterval(TimeInterval(max(0, secondsLeft)))
    }

    /// «Отмена» on the number screen: back to the form, `POST /auth/cancel` (result ignored).
    func cancelLogin() {
        guard let current = challenge else {
            return
        }
        challenge = nil
        loginDeadline = nil
        session = .loggedOut
        loginTask?.cancel()
        loginTask = nil
        let flow = loginFlow
        Task {
            await flow.cancel(current)
        }
    }

    func loginFailed(_ error: Error) {
        let e = RouterStore.apiError(error)
        if e.isCancelled {
            return
        }
        if e.status == 429, let seconds = e.retryAfter, seconds > 0 {
            loginBlockedUntil = Date().addingTimeInterval(TimeInterval(seconds))
        } else if e.status == 401, e.code == "bad_password", e.left == 0 {
            // The last attempt: the server has closed login from this address for 15 min (no retry_after).
            // Another tap would only earn `429 locked` and one more fail2ban hit.
            loginBlockedUntil = Date().addingTimeInterval(15 * 60)
        }
        loginMessage = e.userMessage
    }

    func finishLogin(_ approved: ApprovedLogin) {
        challenge = nil
        loginDeadline = nil
        guard Validation.isValidToken(approved.token) else {
            session = .loggedOut
            loginMessage = APIError.badResponseText
            return
        }
        let saved = keychain.saveToken(approved.token)
        tokenBox.set(approved.token)
        let info = SessionInfo(approved: approved)
        sessionInfo = info
        RouterStore.saveSessionInfo(info)
        resetData()
        sessionEpoch += 1
        loginMessage = nil
        loginBlockedUntil = nil
        session = .loggedIn
        offerFaceID = BiometricGate.canAuthenticate && !AppSettings.lockOnOpen
        if !saved {
            showToast("Не удалось сохранить ключ в Keychain — после перезапуска приложения нужно будет войти снова.", tone: .warn)
        }
        Task {
            await self.read(.me)
        }
    }

    // MARK: - Logout (contract §3.1 LOGOUT)

    /// Stop everything, forget the token and all data, show the login screen with `message`.
    func endSession(message: String?) {
        sessionEpoch += 1
        actionTask?.cancel()
        actionTask = nil
        loginTask?.cancel()
        loginTask = nil
        for timer in timers {
            timer.cancel()
        }
        timers = []
        keychain.deleteToken()
        tokenBox.set(nil)
        RouterStore.clearSessionInfo()
        sessionInfo = nil
        me = nil
        challenge = nil
        loginDeadline = nil
        resetData()
        dismissPresentations()
        offerFaceID = false
        session = .loggedOut
        loginMessage = message
    }

    /// Settings «Выйти на этом iPhone»: the local LOGOUT happens first (Keychain, TokenBox, timers,
    /// data), so a kill or crash during the request can never leave the token behind (contract §2.4).
    /// Then `POST /auth/logout` with a one-shot client holding the old token; its result is ignored.
    func logoutFromSettings() async {
        let token = tokenBox.token
        endSession(message: nil)
        guard let t = token, Validation.isValidToken(t) else {
            return
        }
        let oneShot = RouterStore.oneShotClient(token: t, like: client)
        _ = try? await oneShot.logout()
    }

    /// Close sheets and dialogs (lock screen, logout).
    func dismissPresentations() {
        isSettingsPresented = false
        pendingConfirm = nil
        confirmError = nil
        showPingPreDialog = false
    }

    func resetData() {
        status = nil
        net = nil
        led = nil
        dayData = nil
        lastStatusAt = nil
        firstLoadFinished = false
        offline = false
        appDisabled = false
        statusError = nil
        runningAction = nil
        disabledButtons = []
        quietBanner = nil
        ledBusy = false
        confirmBusy = false
        confirmError = nil
        toast = nil
        inFlight = []
        retryUntil = [:]
        lastReadAt = [:]
        badReplyStreak = 0
        quietUntil = nil
        disabledUntil = [:]
    }

    // MARK: - Polling (contract §7.1)

    /// Runs until the calling task is cancelled (view hidden, app inactive, locked).
    func runPolling() async {
        guard isLoggedIn else {
            return
        }
        pollingCount += 1
        defer {
            pollingCount -= 1
        }
        // `/me` first and alone (contract §2.5, §7.1): it validates the token before the parallel reads,
        // so a stale token costs one `401 token_*` instead of 4–5 (`token_invalid` counts toward fail2ban),
        // and it re-reads `/me` on launch and unlock. Not again within a minute: Control Center or the
        // Face ID sheet also flip the scene inactive → active.
        if lastReadAt[.me].map({ Date().timeIntervalSince($0) > RouterStore.meRecheckAfter }) ?? true {
            await read(.me)
            guard isLoggedIn, !Task.isCancelled else {
                return
            }
        }
        await withTaskGroup(of: Void.self) { group in
            for kind in ReadKind.allCases {
                group.addTask {
                    await self.pollLoop(kind)
                }
            }
        }
    }

    func pollLoop(_ kind: ReadKind) async {
        if kind == .me, let last = lastReadAt[.me] {
            // `/me` is read first by `runPolling()` (launch, unlock), on login and when Settings opens;
            // this loop only adds a read every 30 min.
            let wait = kind.interval - Date().timeIntervalSince(last)
            if wait > 0 {
                do {
                    try await Task.sleep(nanoseconds: RouterStore.nanoseconds(wait))
                } catch {
                    return
                }
            }
        }
        while !Task.isCancelled {
            if shouldPoll(kind) {
                await read(kind)
            }
            do {
                try await Task.sleep(nanoseconds: RouterStore.nanoseconds(kind.interval))
            } catch {
                return
            }
        }
    }

    func shouldPoll(_ kind: ReadKind) -> Bool {
        guard isLoggedIn, !appDisabled else {
            return false
        }
        switch kind {
        case .net:
            // A sheet (Settings, confirm) does not fire the card's onDisappear: stop /net under it too.
            return netCardVisible && !offline && !isQuiet && !isSettingsPresented && pendingConfirm == nil
        case .led:
            return !offline
        case .status, .data, .me:
            return true
        }
    }

    /// Pull-to-refresh: re-reads `/me` (token check first), then status, data and LED once. Never runs actions.
    func refreshAll() async {
        guard isLoggedIn else {
            return
        }
        appDisabled = false
        await read(.me)
        guard isLoggedIn else {
            return
        }
        let kinds: [ReadKind] = [.status, .data, .led]
        await withTaskGroup(of: Void.self) { group in
            for kind in kinds {
                group.addTask {
                    await self.read(kind)
                }
            }
        }
    }

    /// One read. Skipped while the same kind is in flight or blocked by `retry_after`.
    func read(_ kind: ReadKind) async {
        guard isLoggedIn, !inFlight.contains(kind) else {
            return
        }
        if let until = retryUntil[kind], until > Date() {
            return
        }
        let epoch = sessionEpoch
        inFlight.insert(kind)
        defer {
            inFlight.remove(kind)
        }
        do {
            switch kind {
            case .status:
                let value = try await client.status()
                guard epoch == sessionEpoch else {
                    return
                }
                applyStatus(value)
            case .net:
                let value = try await client.net()
                guard epoch == sessionEpoch else {
                    return
                }
                net = value
            case .data:
                let value = try await client.data(range: .day)
                guard epoch == sessionEpoch else {
                    return
                }
                dayData = value
            case .led:
                let value = try await client.led()
                guard epoch == sessionEpoch else {
                    return
                }
                if !ledBusy {
                    led = value
                }
            case .me:
                let value = try await client.me()
                guard epoch == sessionEpoch else {
                    return
                }
                applyMe(value)
            }
            lastReadAt[kind] = Date()
            appDisabled = false
        } catch {
            guard epoch == sessionEpoch else {
                return
            }
            handleReadError(RouterStore.apiError(error), kind: kind)
        }
    }

    func applyStatus(_ value: RouterStatus) {
        status = value
        lastStatusAt = Date()
        firstLoadFinished = true
        offline = false
        statusError = nil
        badReplyStreak = 0
        appDisabled = false
    }

    func applyMe(_ value: MeResponse) {
        me = value
        var info = sessionInfo ?? SessionInfo(deviceID: value.device.id, expires: value.device.expires, hardExpires: value.device.hardExpires)
        info.update(from: value)
        sessionInfo = info
        RouterStore.saveSessionInfo(info)
    }

    func handleReadError(_ e: APIError, kind: ReadKind) {
        if e.isCancelled {
            return
        }
        if e.isAuthFailure {
            endSession(message: e.userMessage)
            return
        }
        if e.isAppDisabled {
            appDisabled = true
            return
        }
        if e.status == 429 {
            let seconds = max(1, e.retryAfter ?? 5)
            retryUntil[kind] = Date().addingTimeInterval(TimeInterval(seconds))
        }
        guard kind == .status else {
            // net / data / led / me: keep the old data, try again on the next tick.
            return
        }
        firstLoadFinished = true
        if isQuiet {
            // Restart or reboot in progress: errors are expected, the banner says so.
            return
        }
        if e.entersOfflineMode {
            offline = true
            statusError = nil
            return
        }
        if e.isBadReply {
            badReplyStreak += 1
            if badReplyStreak >= 2 {
                statusError = e.userMessage
            }
            return
        }
        if e.isBusy {
            return
        }
        statusError = e.userMessage
    }

    // MARK: - Toasts and timers

    func showToast(_ text: String, tone: Tone) {
        guard !text.isEmpty else {
            return
        }
        toast = ToastMessage(text: text, tone: tone)
    }

    func dismissToast(_ id: UUID) {
        if toast?.id == id {
            toast = nil
        }
    }

    /// Hides the current toast after a few seconds (called from the toast view's `.task(id:)`).
    func autoDismissToast() async {
        guard let id = toast?.id else {
            return
        }
        do {
            try await Task.sleep(nanoseconds: 4_500_000_000)
        } catch {
            return
        }
        dismissToast(id)
    }

    /// Runs `work` after `seconds` unless the session changed meanwhile.
    func after(_ seconds: TimeInterval, _ work: @escaping @MainActor @Sendable () async -> Void) {
        let epoch = sessionEpoch
        let task = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: RouterStore.nanoseconds(seconds))
            } catch {
                return
            }
            guard let self = self, self.sessionEpoch == epoch else {
                return
            }
            await work()
        }
        timers.append(task)
    }

    // MARK: - Helpers

    /// `runPolling()` re-reads `/me` first unless it was read this recently.
    nonisolated static let meRecheckAfter: TimeInterval = 60

    /// A client that sends only `token` (same base URL and transport as `client`).
    nonisolated static func oneShotClient(token: String, like client: APIClient) -> APIClient {
        return APIClient(baseURL: client.baseURL, transport: client.transport, clock: client.clock, tokenProvider: { token })
    }

    /// `POST /auth/logout` for a token the app no longer keeps (leftover after a reinstall, a login
    /// cancelled after approval). Fire and forget; the result is ignored.
    nonisolated static func revokeDetached(_ token: String, like client: APIClient) {
        guard Validation.isValidToken(token) else {
            return
        }
        let oneShot = oneShotClient(token: token, like: client)
        Task.detached {
            _ = try? await oneShot.logout()
        }
    }

    nonisolated static func nanoseconds(_ seconds: TimeInterval) -> UInt64 {
        guard seconds.isFinite, seconds > 0 else {
            return 0
        }
        return UInt64(min(seconds, 86400) * 1_000_000_000)
    }

    nonisolated static func apiError(_ error: Error) -> APIError {
        if let e = error as? APIError {
            return e
        }
        return APIError.transport(error)
    }

    nonisolated static func loadSessionInfo() -> SessionInfo? {
        guard let data = UserDefaults.standard.data(forKey: AppSettings.sessionInfoKey) else {
            return nil
        }
        return try? JSONDecoder().decode(SessionInfo.self, from: data)
    }

    nonisolated static func saveSessionInfo(_ info: SessionInfo) {
        if let data = try? JSONEncoder().encode(info) {
            UserDefaults.standard.set(data, forKey: AppSettings.sessionInfoKey)
        }
    }

    nonisolated static func clearSessionInfo() {
        UserDefaults.standard.removeObject(forKey: AppSettings.sessionInfoKey)
    }
}
