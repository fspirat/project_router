import Foundation
import RouterCore

/// Summary actions (contract §2.10–2.12, §7.2–7.4).
///
/// - Never retries a POST by itself; the only automatic follow-ups are `/jobs/{id}` polling and re-reads.
/// - restart / update / reboot: POST without `confirm` → 428 → `ConfirmSheet` with the server texts →
///   (Face ID for `danger == critical`) → the same POST with `confirm`.
/// - Nothing here can be started by a swipe or pull-to-refresh: only by the buttons.
extension RouterStore {
    // MARK: - Button state

    /// Whether a Summary button can be pressed now.
    func isEnabled(_ button: SummaryButton) -> Bool {
        guard isLoggedIn, !offline, !appDisabled else {
            return false
        }
        if disabledButtons.contains(button) {
            return false
        }
        if button == .led {
            return !ledBusy && (led?.isAvailable ?? false)
        }
        return runningAction == nil && pendingConfirm == nil && !confirmBusy
    }

    /// A tap on a Summary button.
    func tap(_ button: SummaryButton) {
        guard isEnabled(button) else {
            return
        }
        switch button {
        case .check:
            if PingPreDialog.isNeeded(status) {
                showPingPreDialog = true
            } else {
                startPing()
            }
        case .restartVPN:
            requestConfirm(.restart, button: button)
        case .updateSubs:
            requestConfirm(.update, button: button)
        case .reboot:
            requestConfirm(.reboot, button: button)
        case .led:
            break
        }
    }

    // MARK: - «Проверить» (ping job)

    func startPing() {
        showPingPreDialog = false
        guard isEnabled(.check) else {
            return
        }
        runningAction = .check
        let epoch = sessionEpoch
        let startedAt = Date()
        actionTask = Task { [weak self] in
            guard let self = self else {
                return
            }
            await self.runPing(epoch: epoch, startedAt: startedAt)
        }
    }

    func runPing(epoch: Int, startedAt: Date) async {
        defer {
            if epoch == sessionEpoch && runningAction == .check {
                runningAction = nil
            }
        }
        do {
            let outcome = try await client.perform(.ping)
            guard epoch == sessionEpoch else {
                return
            }
            switch outcome {
            case .job(let id, let pollEvery):
                let done = try await client.waitForJob(id: id, pollEvery: pollEvery)
                guard epoch == sessionEpoch else {
                    return
                }
                finishPing(done.status, startedAt: startedAt)
            case .done:
                finishPing(nil, startedAt: startedAt)
            case .confirm:
                // ping never asks for a confirm; treat it as a client bug.
                errorTick += 1
                showToast(APIError.client(code: "bad_param", message: nil).userMessage, tone: .err)
            }
        } catch {
            guard epoch == sessionEpoch else {
                return
            }
            handleActionError(RouterStore.apiError(error), isPing: true, button: .check)
        }
    }

    func finishPing(_ result: RouterStatus?, startedAt: Date) {
        successTick += 1
        if let value = result {
            applyStatus(value)
            if ActionTexts.isStale(value, jobStartedAt: startedAt.timeIntervalSince1970) {
                showToast(ActionTexts.staleResult, tone: .info)
                return
            }
        } else {
            Task {
                await self.read(.status)
            }
        }
        if let text = ActionAftermath.after(.ping).toast {
            showToast(text, tone: .ok)
        }
    }

    // MARK: - restart / update / reboot (428 confirm)

    func requestConfirm(_ action: RouterAction, button: SummaryButton) {
        guard isEnabled(button) else {
            return
        }
        runningAction = button
        confirmError = nil
        let epoch = sessionEpoch
        actionTask = Task { [weak self] in
            guard let self = self else {
                return
            }
            await self.fetchConfirm(action, button: button, epoch: epoch)
        }
    }

