import Foundation
import RouterCore

// The generic action runner (contract §2.10–2.12, §7.2–7.4; contract-stage4 §3, §3.7, §6).
//
// - Never retries a POST by itself; the only automatic follow-ups are `/jobs/{id}` polling and re-reads.
// - Confirmable actions: POST without `confirm` → 428 → `ConfirmSheet` with the server texts (red button for
//   `danger == critical`, block, dirdel, revoke-all, or when the screen asks) → Face ID for `critical` (setting
//   «Face ID для опасных действий») → the identical POST with `confirm`.
// - Nothing here may be started by a swipe or pull-to-refresh: only by buttons / toggles the user taps.

/// What the screen asked for.
struct ActionRequest: Equatable {
    let id: UUID
    let action: RouterAction
    /// Display name for the aftermath texts: node name (switch), subscription name (subupdate), device name
    /// (block, unblock, direct, schedule, revokeApp). Falls back to the id / MAC.
    let label: String?
    /// Extra app line above the server text in the confirm sheet, `warn` colour (contract-stage4 §3.3:
    /// schedule window active now, switch while Split is not the global node).
    let note: String?
    /// Red confirm button even if the server sends `high`/`medium` (schedule window active now).
    let forceDestructive: Bool
    /// Header symbol of the confirm sheet.
    let symbol: String?
    /// The «Сводка» button that started it (stage 3 busy spinners and disabling).
    let origin: SummaryButton?
    let startedAt: Date

    init(action: RouterAction, label: String?, note: String?, forceDestructive: Bool, symbol: String?, origin: SummaryButton?) {
        self.id = UUID()
        self.action = action
        self.label = label
        self.note = note
        self.forceDestructive = forceDestructive
        self.symbol = symbol
        self.origin = origin
        self.startedAt = Date()
    }
}

/// An action whose request (or job) is in flight.
struct RunningAction: Equatable {
    let request: ActionRequest

    var action: RouterAction {
        return request.action
    }
}

/// A 428 dialog waiting for the user.
struct PendingConfirm: Identifiable, Equatable {
    let request: ActionRequest
    let prompt: ConfirmPrompt

    var id: String {
        return prompt.confirm
    }

    var action: RouterAction {
        return request.action
    }

    /// Red confirm button: `danger == critical`, block / dirdel / revoke-all, or the screen's own reason.
    var isDestructive: Bool {
        return prompt.isDestructive(for: request.action) || request.forceDestructive
    }

    var symbol: String {
        if let s = request.symbol {
            return s
        }
        if let origin = request.origin {
            return origin.symbol
        }
        return isDestructive ? "exclamationmark.triangle.fill" : "questionmark.circle"
    }
}

/// How an action ended, for the screen's optional completion.
enum ActionResult {
    /// 200 (body as sent by the server/router).
    case done(JSONValue)
    /// A finished job (ping, speedtest).
    case job(JobDone)
    /// An error; the store has already shown the toast and done the re-reads.
    case failed(APIError)
    /// Not started (disabled, invalid), dialog cancelled, or Face ID failed.
    case cancelled

    var isSuccess: Bool {
        switch self {
        case .done, .job:
            return true
        case .failed, .cancelled:
            return false
        }
    }
}

typealias ActionCompletion = @MainActor (ActionResult) -> Void

extension RouterStore {
    // MARK: - State for controls

    /// `true` while `action` is disabled app-wide (PW lock-out, reboot, 429 `retry_after`, verification).
    func isLocked(_ action: RouterAction) -> Bool {
        guard lockedActionNames.contains(action.name) else {
            return false
        }
        if let until = lockedUntil[action.name] {
            return until > Date()
        }
        return false
    }

    /// Seconds left of the lock of `action` (for «Повтори через N с» countdowns; wrap in a TimelineView).
    func lockSecondsLeft(_ action: RouterAction, now: Date = Date()) -> Int {
        guard let until = lockedUntil[action.name] else {
            return 0
        }
        let left = until.timeIntervalSince(now)
        return left > 0 ? Int(left.rounded(.up)) : 0
    }

