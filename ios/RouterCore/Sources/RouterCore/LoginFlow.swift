import Foundation

/// Texts of the login screens (contract §2.1, §7.6). (proposed) marks new app texts.
public enum LoginTexts {
    public static let passwordField = "Пароль панели"
    public static let nameField = "Название телефона"
    public static let defaultDeviceName = "iPhone"
    public static let loginButton = "Войти"
    public static let cancelButton = "Отмена"
    /// (proposed)
    public static let passwordRequired = "Введи пароль панели."
    /// (proposed)
    public static let nameRequired = "Введи название телефона."
    /// (proposed)
    public static func pressNumber(_ number: Int) -> String {
        return "Нажми в Telegram-боте число \(number)"
    }
    /// (proposed)
    public static let offerFaceID = "Включить Face ID для входа в приложение?"
}

/// Login: password → number in the Telegram bot → token (contract §2.1–2.3, §7.6).
///
/// Never stores or logs the password or `login_id`.
public final class LoginFlow: @unchecked Sendable {
    public let client: APIClient
    public let clock: RuntimeClock

    public init(client: APIClient, clock: RuntimeClock = .live) {
        self.client = client
        self.clock = clock
    }

    /// `POST /auth/login`. Errors (`bad_password` with `left`, `locked`/`rate_limited` with
    /// `retryAfter`, `tg_unavailable`, `too_many_devices`, …) are thrown as `APIError`.
    public func start(password: String, device: DeviceInfo) async throws -> LoginChallenge {
        return try await client.login(password: password, device: device)
    }

    /// Polls `/auth/poll` every `pollEvery` s until approved.
    ///
    /// - Keeps polling through transient errors (no connection, 429, 5xx) until the countdown
    ///   reaches 0, then polls once more and throws `APIError.loginTimedOut`.
    /// - `pending.expires_in` corrects the countdown.
    /// - Throws at once on `410 login_denied` / `login_expired`, `409 too_many_devices`,
    ///   `503 app_disabled`, 400, cancellation.
    /// - `onTick` gets the seconds left after every poll (and once at the start).
    public func waitForApproval(
        _ challenge: LoginChallenge,
        onTick: (@Sendable (Int) async -> Void)? = nil
    ) async throws -> ApprovedLogin {
        let started = clock.now()
        let interval = TimeInterval(min(max(challenge.pollEvery, 1), 10))
        let hardStop = started + TimeInterval(max(challenge.expiresIn, 120) + 60)
        var deadline = min(started + TimeInterval(max(challenge.expiresIn, 0)), hardStop)
        if let tick = onTick {
            await tick(LoginFlow.secondsLeft(deadline: deadline, now: started))
        }
        while true {
            try await clock.sleep(interval)
            try Task.checkCancellation()
            let finalAttempt = clock.now() >= deadline
            do {
                let result = try await client.poll(loginID: challenge.loginID)
                switch result {
                case .approved(let approved):
                    return approved
                case .pending(let left):
                    if let left = left {
                        deadline = min(clock.now() + TimeInterval(max(left, 0)), hardStop)
                    }
                }
            } catch let e as APIError {
                if !e.isTransient {
                    throw e
                }
            }
            let now = clock.now()
            if let tick = onTick {
                await tick(LoginFlow.secondsLeft(deadline: deadline, now: now))
            }
            if (finalAttempt && now >= deadline) || now >= hardStop {
                throw APIError.loginTimedOut
            }
        }
    }

    /// `POST /auth/cancel`; the result is ignored (any answer means the login is closed).
    public func cancel(_ challenge: LoginChallenge) async {
        _ = try? await client.cancelLogin(loginID: challenge.loginID)
    }

    /// Whole seconds left, never negative.
    public static func secondsLeft(deadline: TimeInterval, now: TimeInterval) -> Int {
        let left = deadline - now
        if left <= 0 {
            return 0
        }
        return Int(left.rounded(.up))
    }
}
