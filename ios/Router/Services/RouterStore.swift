import Foundation
import Observation
import RouterCore

/// Where the user is: login form, waiting for the bot, or inside the app.
enum SessionState: Equatable {
    case loggedOut
    case waitingForBot
    case loggedIn
}

/// The bottom tabs (contract-stage4 §1.1). Settings is the gear on every tab, not a tab.
enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case summary
    case vpn
    case devices
    case bypass
    case journal

    var id: String {
        return rawValue
    }

    var title: String {
        switch self {
        case .summary:
            return "Сводка"
        case .vpn:
            return "VPN"
        case .devices:
            return "Устройства"
        case .bypass:
            return "Обход"
        case .journal:
            return "Журнал"
        }
    }

    /// SF Symbols (contract-stage4 §1.1).
    var symbol: String {
        switch self {
        case .summary:
            return "gauge.with.dots.needle.67percent"
        case .vpn:
            return "lock.shield"
        case .devices:
            return "macbook.and.iphone"
        case .bypass:
            return "arrow.triangle.branch"
        case .journal:
            return "scroll"
        }
    }
}

/// «Все в журнале» from the VPN switch history (contract-stage4 §5.1.5): the Journal tab opens with
/// filter «Все» and this range. Set by `RouterStore.openJournal(range:)`; the Journal screen consumes it.
struct JournalLink: Equatable {
    let id: UUID
    let range: DataRange

    init(range: DataRange) {
        self.id = UUID()
        self.range = range
    }
}