    /// The single check for enabling a control that starts `action`: logged in, not app-disabled, router on
    /// line (unless the action is server-only: rename, revokes), not locked, no other action or dialog running
    /// (jobs block only other jobs).
    func canPerform(_ action: RouterAction) -> Bool {
        guard isLoggedIn, !appDisabled, !uiLocked else {
            return false
        }
        if offline && !action.worksOffline {
            return false
        }
        if isLocked(action) {
            return false
        }
        if runningAction != nil || pendingConfirm != nil || confirmBusy {
            return false
        }
        if action.isJob && runningJob != nil {
            return false
        }
        return true
    }

    /// This exact action (same parameters) is running (spinner on its control).
    func isRunning(_ action: RouterAction) -> Bool {
        return runningAction?.action == action || runningJob?.action == action
    }

    /// Any action with this name is running (e.g. "pingone" for any server).
    func isRunning(named name: String) -> Bool {
        return runningAction?.action.name == name || runningJob?.action.name == name
    }

    /// A 428 dialog for `action` is open.
    func isConfirming(_ action: RouterAction) -> Bool {
        return pendingConfirm?.action == action
    }

    // MARK: - Run

    /// Starts `action`. Returns `false` (and calls `completion(.cancelled)`) when it cannot start now.
    /// The store handles everything else: the 428 sheet, Face ID, job polling, toasts, haptics, quiet windows,
    /// locks, local state changes, re-reads and LOGOUT on `401 token_*` / revoke-all.
    @discardableResult
    func perform(
        _ action: RouterAction,
        label: String? = nil,
        note: String? = nil,
        destructive: Bool = false,
        symbol: String? = nil,
        origin: SummaryButton? = nil,
        completion: ActionCompletion? = nil
    ) -> Bool {
        guard canPerform(action) else {
            completion?(.cancelled)
            return false
        }
        if let invalid = Validation.actionError(action) {
            errorTick += 1
            showToast(invalid.userMessage, tone: .err)
            completion?(.failed(invalid))
            return false
        }
        let request = ActionRequest(action: action, label: label, note: note, forceDestructive: destructive, symbol: symbol, origin: origin)
        if let c = completion {
            completions[request.id] = c
        }
        let epoch = sessionEpoch
        if action.isJob {
            runningJob = RunningAction(request: request)
            jobTask = Task { [weak self] in
                await self?.start(request, epoch: epoch)
            }
        } else {
            runningAction = RunningAction(request: request)
            actionTask = Task { [weak self] in
                await self?.start(request, epoch: epoch)
            }
        }
        return true
    }

    func start(_ request: ActionRequest, epoch: Int) async {
        do {
            let outcome = try await client.perform(request.action)
            guard epoch == sessionEpoch else {
                return
            }
            try await handleOutcome(outcome, request: request, epoch: epoch)
        } catch {
            guard epoch == sessionEpoch else {
                return
            }
            clearRunning(request)
            actionFailed(RouterStore.apiError(error), request: request)
        }
    }

    /// 200 → success; 202 → poll the job; 428 → the dialog (a new one also when the old confirm expired;
    /// never re-sent automatically).
    func handleOutcome(_ outcome: ActionOutcome, request: ActionRequest, epoch: Int) async throws {
        switch outcome {
        case .confirm(let prompt):
            clearRunning(request)
            confirmError = nil
            if uiLocked {
                // The 428 arrived after the lock screen came up: never open a confirm sheet under the lock.
                if pendingConfirm?.request.id == request.id {
                    pendingConfirm = nil
                }
                finishCompletion(request, .cancelled)
                return
            }
            pendingConfirm = PendingConfirm(request: request, prompt: prompt)
        case .done(let value):
            clearRunning(request)
            if pendingConfirm?.request.id == request.id {
                pendingConfirm = nil
            }
            confirmError = nil
            actionSucceeded(request, value: value, job: nil)
        case .job(let id, let pollEvery):
            if pendingConfirm?.request.id == request.id {
                pendingConfirm = nil
            }
            if runningJob?.request.id != request.id {
                runningJob = RunningAction(request: request)
            }
            if runningAction?.request.id == request.id {
                runningAction = nil
            }
            let done = try await client.waitForJob(id: id, pollEvery: pollEvery)
            guard epoch == sessionEpoch else {
                return
            }
            clearRunning(request)
            actionSucceeded(request, value: done.result, job: done)
        }
    }