    func fetchConfirm(_ action: RouterAction, button: SummaryButton, epoch: Int) async {
        defer {
            if epoch == sessionEpoch && runningAction == button {
                runningAction = nil
            }
        }
        do {
            let outcome = try await client.perform(action)
            guard epoch == sessionEpoch else {
                return
            }
            handleOutcome(outcome, action: action, button: button)
        } catch {
            guard epoch == sessionEpoch else {
                return
            }
            pendingConfirm = nil
            handleActionError(RouterStore.apiError(error), isPing: false, button: button)
        }
    }

    func handleOutcome(_ outcome: ActionOutcome, action: RouterAction, button: SummaryButton) {
        switch outcome {
        case .confirm(let prompt):
            // A new dialog (also when the old confirm expired). Never re-sent automatically.
            confirmError = nil
            pendingConfirm = PendingConfirm(action: action, button: button, prompt: prompt)
        case .done:
            pendingConfirm = nil
            confirmError = nil
            actionSucceeded(action)
        case .job:
            pendingConfirm = nil
            confirmError = nil
            Task {
                await self.read(.status)
            }
        }
    }

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
        guard !confirmBusy else {
            return
        }
        pendingConfirm = nil
        confirmError = nil
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
                return
            }
            if !pending.prompt.canResend(now: Date().timeIntervalSince1970) {
                await refetchConfirm(pending, epoch: epoch)
                return
            }
        }
        do {
            let outcome = try await client.perform(pending.action, confirm: pending.prompt.confirm)
            guard epoch == sessionEpoch else {
                return
            }
            handleOutcome(outcome, action: pending.action, button: pending.button)
        } catch {
            guard epoch == sessionEpoch else {
                return
            }
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
            pendingConfirm = nil
            confirmError = nil
            handleActionError(e, isPing: false, button: pending.button)
        }
    }

    func refetchConfirm(_ pending: PendingConfirm, epoch: Int) async {
        do {
            let outcome = try await client.perform(pending.action)
            guard epoch == sessionEpoch else {
                return
            }
            handleOutcome(outcome, action: pending.action, button: pending.button)
        } catch {
            guard epoch == sessionEpoch else {
                return
            }
            pendingConfirm = nil
            confirmError = nil
            handleActionError(RouterStore.apiError(error), isPing: false, button: pending.button)
        }
    }

    // MARK: - LED (no confirm, optimistic with rollback)

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
                    self.handleActionError(RouterStore.apiError(error), isPing: false, button: .led)
                }
            }
        }
    }

    // MARK: - After success / error (contract §7.2, §7.3)

    func actionSucceeded(_ action: RouterAction) {
        let aftermath = ActionAftermath.after(action)
        successTick += 1
        if let text = aftermath.toast {
            showToast(text, tone: .ok)
        }
        if aftermath.quietWindow > 0 {
            startQuietWindow(aftermath.quietWindow, banner: aftermath.banner)
        }
        if aftermath.disabledFor > 0 {
            disable(aftermath.disabledButtons, for: aftermath.disabledFor)
        }
        if let delay = aftermath.rereadStatusAfter {
            after(delay) { [weak self] in
                guard let self = self, self.pollingActive else {
                    return
                }
                await self.read(.status)
            }
        }
    }

    func handleActionError(_ e: APIError, isPing: Bool, button: SummaryButton) {
        if e.isCancelled {
            return
        }
        if e.isAuthFailure {
            endSession(message: e.userMessage)
            return
        }
        if e.isAppDisabled {
            appDisabled = true
        }
        if e.isRateLimited, let seconds = e.retryAfter, seconds > 0 {
            // Block the same request until `retry_after`.
            disable([button], for: TimeInterval(seconds))
        }
        let text = isPing ? ActionTexts.pingJobErrorMessage(e) : e.actionMessage
        let slow = isPing && text == ActionTexts.pingSlow
        errorTick += 1
        showToast(text, tone: slow ? .warn : .err)
    }

    func startQuietWindow(_ seconds: TimeInterval, banner: String?) {
        quietUntil = Date().addingTimeInterval(seconds)
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
            guard let self = self else {
                return
            }
            self.refreshDisabled()
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
}
