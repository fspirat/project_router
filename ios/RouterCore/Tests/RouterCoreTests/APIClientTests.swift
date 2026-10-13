import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import RouterCore

final class APIClientTests: XCTestCase {

    // MARK: - Request building

    func testStatusRequest() throws {
        let client = makeClient(MockTransport())
        let req = try client.makeRequest(Endpoint.status)
        XCTAssertEqual(req.url?.absoluteString, "https://example.test/router/app/v1/status")
        XCTAssertEqual(req.httpMethod, "GET")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer " + dummyToken)
        XCTAssertEqual(req.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertNil(req.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertNil(req.value(forHTTPHeaderField: "Origin"))
        XCTAssertNil(req.value(forHTTPHeaderField: "Cookie"))
        XCTAssertNil(req.httpBody)
        XCTAssertEqual(req.timeoutInterval, 30)
        XCTAssertFalse(req.httpShouldHandleCookies)
        XCTAssertFalse(req.url?.absoluteString.contains("fsr1_") ?? true)
    }

    func testTimeouts() throws {
        let client = makeClient(MockTransport())
        XCTAssertEqual(try client.makeRequest(Endpoint.net).timeoutInterval, 15)
        XCTAssertEqual(try client.makeRequest(Endpoint.led).timeoutInterval, 15)
        XCTAssertEqual(try client.makeRequest(Endpoint.me).timeoutInterval, 15)
        XCTAssertEqual(try client.makeRequest(Endpoint.data(range: .day)).timeoutInterval, 15)
        XCTAssertEqual(try client.makeRequest(Endpoint.action(.restart)).timeoutInterval, 30)
        XCTAssertEqual(try client.makeRequest(Endpoint.job(id: "fbe9f93b0caf8a91")).timeoutInterval, 15)
    }

    func testBaseURLWithoutTrailingSlash() throws {
        let box = TokenBox(dummyToken)
        let client = APIClient(baseURL: URL(string: "https://example.test/router/app/v1")!, transport: MockTransport(), tokenProvider: { box.token })
        XCTAssertEqual(try client.makeRequest(Endpoint.me).url?.absoluteString, "https://example.test/router/app/v1/me")
    }

    func testOnlyRangeQuery() throws {
        let client = makeClient(MockTransport())
        let req = try client.makeRequest(Endpoint.data(range: .week))
        XCTAssertEqual(req.url?.absoluteString, "https://example.test/router/app/v1/data?range=week")
        let comps = try XCTUnwrap(URLComponents(url: try XCTUnwrap(req.url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(comps.queryItems?.count, 1)
        XCTAssertEqual(comps.queryItems?.first?.name, "range")
        XCTAssertNil(try client.makeRequest(Endpoint.status).url?.query)
    }

    func testPostBodies() throws {
        let client = makeClient(MockTransport())

        let restart = try client.makeRequest(Endpoint.action(.restart))
        XCTAssertEqual(restart.httpMethod, "POST")
        XCTAssertEqual(restart.url?.absoluteString, "https://example.test/router/app/v1/action/restart")
        XCTAssertEqual(restart.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(String(decoding: try XCTUnwrap(restart.httpBody), as: UTF8.self), "{}")

        let confirmed = try client.makeRequest(Endpoint.action(.reboot, confirm: "e9cd4613c347db5985111bd0d7e5e582"))
        XCTAssertEqual(String(decoding: try XCTUnwrap(confirmed.httpBody), as: UTF8.self), #"{"confirm":"e9cd4613c347db5985111bd0d7e5e582"}"#)

        let ledOff = try client.makeRequest(Endpoint.action(.ledset(on: false)))
        XCTAssertEqual(String(decoding: try XCTUnwrap(ledOff.httpBody), as: UTF8.self), #"{"on":false}"#)
        XCTAssertEqual(bodyJSON(ledOff)?["on"], .bool(false))
        let ledOn = try client.makeRequest(Endpoint.action(.ledset(on: true)))
        XCTAssertEqual(bodyJSON(ledOn)?["on"], .bool(true))

        let logout = try client.makeRequest(Endpoint.logout)
        XCTAssertEqual(String(decoding: try XCTUnwrap(logout.httpBody), as: UTF8.self), "{}")
        XCTAssertNotNil(logout.value(forHTTPHeaderField: "Authorization"))
    }

    func testLoginRequestHasNoAuthorization() throws {
        let client = makeClient(MockTransport(), token: nil)
        let device = DeviceInfo(name: "iPhone владельца", model: "iPhone15,2", os: "iOS 18.1", app: "1.0 (42)")
        let req = try client.makeRequest(Endpoint.login(password: "pa\"ss", device: device))
        XCTAssertEqual(req.url?.absoluteString, "https://example.test/router/app/v1/auth/login")
        XCTAssertNil(req.value(forHTTPHeaderField: "Authorization"))
        let body = try XCTUnwrap(bodyJSON(req))
        XCTAssertEqual(body["password"], .string("pa\"ss"))
        XCTAssertEqual(body["device"]?["name"], .string("iPhone владельца"))
        XCTAssertEqual(body["device"]?["model"], .string("iPhone15,2"))
        XCTAssertEqual(body["device"]?["os"], .string("iOS 18.1"))
        XCTAssertEqual(body["device"]?["app"], .string("1.0 (42)"))
        XCTAssertEqual(body.objectValue?.count, 2)
        XCTAssertEqual(body["device"]?.objectValue?.count, 4)

        let poll = try client.makeRequest(Endpoint.poll(loginID: String(repeating: "ab", count: 32)))
        XCTAssertEqual(poll.url?.absoluteString, "https://example.test/router/app/v1/auth/poll")
        XCTAssertNil(poll.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(bodyJSON(poll), .object(["login_id": .string(String(repeating: "ab", count: 32))]))
    }

    func testMissingOrMalformedTokenIsNeverSent() async throws {
        let transport = MockTransport()
        let noToken = makeClient(transport, token: nil)
        do {
            _ = try await noToken.status()
            XCTFail("expected an error")
        } catch let e as APIError {
            XCTAssertTrue(e.isAuthFailure)
            XCTAssertEqual(e.kind, .client)
            XCTAssertEqual(e.code, "token_missing")
        }
        let badToken = makeClient(transport, token: "fsr1_short")
        do {
            _ = try await badToken.status()
            XCTFail("expected an error")
        } catch let e as APIError {
            XCTAssertTrue(e.isAuthFailure)
        }
        XCTAssertEqual(transport.requests.count, 0)
    }

    func testUnsafePathsAreRefused() {
        let client = makeClient(MockTransport())
        XCTAssertThrowsError(try client.makeRequest(Endpoint(method: .get, path: "/status", requiresAuth: true, timeout: 15)))
        XCTAssertThrowsError(try client.makeRequest(Endpoint(method: .get, path: "status?x=1", requiresAuth: true, timeout: 15)))
        XCTAssertThrowsError(try client.makeRequest(Endpoint(method: .get, path: "jobs/../me", requiresAuth: true, timeout: 15)))
        XCTAssertThrowsError(try client.makeRequest(Endpoint(method: .get, path: "x/fsr1_abc", requiresAuth: true, timeout: 15)))
        let http = APIClient(baseURL: URL(string: "http://example.test/router/app/v1/")!, transport: MockTransport(), tokenProvider: { nil })
        XCTAssertThrowsError(try http.makeRequest(Endpoint.status))
    }

    func testSessionConfiguration() {
        let c = URLSessionTransport.makeConfiguration()
        XCTAssertFalse(c.httpShouldSetCookies)
        XCTAssertEqual(c.httpCookieAcceptPolicy, .never)
        XCTAssertNil(c.httpCookieStorage)
        XCTAssertNil(c.urlCache)
        XCTAssertEqual(c.requestCachePolicy, .reloadIgnoringLocalCacheData)
        XCTAssertEqual(c.timeoutIntervalForRequest, 30)
    }

    func testDefaultTransportRefusesRedirects() throws {
        // The default session has the no-redirect delegate, which answers every redirect with nil.
        let transport = URLSessionTransport()
        let delegate = try XCTUnwrap(transport.session.delegate as? NoRedirectDelegate)
        let from = URL(string: "https://example.test/router/app/v1/status")!
        let to = URL(string: "https://other.example/steal")!
        let response = try XCTUnwrap(HTTPURLResponse(url: from, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": to.absoluteString]))
        var next = URLRequest(url: to)
        next.setValue("Bearer fsr1_test", forHTTPHeaderField: "Authorization")
        let task = transport.session.dataTask(with: URLRequest(url: from))
        let answered = expectation(description: "completion")
        delegate.urlSession(transport.session, task: task, willPerformHTTPRedirection: response, newRequest: next) { request in
            XCTAssertNil(request)
            answered.fulfill()
        }
        wait(for: [answered], timeout: 1)
        transport.session.invalidateAndCancel()
    }

    // MARK: - Reads

    func testReadsDecode() async throws {
        let transport = MockTransport()
        let client = makeClient(transport)
        transport.enqueue(200, SampleJSON.statusNormal)
        transport.enqueue(200, SampleJSON.net)
        transport.enqueue(200, SampleJSON.ledAbsent)
        transport.enqueue(200, SampleJSON.dataDay)
        transport.enqueue(200, SampleJSON.me)
        let s = try await client.status()
        XCTAssertEqual(s.current, "Kq7Lm2Xp")
        let n = try await client.net()
        XCTAssertEqual(n.rx, 18734216)
        let l = try await client.led()
        XCTAssertFalse(l.isAvailable)
        let d = try await client.data()
        XCTAssertEqual(d.events.count, 6)
        let me = try await client.me()
        XCTAssertEqual(me.device.id, "49139e3a1db5a6ac")
        let urls = transport.requests.map { $0.url?.absoluteString ?? "" }
        XCTAssertEqual(urls, [
            "https://example.test/router/app/v1/status",
            "https://example.test/router/app/v1/net",
            "https://example.test/router/app/v1/led",
            "https://example.test/router/app/v1/data?range=day",
            "https://example.test/router/app/v1/me"
        ])
        for r in transport.requests {
            XCTAssertEqual(r.value(forHTTPHeaderField: "Authorization"), "Bearer " + dummyToken)
        }
    }

    func testReadErrors() async throws {
        let transport = MockTransport()
        let client = makeClient(transport)
        transport.enqueue(502, #"{"error":"router_offline","message":"Роутер не на связи: туннель до сервера оборван или дома нет интернета."}"#)
        transport.enqueue(401, #"{"error":"token_revoked","message":"Доступ этого телефона отозван — войди заново."}"#, headers: ["WWW-Authenticate": "Bearer error=\"invalid_token\""])
        transport.enqueue(200, "<html>captive portal</html>")
        transport.enqueueFailure(URLError(.timedOut))
        transport.enqueue(429, #"{"error":"rate_limited","retry_after":2}"#, headers: ["Retry-After": "2"])

        do {
            _ = try await client.status()
            XCTFail("expected an error")
        } catch let e as APIError {
            XCTAssertTrue(e.entersOfflineMode)
        }
        do {
            _ = try await client.status()
            XCTFail("expected an error")
        } catch let e as APIError {
            XCTAssertTrue(e.isAuthFailure)
            XCTAssertEqual(e.userMessage, "Доступ этого телефона отозван — войди заново.")
        }
        do {
            _ = try await client.status()
            XCTFail("expected an error")
        } catch let e as APIError {
            XCTAssertEqual(e.kind, .badResponse)
            XCTAssertTrue(e.isTransient)
        }
        do {
            _ = try await client.net()
            XCTFail("expected an error")
        } catch let e as APIError {
            XCTAssertEqual(e.kind, .noConnection)
        }
        do {
            _ = try await client.data()
            XCTFail("expected an error")
        } catch let e as APIError {
            XCTAssertEqual(e.retryAfter, 2)
            XCTAssertEqual(e.userMessage, "Слишком часто — подожди немного. Повтори через 2\u{00A0}с.")
        }
    }

    // MARK: - Actions

    func testConfirmFlow() async throws {
        let transport = MockTransport()
        let clock = FakeClock(start: nowT)
        let client = makeClient(transport, clock: clock)
        transport.enqueue(428, SampleJSON.confirmRestart)
        transport.enqueue(200, #"{"ok":true}"#)

        let first = try await client.perform(.restart)
        guard case .confirm(let prompt) = first else {
            return XCTFail("expected a confirm")
        }
        XCTAssertEqual(prompt.title, "Перезапустить VPN?")
        XCTAssertEqual(prompt.button, "Перезапустить")
        XCTAssertEqual(prompt.receivedAt, nowT)
        XCTAssertTrue(prompt.canResend(now: nowT + 54))
        XCTAssertFalse(prompt.canResend(now: nowT + 55))

        let second = try await client.perform(.restart, confirm: prompt.confirm)
        XCTAssertEqual(second, .done(.object(["ok": .bool(true)])))

        let reqs = transport.requests
        XCTAssertEqual(reqs.count, 2)
        XCTAssertEqual(String(decoding: try XCTUnwrap(reqs[0].httpBody), as: UTF8.self), "{}")
        XCTAssertEqual(bodyJSON(reqs[1]), .object(["confirm": .string("79217acbd9c66e9e1af7693324516b75")]))
    }

    func testConfirmResendFailures() async throws {
        let transport = MockTransport()
        let client = makeClient(transport)
        transport.enqueue(400, #"{"error":"confirm_invalid","message":"Подтверждение не подошло — повтори действие."}"#)
        transport.enqueue(409, #"{"error":"busy","message":"Другое действие ещё выполняется — подожди немного."}"#)
        transport.enqueue(504, #"{"error":"router_timeout","message":"Роутер не ответил вовремя."}"#)
        transport.enqueue(428, SampleJSON.confirmReboot)
        let c = "e9cd4613c347db5985111bd0d7e5e582"

        do {
            _ = try await client.perform(.reboot, confirm: c)
            XCTFail("expected an error")
        } catch let e as APIError {
            XCTAssertEqual(e.code, "confirm_invalid")
        }
        do {
            _ = try await client.perform(.reboot, confirm: c)
            XCTFail("expected an error")
        } catch let e as APIError {
            XCTAssertTrue(e.isBusy)
        }
        do {
            _ = try await client.perform(.reboot, confirm: c)
            XCTFail("expected an error")
        } catch let e as APIError {
            XCTAssertTrue(e.mayHaveExecuted)
            XCTAssertTrue(e.actionMessage.hasSuffix("Действие могло выполниться — проверь состояние через минуту."))
        }
        // expired confirm → a new 428 dialog
        let again = try await client.perform(.reboot, confirm: c)
        guard case .confirm(let p) = again else {
            return XCTFail("expected a new confirm")
        }
        XCTAssertTrue(p.requiresBiometrics)
    }

    func testConfirmIsRefusedLocallyForPing() async throws {
        let transport = MockTransport()
        let client = makeClient(transport)
        do {
            _ = try await client.perform(.ping, confirm: "79217acbd9c66e9e1af7693324516b75")
            XCTFail("expected an error")
        } catch let e as APIError {
            XCTAssertEqual(e.kind, .client)
        }
        do {
            _ = try await client.perform(.ledset(on: true), confirm: "79217acbd9c66e9e1af7693324516b75")
            XCTFail("expected an error")
        } catch let e as APIError {
            XCTAssertEqual(e.kind, .client)
        }
        XCTAssertEqual(transport.requests.count, 0)
    }

    func testRateLimitedActionHasNoDialog() async throws {
        let transport = MockTransport()
        let client = makeClient(transport)
        transport.enqueue(429, #"{"error":"rate_limited","message":"Слишком часто — подожди немного.","retry_after":15}"#, headers: ["Retry-After": "15"])
        do {
            _ = try await client.perform(.update)
            XCTFail("expected an error")
        } catch let e as APIError {
            XCTAssertTrue(e.isRateLimited)
            XCTAssertEqual(e.retryAfter, 15)
            XCTAssertEqual(e.actionMessage, "Слишком часто — подожди немного. Повтори через 15\u{00A0}с.")
        }
    }

    func testSetLED() async throws {
        let transport = MockTransport()
        let client = makeClient(transport)
        transport.enqueue(200, SampleJSON.ledsetOff)
        let led = try await client.setLED(on: false)
        XCTAssertFalse(led.on)
        XCTAssertTrue(led.isAvailable)
        XCTAssertEqual(transport.requests.first?.url?.absoluteString, "https://example.test/router/app/v1/action/ledset")

        transport.enqueue(503, #"{"error":"not installed","message":"Не установлено на роутере.","source":"router"}"#)
        do {
            _ = try await client.setLED(on: true)
            XCTFail("expected an error")
        } catch let e as APIError {
            XCTAssertEqual(e.userMessage, "Не установлено на роутере.")
            XCTAssertEqual(e.source, "router")
        }
    }

    // MARK: - Jobs

    func testPingJob() async throws {
        let transport = MockTransport()
        let clock = FakeClock(start: nowT)
        let client = makeClient(transport, clock: clock)
        transport.enqueue(202, SampleJSON.jobStart, headers: ["Connection": "close"])
        transport.enqueue(200, SampleJSON.jobRunning)
        transport.enqueue(503, #"{"error":"server_unavailable"}"#)
        transport.enqueueFailure(URLError(.networkConnectionLost))
        transport.enqueue(200, SampleJSON.jobDone)

        let started = try await client.perform(.ping)
        guard case .job(let id, let every) = started else {
            return XCTFail("expected a job")
        }
        XCTAssertEqual(id, "fbe9f93b0caf8a91")
        XCTAssertEqual(every, 3)
        let startedAt = clock.now()
        let done = try await client.waitForJob(id: id, pollEvery: every)
        XCTAssertEqual(done.action, "ping")
        XCTAssertEqual(done.status?.current, "Kq7Lm2Xp")
        XCTAssertEqual(clock.sleeps, [3, 3, 3, 3])
        XCTAssertEqual(transport.requests.count, 5)
        XCTAssertEqual(transport.requests[1].url?.absoluteString, "https://example.test/router/app/v1/jobs/fbe9f93b0caf8a91")
        XCTAssertEqual(transport.requests[1].httpMethod, "GET")
        // the result is older than the job → «Показаны данные последней проверки»
        XCTAssertTrue(ActionTexts.isStale(try XCTUnwrap(done.status), jobStartedAt: startedAt))
        XCTAssertFalse(ActionTexts.isStale(try XCTUnwrap(done.status), jobStartedAt: 1791886200))
    }

    func testJobErrorAndTimeout() async throws {
        let transport = MockTransport()
        let clock = FakeClock(start: nowT)
        let client = makeClient(transport, clock: clock)
        transport.enqueue(200, SampleJSON.jobErrorOffline)
        do {
            _ = try await client.waitForJob(id: "fbe9f93b0caf8a91", pollEvery: 3)
            XCTFail("expected an error")
        } catch let e as APIError {
            XCTAssertEqual(e.code, "router_offline")
            XCTAssertEqual(e.status, 502)
            XCTAssertEqual(ActionTexts.pingJobErrorMessage(e), "Роутер не на связи: туннель до сервера оборван или дома нет интернета.")
        }

        transport.setFallback(.http(status: 200, body: SampleJSON.jobRunning, headers: [:]))
        let before = clock.now()
        do {
            _ = try await client.waitForJob(id: "fbe9f93b0caf8a91", pollEvery: 3)
            XCTFail("expected a timeout")
        } catch let e as APIError {
            XCTAssertEqual(e.code, "job_timeout")
            XCTAssertEqual(ActionTexts.pingJobErrorMessage(e), ActionTexts.pingSlow)
        }
        XCTAssertGreaterThanOrEqual(clock.now() - before, 160)
        XCTAssertLessThan(clock.now() - before, 170)
    }

    func testJobNotFoundStops() async throws {
        let transport = MockTransport()
        let client = makeClient(transport)
        transport.enqueue(404, #"{"error":"not_found","message":"Не найдено."}"#)
        do {
            _ = try await client.waitForJob(id: "fbe9f93b0caf8a91", pollEvery: 3)
            XCTFail("expected an error")
        } catch let e as APIError {
            XCTAssertEqual(e.code, "not_found")
        }
        XCTAssertEqual(transport.requests.count, 1)
    }
}