    func clearRunning(_ request: ActionRequest) {
        if runningAction?.request.id == request.id {
            runningAction = nil
        }
        if runningJob?.request.id == request.id {
            runningJob = nil
        }
    }

    // MARK: - Confirm sheet

    /// The confirm button of `ConfirmSheet`.
    func confirmPending() {
        guard let pending = pendingConfirm, !confirmBusy else {
            return
        }
        confirmBusy = true
        confirmError = nil
        let epoch = sessionEpoch
        actionTask = Task { [weak self] in
            guard let self = self else {
                return
            }
            await self.sendConfirm(pending, epoch: epoch)
        }
    }

    /// «Отмена» or the sheet swiped away.
    func cancelPending() {
        guard !confirmBusy, let pending = pendingConfirm else {
            return
        }
        pendingConfirm = nil
        confirmError = nil
        finishCompletion(pending.request, .cancelled)
    }

    func sendConfirm(_ pending: PendingConfirm, epoch: Int) async {
        defer {
            if epoch == sessionEpoch {
                confirmBusy = false
            }
        }
        // The dialog stayed open too long: do not resend, ask the server for a fresh 428.
        if !pending.prompt.canResend(now: Date().timeIntervalSince1970) {
            await refetchConfirm(pending, epoch: epoch)
            return
        }
        if pending.prompt.requiresBiometrics && AppSettings.biometricForDanger {
            let reason = SettingsTexts.confirmReason(pending.prompt.displayTitle)
            let ok = await BiometricGate.confirmDangerous(reason: reason)
            guard epoch == sessionEpoch, pendingConfirm?.id == pending.id else {
                return
            }
            if !ok {
                // Face ID failed or cancelled → cancel silently.
                pendingConfirm = nil
                finishCompletion(pending.request, .cancelled)
                return
            }
            if !pending.prompt.canResend(now: Date().timeIntervalSince1970) {
                await refetchConfirm(pending, epoch: epoch)
                return
            }
        }
        if pending.action.isJob {
            runningJob = RunningAction(request: pending.request)
        } else {
            runningAction = RunningAction(request: pending.request)
        }
        do {
            let outcome = try await client.perform(pending.action, confirm: pending.prompt.confirm)
            guard epoch == sessionEpoch else {
                return
            }
            try await handleOutcome(outcome, request: pending.request, epoch: epoch)
        } catch {
            guard epoch == sessionEpoch else {
                return
            }
            clearRunning(pending.request)
            let e = RouterStore.apiError(error)
            if e.isCancelled {
                return
            }
            // A server 409/429 busy comes before the confirm check and does not burn the confirm: keep the
            // dialog and offer «Повторить». A busy from the router CGI (`source == "router"`) comes after the
            // check, the confirm is spent (contract §9 #5): close the dialog, the next tap gets a fresh 428.
            if e.isBusy && e.source != "router" && pendingConfirm?.id == pending.id && pending.prompt.canResend(now: Date().timeIntervalSince1970) {
                confirmError = e.userMessage
                errorTick += 1
                return
            }
            if pendingConfirm?.id == pending.id {
                pendingConfirm = nil
            }
            confirmError = nil
            actionFailed(e, request: pending.request)
        }
    }

    func refetchConfirm(_ pending: PendingConfirm, epoch: Int) async {
        do {
            let outcome = try await client.perform(pending.action)
            guard epoch == sessionEpoch else {
                return
            }
            try await handleOutcome(outcome, request: pending.request, epoch: epoch)
        } catch {
            guard epoch == sessionEpoch else {
                return
            }
            if pendingConfirm?.id == pending.id {
                pendingConfirm = nil
            }
            confirmError = nil
            actionFailed(RouterStore.apiError(error), request: pending.request)
        }
    }

    // MARK: - After success (contract §7.2, contract-stage4 §3.7)