/// The single app state (inventory §9.1): session, data caches, polling and actions.
///
/// - Data lives only in memory; the token is in Keychain, `SessionInfo` (not secret) in UserDefaults.
/// - Polling (RouterStore+Polling.swift) runs only while the app is active, unlocked and logged in, and only
///   for the reads of the screens on display (`.pollingScope(_:)`). One request per kind at a time.
/// - Actions (RouterStore+Actions.swift): one generic runner with the 428 confirm flow, jobs, aftermath.
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

    // MARK: Data caches (memory only; contract-stage4 §1.2)

    /// `/status` (or the ping job result). Shared by Summary, VPN, Devices, Bypass.
    var status: RouterStatus? = nil
    /// `/net` (Summary «Интернет сейчас» only).
    var net: NetStats? = nil
    /// `/led`.
    var led: LedState? = nil
    /// `/data?range=…`, one cache per range. Read with `data(_:)`.
    var dataByRange: [DataRange: DataResponse] = [:]
    /// The newest `/data` response of any range: use it for `names`, `traffic`, `newdevs`, `speed`, `site`
    /// (the same in every range).
    var latestData: DataResponse? = nil
    /// `/zapret`.
    var zapret: ZapretState? = nil
    /// `/tgws`.
    var tgws: TgwsState? = nil
    /// `/mydirect`.
    var mydirect: MyDirectList? = nil
    /// `/vds` (own servers, read-only).
    var vds: VdsResponse? = nil
    /// `GET /devices` (who has access: phones, browsers, login journal).
    var accessList: AccessList? = nil
    /// The last read error to show per kind (see `readError(_:)`, `readErrorCode(_:)`); cleared by the next
    /// success.
    var readErrors: [ReadKind: APIError] = [:]

    /// The last successful `/status` (or ping job result).
    var lastStatusAt: Date? = nil
    var firstLoadFinished: Bool = false
    /// Offline mode (contract §7.5): only `/status` 502/504 outside a quiet window switches it on.
    var offline: Bool = false
    /// `503 app_disabled`: full-screen state on Summary, a pill elsewhere; the token is kept.
    var appDisabled: Bool = false
    /// A `/status` error that is not offline mode (server down, no connection, …).
    var statusError: String? = nil

    // MARK: Navigation (shared between screens)

    /// The selected tab. Screens may switch it (e.g. Summary «Все устройства» → `.devices`).
    var selectedTab: AppTab = .summary
    /// Badge per tab (0 / missing = none). The Devices screen may set `.devices` (new devices this week).
    var tabBadges: [AppTab: Int] = [:]
    /// «Все в журнале»: consumed (set to nil) by the Journal screen.
    var journalLink: JournalLink? = nil
    var isSettingsPresented: Bool = false

    // MARK: Actions and presentation

    /// A non-job action in flight (its request or its 428 fetch). Other non-job actions are disabled meanwhile.
    var runningAction: RunningAction? = nil
    /// A job (ping, speedtest) being polled. Another job cannot start meanwhile; other actions can.
    var runningJob: RunningAction? = nil
    /// «Сводка» buttons disabled after an action (stage 3 aftermath `disabledButtons`).
    var disabledButtons: Set<SummaryButton> = []
    /// Action names (`RouterAction.name`) disabled app-wide right now: PW lock-out, reboot, 429 `retry_after`,
    /// verification windows. Use `isLocked(_:)` / `canPerform(_:)`.
    var lockedActionNames: Set<String> = []
    /// Quiet-window banner («VPN перезапускается…»): Summary shows it as a banner, other tabs as a pill.
    var quietBanner: String? = nil
    var ledBusy: Bool = false
    var pendingConfirm: PendingConfirm? = nil
    var confirmBusy: Bool = false
    var confirmError: String? = nil
    /// A check that runs on the re-reads after `zapretstrat` / `tgwsset` (spinner on the control meanwhile).
    var verification: Verification? = nil
    var showPingPreDialog: Bool = false
    var toast: ToastMessage? = nil
    var successTick: Int = 0
    var errorTick: Int = 0
    /// Toast/confirm hosts on screen, bottom to top (tab roots and app sheets; see PresentationHost.swift).
    var hostStack: [PresentationHostEntry] = []
    /// The lock screen is up (mirrored from `AppLock` by RootView): no action starts and no 428 sheet opens.
    /// Observed, so controls re-enable as soon as the app is unlocked.
    var uiLocked: Bool = false
    /// When `pingone` last succeeded per node id (Unix time): the server card says «Проверено только что»
    /// for a minute (contract-stage4 §5.1.4), also after the card is closed and opened again.
    var pingedAt: [String: TimeInterval] = [:]

    // MARK: Bookkeeping (not observed)

    /// Bumped on every login/logout: late answers of an old session are dropped.
    @ObservationIgnored var sessionEpoch: Int = 0
    @ObservationIgnored var inFlight: Set<ReadKind> = []
    @ObservationIgnored var retryUntil: [ReadKind: Date] = [:]
    /// Last successful read per kind.
    @ObservationIgnored var lastReadAt: [ReadKind: Date] = [:]
    /// Last started read per kind (success or not): the polling schedule counts from it.
    @ObservationIgnored var lastAttemptAt: [ReadKind: Date] = [:]
    /// Failed reads in a row per kind (router 502/504 on zapret/tgws/mydirect are shown only from the 2nd).
    @ObservationIgnored var readFailures: [ReadKind: Int] = [:]
    @ObservationIgnored var badReplyStreak: Int = 0
    @ObservationIgnored var quietUntil: Date? = nil
    @ObservationIgnored var disabledUntil: [SummaryButton: Date] = [:]
    @ObservationIgnored var lockedUntil: [String: Date] = [:]
    /// Pending `after(_:_:)` timers; each removes itself when it fires.
    @ObservationIgnored var timers: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored var actionTask: Task<Void, Never>? = nil
    @ObservationIgnored var jobTask: Task<Void, Never>? = nil
    @ObservationIgnored var loginTask: Task<Void, Never>? = nil
    @ObservationIgnored var pollingCount: Int = 0
    /// Visible polling scopes (`.pollingScope(_:)`), by scope id.
    @ObservationIgnored var scopes: [UUID: Set<ReadKind>] = [:]
    /// Fast `/zapret` polling (3 s while busy/checking, ≤ 2 min per trigger).
    @ObservationIgnored var zapretFastSince: Date? = nil
    @ObservationIgnored var verificationID: UUID? = nil
    @ObservationIgnored var completions: [UUID: ActionCompletion] = [:]
    @ObservationIgnored var tabRestored: Bool = false
    /// A 428 sheet has appeared and its dismissal has not been reported yet (PresentationHost).
    @ObservationIgnored var confirmSheetShown: Bool = false
    /// Completions held back until the closing 428 sheet is gone (see `finishCompletion`).
    @ObservationIgnored var afterConfirmDismissed: [@MainActor () -> Void] = []

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

    /// `/data` for one range (nil until the first read of that range).
    func data(_ range: DataRange) -> DataResponse? {
        return dataByRange[range]
    }

    /// `/data?range=day` (Summary, Settings links).
    var dayData: DataResponse? {
        return dataByRange[.day]
    }

    /// A read error to show for `kind`, or nil. Router 502/504 and bad replies count only from the second
    /// failure in a row (contract-stage4 §4.3); other errors (e.g. `/mydirect` `500 no rule`) at once.
    func readError(_ kind: ReadKind) -> String? {
        return readErrors[kind]?.userMessage
    }

    /// The API error code behind `readError(kind)` (e.g. "no rule"), or nil.
    func readErrorCode(_ kind: ReadKind) -> String? {
        return readErrors[kind]?.code
    }

    /// Switch to the Journal tab with filter «Все» and `range` (contract-stage4 §5.1.5).
    func openJournal(range: DataRange) {
        journalLink = JournalLink(range: range)
        selectedTab = .journal
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
        selectedTab = .summary
        tabRestored = true
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
        jobTask?.cancel()
        jobTask = nil
        loginTask?.cancel()
        loginTask = nil
        for timer in timers.values {
            timer.cancel()
        }
        timers = [:]
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

    /// Close store-owned sheets and dialogs (lock screen, logout). Screen-owned sheets stay under the
    /// lock/privacy cover (`sheetChrome`).
    func dismissPresentations() {
        isSettingsPresented = false
        if let pending = pendingConfirm {
            pendingConfirm = nil
            finishCompletion(pending.request, .cancelled)
        }
        confirmError = nil
        showPingPreDialog = false
    }

    func resetData() {
        status = nil
        net = nil
        led = nil
        dataByRange = [:]
        latestData = nil
        zapret = nil
        tgws = nil
        mydirect = nil
        vds = nil
        accessList = nil
        readErrors = [:]
        pingedAt = [:]
        lastStatusAt = nil
        firstLoadFinished = false
        offline = false
        appDisabled = false
        statusError = nil
        runningAction = nil
        runningJob = nil
        disabledButtons = []
        lockedActionNames = []
        quietBanner = nil
        ledBusy = false
        confirmBusy = false
        confirmError = nil
        verification = nil
        toast = nil
        tabBadges = [:]
        journalLink = nil
        inFlight = []
        retryUntil = [:]
        lastReadAt = [:]
        lastAttemptAt = [:]
        readFailures = [:]
        badReplyStreak = 0
        quietUntil = nil
        disabledUntil = [:]
        lockedUntil = [:]
        zapretFastSince = nil
        verificationID = nil
        completions = [:]
        confirmSheetShown = false
        afterConfirmDismissed = []
    }

    // MARK: - Reads

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
        lastAttemptAt[kind] = Date()
        defer {
            // A read left over from the previous session must not free the new session's slot.
            if epoch == sessionEpoch {
                inFlight.remove(kind)
            }
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
            case .data(let range):
                let value = try await client.data(range: range)
                guard epoch == sessionEpoch else {
                    return
                }
                dataByRange[range] = value
                latestData = value
                updateDevicesBadge()
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
            case .zapret:
                let value = try await client.zapret()
                guard epoch == sessionEpoch else {
                    return
                }
                applyZapret(value)
            case .tgws:
                let value = try await client.tgws()
                guard epoch == sessionEpoch else {
                    return
                }
                tgws = value
            case .mydirect:
                let value = try await client.mydirect()
                guard epoch == sessionEpoch else {
                    return
                }
                mydirect = value
            case .vds:
                let value = try await client.vds()
                guard epoch == sessionEpoch else {
                    return
                }
                vds = value
            case .devices:
                let value = try await client.accessList()
                guard epoch == sessionEpoch else {
                    return
                }
                accessList = value
            }
            lastReadAt[kind] = Date()
            readFailures[kind] = nil
            if readErrors[kind] != nil {
                readErrors[kind] = nil
            }
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

    /// `/zapret` with the fast-poll bookkeeping: a new trigger starts when busy/checking appears.
    func applyZapret(_ value: ZapretState) {
        zapret = value
        if value.busy || value.checking {
            if zapretFastSince == nil {
                zapretFastSince = Date()
            }
        } else {
            zapretFastSince = nil
        }
    }

    /// After `rename`: the whole names map replaces `names` in every `/data` cache.
    func applyNames(_ names: [String: String]) {
        var updated: [DataRange: DataResponse] = [:]
        for (range, value) in dataByRange {
            updated[range] = value.replacingNames(names)
        }
        dataByRange = updated
        if let latest = latestData {
            latestData = latest.replacingNames(names)
        }
        updateDevicesBadge()
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
            // Other kinds keep the old data; the error is shown per screen via `readError(_:)`.
            noteReadFailure(e, kind: kind)
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

    /// Router 502/504, bad replies and no connection count from the 2nd failure in a row; other errors at once.
    /// `.net`, `.led`, `.me` stay silent as in stage 3.
    func noteReadFailure(_ e: APIError, kind: ReadKind) {
        let streak = (readFailures[kind] ?? 0) + 1
        readFailures[kind] = streak
        switch kind {
        case .net, .led, .me:
            return
        default:
            break
        }
        if e.isRateLimited || e.isBusy {
            return
        }
        let transient = e.entersOfflineMode || e.isBadReply || e.isNoConnection || e.kind == .badResponse
        if transient && (streak < 2 || isQuiet) {
            if streak == 1 && !isQuiet && (effectiveInterval(kind) ?? .infinity) > 30 {
                // No timer brings the 2nd failure soon (`/mydirect`, `/devices`: none; `/vds`: 5 min), and the
                // screen would keep «Загружаю…» meanwhile: retry once.
                after(5) { [weak self] in
                    guard let self = self, self.pollingActive, self.activeKinds.contains(kind), self.shouldPoll(kind) else {
                        return
                    }
                    await self.read(kind)
                }
            }
            return
        }
        readErrors[kind] = e
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
        let id = UUID()
        let task = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: RouterStore.nanoseconds(seconds))
            } catch {
                return
            }
            guard let self = self else {
                return
            }
            self.timers[id] = nil
            guard self.sessionEpoch == epoch else {
                return
            }
            await work()
        }
        timers[id] = task
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
