import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import RouterCore

/// Collects countdown ticks from `waitForApproval`.
final class TickRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int] = []

    func add(_ v: Int) {
        lock.lock()
        values.append(v)
        lock.unlock()
    }

    var all: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return values
    }
}

final class LoginFlowTests: XCTestCase {

    private let device = DeviceInfo(name: "iPhone владельца", model: "iPhone15,2", os: "iOS 18.1", app: "1.0 (42)")

    func testLoginPendingTwiceThenApproved() async throws {
        let transport = MockTransport()
        let clock = FakeClock(start: nowT)
        let client = makeClient(transport, clock: clock, token: nil)
        let flow = LoginFlow(client: client, clock: clock.runtime)
        transport.enqueue(200, SampleJSON.loginStart)
        transport.enqueue(200, #"{"state":"pending","expires_in":118}"#)
        transport.enqueue(200, #"{"state":"pending","expires_in":116}"#)
        transport.enqueue(200, SampleJSON.pollApproved)

        let challenge = try await flow.start(password: "secret", device: device)
        XCTAssertEqual(challenge.number, 24)
        XCTAssertEqual(LoginTexts.pressNumber(challenge.number), "Нажми в Telegram-боте число 24")

        let ticks = TickRecorder()
        let approved = try await flow.waitForApproval(challenge, onTick: { left in ticks.add(left) })
        XCTAssertTrue(Validation.isValidToken(approved.token))
        XCTAssertEqual(approved.deviceID, "49139e3a1db5a6ac")
        XCTAssertEqual(approved.hardExpires, 1823422560)
        XCTAssertEqual(clock.sleeps, [2, 2, 2])
        XCTAssertEqual(ticks.all, [120, 118, 116])

        let reqs = transport.requests
        XCTAssertEqual(reqs.count, 4)
        XCTAssertEqual(reqs[0].url?.path, "/router/app/v1/auth/login")
        XCTAssertEqual(reqs[1].url?.path, "/router/app/v1/auth/poll")
        for r in reqs {
            XCTAssertNil(r.value(forHTTPHeaderField: "Authorization"))
            XCTAssertFalse(r.url?.absoluteString.contains(challenge.loginID) ?? true)
        }
        XCTAssertEqual(bodyJSON(reqs[1])?["login_id"], .string(challenge.loginID))

        let session = SessionInfo(approved: approved)
        XCTAssertEqual(session.expires, 1799662560)
    }

    func testDenied() async throws {
        let transport = MockTransport()
        let clock = FakeClock(start: nowT)
        let flow = LoginFlow(client: makeClient(transport, clock: clock, token: nil), clock: clock.runtime)
        transport.enqueue(200, #"{"state":"pending","expires_in":118}"#)
        transport.enqueue(410, #"{"error":"login_denied","message":"Вход отклонён в Telegram."}"#)
        let challenge = try decodeJSON(LoginChallenge.self, SampleJSON.loginStart)
        do {
            _ = try await flow.waitForApproval(challenge)
            XCTFail("expected an error")
        } catch let e as APIError {
            XCTAssertEqual(e.status, 410)
            XCTAssertTrue(e.isLoginReset)
            XCTAssertFalse(e.isAuthFailure)
            XCTAssertEqual(e.userMessage, "Вход отклонён в Telegram.")
        }
    }

    func testBadPasswordIsNotALogout() async throws {
        let transport = MockTransport()
        let flow = LoginFlow(client: makeClient(transport, token: nil))
        transport.enqueue(401, #"{"error":"bad_password","message":"Неверный пароль. Осталось попыток: 4.","left":4}"#)
        transport.enqueue(401, #"{"error":"bad_password","message":"Слишком много неверных попыток. Вход с этого адреса закрыт на 15 мин.","left":0}"#)
        transport.enqueue(429, #"{"error":"locked","message":"Слишком много неверных попыток. Вход с этого адреса закрыт ещё на 15 мин.","retry_after":874}"#, headers: ["Retry-After": "874"])
        do {
            _ = try await flow.start(password: "wrong", device: device)
            XCTFail("expected an error")
        } catch let e as APIError {
            XCTAssertEqual(e.code, "bad_password")
            XCTAssertEqual(e.left, 4)
            XCTAssertFalse(e.isAuthFailure)
            XCTAssertEqual(e.userMessage, "Неверный пароль. Осталось попыток: 4.")
        }
        do {
            _ = try await flow.start(password: "wrong", device: device)
            XCTFail("expected an error")
        } catch let e as APIError {
            XCTAssertEqual(e.left, 0)
            XCTAssertEqual(e.userMessage, "Слишком много неверных попыток. Вход с этого адреса закрыт на 15 мин.")
        }
        do {
            _ = try await flow.start(password: "wrong", device: device)
            XCTFail("expected an error")
        } catch let e as APIError {
            XCTAssertEqual(e.code, "locked")
            XCTAssertEqual(e.retryAfter, 874)
        }
    }

    func testEmptyPasswordOrNameIsNeverSent() async throws {
        let transport = MockTransport()
        let flow = LoginFlow(client: makeClient(transport, token: nil))
        do {
            _ = try await flow.start(password: "", device: device)
            XCTFail("expected an error")
        } catch let e as APIError {
            XCTAssertEqual(e.kind, .client)
            XCTAssertEqual(e.userMessage, LoginTexts.passwordRequired)
        }
        do {
            _ = try await flow.start(password: "secret", device: DeviceInfo(name: " \n "))
            XCTFail("expected an error")
        } catch let e as APIError {
            XCTAssertEqual(e.userMessage, LoginTexts.nameRequired)
        }
        XCTAssertEqual(transport.requests.count, 0)
    }

    func testLocalExpiryAfterNetworkErrors() async throws {
        let transport = MockTransport()
        let clock = FakeClock(start: nowT)
        let flow = LoginFlow(client: makeClient(transport, clock: clock, token: nil), clock: clock.runtime)
        // the queue is empty: every poll fails with "no connection"
        let challenge = try decodeJSON(LoginChallenge.self, SampleJSON.loginStart)
        do {
            _ = try await flow.waitForApproval(challenge)
            XCTFail("expected an error")
        } catch let e as APIError {
            XCTAssertEqual(e.code, "login_expired")
            XCTAssertTrue(e.isLoginReset)
        }
        // polls at t = 2, 4, …, 120: the one at 120 is the final attempt
        XCTAssertEqual(transport.requests.count, 60)
        XCTAssertEqual(clock.now() - nowT, 120)
    }

    func testServerExpiry() async throws {
        let transport = MockTransport()
        let clock = FakeClock(start: nowT)
        let flow = LoginFlow(client: makeClient(transport, clock: clock, token: nil), clock: clock.runtime)
        transport.enqueue(200, #"{"state":"pending","expires_in":1}"#)
        transport.enqueue(410, #"{"error":"login_expired","message":"Время на подтверждение вышло — начни вход заново."}"#)
        let challenge = try decodeJSON(LoginChallenge.self, SampleJSON.loginStart)
        do {
            _ = try await flow.waitForApproval(challenge)
            XCTFail("expected an error")
        } catch let e as APIError {
            XCTAssertEqual(e.kind, .http)
            XCTAssertEqual(e.code, "login_expired")
        }
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testTooManyDevicesOnPoll() async throws {
        let transport = MockTransport()
        let clock = FakeClock(start: nowT)
        let flow = LoginFlow(client: makeClient(transport, clock: clock, token: nil), clock: clock.runtime)
        transport.enqueue(409, #"{"error":"too_many_devices","message":"Уже 10 телефонов с доступом — отзови старый в Настройках, в веб-панели или командой /apps в боте."}"#)
        let challenge = try decodeJSON(LoginChallenge.self, SampleJSON.loginStart)
        do {
            _ = try await flow.waitForApproval(challenge)
            XCTFail("expected an error")
        } catch let e as APIError {
            XCTAssertEqual(e.code, "too_many_devices")
            XCTAssertTrue(e.isLoginReset)
        }
    }

    func testCancelIgnoresResult() async throws {
        let transport = MockTransport()
        let flow = LoginFlow(client: makeClient(transport, token: nil))
        let challenge = try decodeJSON(LoginChallenge.self, SampleJSON.loginStart)
        transport.enqueue(200, SampleJSON.cancelOK)
        await flow.cancel(challenge)
        transport.enqueue(410, #"{"error":"login_expired"}"#)
        await flow.cancel(challenge)
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(transport.requests[0].url?.path, "/router/app/v1/auth/cancel")
        XCTAssertEqual(bodyJSON(transport.requests[0]), .object(["login_id": .string(challenge.loginID)]))
    }

    func testSecondsLeft() {
        XCTAssertEqual(LoginFlow.secondsLeft(deadline: 100, now: 100), 0)
        XCTAssertEqual(LoginFlow.secondsLeft(deadline: 100, now: 150), 0)
        XCTAssertEqual(LoginFlow.secondsLeft(deadline: 100, now: 99.2), 1)
        XCTAssertEqual(LoginFlow.secondsLeft(deadline: 220, now: 100), 120)
    }
}