    func actionSucceeded(_ request: ActionRequest, value: JSONValue, job: JobDone?) {
        let action = request.action
        let aftermath = ActionAftermath.after(action, name: request.label, result: value)
        var toastText = aftermath.toast
        switch action {
        case .ping:
            if let result = job?.status {
                applyStatus(result)
                if ActionTexts.isStale(result, jobStartedAt: request.startedAt.timeIntervalSince1970) {
                    toastText = ActionTexts.staleResult
                }
            } else {
                rereadNow(.status)
            }
        case .speedtest:
            if let s = status {
                status = s.applyingSuccess(of: action, result: job?.result ?? value)
            }
        case .ledset:
            if value.isObject {
                led = LedState(json: value)
            }
        case .rename:
            if value.isObject {
                applyNames(RenameResult(json: value).names)
            }
        case .diradd, .dirdel:
            if let m = mydirect {
                mydirect = m.applyingSuccess(of: action)
            }
        case .zapretset, .zapretcheck:
            if let z = zapret {
                zapret = z.applyingSuccess(of: action)
            }
        default:
            if let s = status {
                status = s.applyingSuccess(of: action, result: value)
            }
        }
        if case .pingone(let id) = action {
            pingedAt[id] = Date().timeIntervalSince1970
        }
        successTick += 1
        if let text = toastText {
            showToast(text, tone: text == ActionTexts.staleResult ? .info : .ok)
        }
        if aftermath.logsOut {
            // revoke-all: this phone's key is revoked too → LOGOUT at once with the banner.
            finishCompletion(request, job.map { ActionResult.job($0) } ?? .done(value))
            endSession(message: aftermath.toast)
            return
        }
        if case .revokeApp(let id) = action, id == sessionInfo?.deviceID {
            finishCompletion(request, .done(value))
            endSession(message: nil)
            return
        }
        if aftermath.quietWindow > 0 {
            startQuietWindow(aftermath.quietWindow, banner: aftermath.banner)
        }
        if aftermath.disabledFor > 0 {
            disable(aftermath.disabledButtons, for: aftermath.disabledFor)
        }
        if aftermath.lockedFor > 0 && !aftermath.lockedActions.isEmpty {
            lock(aftermath.lockedActions, for: aftermath.lockedFor)
        }
        if let fast = aftermath.fastPoll, fast.target == .zapret {
            // A new trigger: 3 s polling while busy/checking, at most 2 min.
            zapretFastSince = Date()
        }
        var verifiedTarget: ReadTarget? = nil
        if let check = aftermath.verification {
            verifiedTarget = startVerification(check, rereads: aftermath.rereads)
        }
        for reread in aftermath.rereads where reread.target != verifiedTarget {
            scheduleReread(reread)
        }
        finishCompletion(request, job.map { ActionResult.job($0) } ?? .done(value))
    }

    func scheduleReread(_ reread: ScheduledRead) {
        let target = reread.target
        if reread.after <= 0 {
            rereadNow(target)
            return
        }
        after(reread.after) { [weak self] in
            guard let self = self, self.pollingActive else {
                return
            }
            for kind in self.kinds(for: target) {
                await self.read(kind)
            }
        }
    }

    /// zapretstrat / tgwsset: read at the scheduled times and check the router really applied it.
    /// Returns the target whose re-reads it took over.
    func startVerification(_ check: Verification, rereads: [ScheduledRead]) -> ReadTarget {
        let target: ReadTarget
        switch check {
        case .zapretStrategy:
            target = .zapret
        case .tgws:
            target = .tgws
        }
        let id = UUID()
        verificationID = id
        verification = check
        let delays = rereads.filter { $0.target == target }.map { $0.after }.sorted()
        for (index, delay) in delays.enumerated() {
            let isLast = index == delays.count - 1
            after(delay) { [weak self] in
                guard let self = self, self.verificationID == id else {
                    return
                }
                guard self.pollingActive else {
                    // Left the app meanwhile: no background reads; just stop the spinner.
                    self.endVerification(id)
                    return
                }
                for kind in self.kinds(for: target) {
                    await self.read(kind)
                }
                guard self.verificationID == id else {
                    return
                }
                self.evaluateVerification(check, id: id, isLast: isLast)
            }
        }
        if delays.isEmpty {
            endVerification(id)
        }
        return target
    }

    func evaluateVerification(_ check: Verification, id: UUID, isLast: Bool) {
        switch check {
        case .zapretStrategy(let n):
            switch Zapret.verifyStrategy(requested: n, state: zapret, isLastCheck: isLast) {
            case .applied(let text):
                showToast(text, tone: .ok)
                endVerification(id)
            case .pending:
                break
            case .failed(let text):
                errorTick += 1
                showToast(text, tone: .err)
                endVerification(id)
            }
        case .tgws(let on):
            switch Tgws.verifySwitch(requested: on, state: tgws, isLastCheck: isLast) {
            case .applied:
                endVerification(id)
            case .pending:
                break
            case .failed(let text):
                errorTick += 1
                showToast(text, tone: .err)
                endVerification(id)
            }
        }
    }

    func endVerification(_ id: UUID) {
        guard verificationID == id else {
            return
        }
        verificationID = nil
        verification = nil
    }

    // MARK: - After an error (contract §7.3, contract-stage4 §6)

    func actionFailed(_ e: APIError, request: ActionRequest) {
        let action = request.action
        if e.isCancelled {
            finishCompletion(request, .cancelled)
            return
        }
        if e.isAuthFailure {
            finishCompletion(request, .failed(e))
            endSession(message: e.userMessage)
            return
        }
        if ActionErrorPolicy.treatsAsStarted(action, error: e) {
            // zapretcheck answered 409 by the router: a check already runs → poll it, no error.
            actionSucceeded(request, value: .null, job: nil)
            return
        }
        if e.isAppDisabled {
            appDisabled = true
        }
        if e.isRateLimited, let seconds = e.retryAfter, seconds > 0 {
            // Block the same request until `retry_after` (with a countdown on the control).
            lock([action.name], for: TimeInterval(seconds))
            if let origin = request.origin {
                disable([origin], for: TimeInterval(seconds))
            }
        }
        for target in ActionErrorPolicy.rereads(for: action, error: e) {
            rereadNow(target)
        }
        let text: String?
        if case .ping = action {
            text = ActionTexts.pingJobErrorMessage(e)
        } else {
            text = ActionErrorPolicy.message(for: action, error: e)
        }
        if let message = text, !message.isEmpty {
            let slow = message == ActionTexts.pingSlow
            errorTick += 1
            showToast(message, tone: slow ? .warn : .err)
        }
        finishCompletion(request, .failed(e))
    }

    /// Runs the screen's completion. While a 428 sheet is closing (shown, nothing pending any more) it waits
    /// until the sheet is gone: a completion that closes its own sheet (schedule, server card) would otherwise
    /// dismiss two stacked sheets in one update.
    func finishCompletion(_ request: ActionRequest, _ result: ActionResult) {
        guard let completion = completions.removeValue(forKey: request.id) else {
            return
        }
        if confirmSheetShown && pendingConfirm == nil {
            afterConfirmDismissed.append {
                completion(result)
            }
            // Fallback in case the sheet's onDismiss is never reported.
            after(1.0) { [weak self] in
                self?.confirmSheetDidDismiss()
            }
            return
        }
        completion(result)
    }

    /// The 428 sheet is gone (PresentationHost `onDismiss`): run the completions held back meanwhile.
    func confirmSheetDidDismiss() {
        confirmSheetShown = false
        let queued = afterConfirmDismissed
        afterConfirmDismissed = []
        for work in queued {
            work()
        }
    }

    // MARK: - Quiet windows, locks, disabled Summary buttons

    func startQuietWindow(_ seconds: TimeInterval, banner: String?) {
        let until = Date().addingTimeInterval(seconds)
        if let current = quietUntil, current > until {
            return
        }
        quietUntil = until
        quietBanner = banner
        statusError = nil
        after(seconds + 0.2) { [weak self] in
            guard let self = self else {
                return
            }
            if !self.isQuiet {
                self.quietBanner = nil
            }
        }
    }

    /// Disable these action names app-wide for `seconds`.
    func lock(_ names: Set<String>, for seconds: TimeInterval) {
        guard seconds > 0, !names.isEmpty else {
            return
        }
        let until = Date().addingTimeInterval(seconds)
        for name in names {
            if let current = lockedUntil[name], current > until {
                continue
            }
            lockedUntil[name] = until
        }
        refreshLocks()
        after(seconds + 0.2) { [weak self] in
            self?.refreshLocks()
        }
    }

    func refreshLocks() {
        let now = Date()
        lockedUntil = lockedUntil.filter { $0.value > now }
        let current = Set(lockedUntil.keys)
        if current != lockedActionNames {
            lockedActionNames = current
        }
    }

    func disable(_ buttons: [SummaryButton], for seconds: TimeInterval) {
        guard seconds > 0, !buttons.isEmpty else {
            return
        }
        let until = Date().addingTimeInterval(seconds)
        for button in buttons {
            if let current = disabledUntil[button], current > until {
                continue
            }
            disabledUntil[button] = until
        }
        refreshDisabled()
        after(seconds + 0.2) { [weak self] in
            self?.refreshDisabled()
        }
    }

    func refreshDisabled() {
        let now = Date()
        disabledUntil = disabledUntil.filter { $0.value > now }
        let current = Set(disabledUntil.keys)
        if current != disabledButtons {
            disabledButtons = current
        }
    }

    // MARK: - «Сводка» buttons (stage 3 behaviour on top of the generic runner)

    /// Whether a Summary button can be pressed now.
    func isEnabled(_ button: SummaryButton) -> Bool {
        guard isLoggedIn, !offline, !appDisabled else {
            return false
        }
        if disabledButtons.contains(button) {
            return false
        }
        if button == .led {
            return !ledBusy && (led?.isAvailable ?? false) && !isLocked(.ledset(on: true))
        }
        guard let action = button.action else {
            return false
        }
        // Stage 3: every Summary button waits while the ping job («Проверить») runs.
        return canPerform(action) && runningJob == nil
    }

    /// The Summary button shows a spinner.
    func isBusy(_ button: SummaryButton) -> Bool {
        return runningAction?.request.origin == button || runningJob?.request.origin == button
    }

    /// A tap on a Summary button.
    func tap(_ button: SummaryButton) {
        guard isEnabled(button), let action = button.action else {
            return
        }
        if button == .check && PingPreDialog.isNeeded(status) {
            showPingPreDialog = true
            return
        }
        perform(action, origin: button)
    }

    /// «Проверить» after the pre-dialog.
    func startPing() {
        showPingPreDialog = false
        guard isEnabled(.check) else {
            return
        }
        perform(.ping, origin: .check)
    }

    /// «Подсветка»: `POST action/ledset {on}` without a dialog; optimistic, rolled back on error.
    func setLED(on: Bool) {
        guard isEnabled(.led), let previous = led else {
            return
        }
        ledBusy = true
        var optimistic = previous
        optimistic.on = on
        led = optimistic
        let epoch = sessionEpoch
        let apiClient = client
        let request = ActionRequest(action: .ledset(on: on), label: nil, note: nil, forceDestructive: false, symbol: nil, origin: .led)
        Task { [weak self] in
            var result: LedState? = nil
            var failure: Error? = nil
            do {
                result = try await apiClient.setLED(on: on)
            } catch {
                failure = error
            }
            guard let self = self, epoch == self.sessionEpoch else {
                return
            }
            self.ledBusy = false
            if let state = result {
                self.led = state
                self.successTick += 1
                if let text = ActionAftermath.after(.ledset(on: on)).toast {
                    self.showToast(text, tone: .ok)
                }
            } else {
                self.led = previous
                if let error = failure {
                    self.actionFailed(RouterStore.apiError(error), request: request)
                }
            }
        }
    }
}

extension SummaryButton {
    /// The router action behind a Summary button (`led` is a toggle, not a one-shot action).
    var action: RouterAction? {
        switch self {
        case .check:
            return .ping
        case .restartVPN:
            return .restart
        case .updateSubs:
            return .update
        case .reboot:
            return .reboot
        case .led:
            return nil
        }
    }
}
