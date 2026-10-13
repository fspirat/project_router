import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import RouterCore

/// Stage 4 actions: bodies, validation, the 428 flow for revoke-all, jobs, aftermath, error policy, local patches.
final class ActionsStage4Tests: XCTestCase {

    let mac = "00:00:5e:00:53:03"

    func body(_ a: RouterAction, confirm: String? = nil) throws -> JSONValue {
        let ep = Endpoint.action(a, confirm: confirm)
        return try JSONValue.parse(try XCTUnwrap(ep.body))
    }

    func rawBody(_ a: RouterAction, confirm: String? = nil) throws -> String {
        return String(decoding: try XCTUnwrap(Endpoint.action(a, confirm: confirm).body), as: UTF8.self)
    }

    // MARK: - Bodies and paths

    func testBodies() throws {
        XCTAssertEqual(try body(.pingone(id: "Wm6Tj2Gk")), .object(["id": .string("Wm6Tj2Gk")]))
        XCTAssertEqual(try body(.switchServer(id: "Hd3Fs9Qa")), .object(["id": .string("Hd3Fs9Qa")]))
        XCTAssertEqual(try body(.switchDirect), .object(["id": .string("direct")]))
        XCTAssertEqual(try body(.subupdate(sid: "cfg7d8e9f")), .object(["sid": .string("cfg7d8e9f")]))
        XCTAssertEqual(try body(.subupdateAll), .object(["all": .bool(true)]))
        XCTAssertEqual(try body(.speedtest(via: .vpn)), .object(["via": .string("vpn")]))
        XCTAssertEqual(try body(.speedtest(via: .direct)), .object(["via": .string("direct")]))
        XCTAssertEqual(try body(.block(mac: "00:00:5E:00:53:03")), .object(["mac": .string(mac)]), "MAC is lowercased")
        XCTAssertEqual(try body(.unblock(mac: mac)), .object(["mac": .string(mac)]))
        XCTAssertEqual(try body(.direct(mac: mac, on: true)), .object(["mac": .string(mac), "on": .bool(true)]))
        XCTAssertEqual(try body(.direct(mac: mac, on: false)), .object(["mac": .string(mac), "on": .bool(false)]))
        XCTAssertEqual(try body(.schedule(mac: mac, off: "2300", on: "0700")), .object(["mac": .string(mac), "off": .string("2300"), "on": .string("0700")]))
        XCTAssertEqual(try body(.scheduleClear(mac: mac)), .object(["mac": .string(mac), "off": .string(""), "on": .string("")]))
        XCTAssertEqual(try body(.diradd(domain: "ozon.ru")), .object(["d": .string("ozon.ru")]))
        XCTAssertEqual(try body(.dirdel(domain: "kinopoisk.ru")), .object(["d": .string("kinopoisk.ru")]))
        XCTAssertEqual(try body(.svcdirect(name: "YouTube", on: true)), .object(["name": .string("YouTube"), "on": .bool(true)]))
        XCTAssertEqual(try body(.zapretset(on: false)), .object(["on": .bool(false)]))
        XCTAssertEqual(try body(.zapretstrat(n: 2)), .object(["n": .int(2)]), "n is a JSON int")
        XCTAssertEqual(try rawBody(.zapretstrat(n: 2)), #"{"n":2}"#)
        XCTAssertEqual(try rawBody(.zapretcheck), "{}")
        XCTAssertEqual(try body(.tgwsset(on: true)), .object(["on": .bool(true)]))
        XCTAssertEqual(try body(.rename(mac: "00:00:5E:00:53:03", name: "  Телевизор ")), .object(["mac": .string(mac), "name": .string("Телевизор")]))
        XCTAssertEqual(try body(.rename(mac: mac, name: "")), .object(["mac": .string(mac), "name": .string("")]))
        XCTAssertEqual(try body(.revokeApp(id: "8df5a0cb8a35a59a")), .object(["id": .string("8df5a0cb8a35a59a")]))
        XCTAssertEqual(try body(.revokeWeb(ref: "8207c706de3f72c7")), .object(["web_ref": .string("8207c706de3f72c7")]))
        XCTAssertEqual(try body(.revokeAll(web: false)), .object(["web": .bool(false)]))
        // keys sorted, confirm included
        XCTAssertEqual(
            try rawBody(.schedule(mac: mac, off: "2300", on: "0700"), confirm: "4d04926fe9ee90be9407a94746cb0920"),
            #"{"confirm":"4d04926fe9ee90be9407a94746cb0920","mac":"00:00:5e:00:53:03","off":"2300","on":"0700"}"#
        )
        XCTAssertEqual(try rawBody(.revokeAll(web: true), confirm: "518a7f2c40f50edf1a650e872fb6cb70"), #"{"confirm":"518a7f2c40f50edf1a650e872fb6cb70","web":true}"#)
    }

    func testPathsAndTimeouts() throws {
        let client = makeClient(MockTransport())
        XCTAssertEqual(try client.makeRequest(Endpoint.action(.switchDirect)).url?.absoluteString, "https://example.test/router/app/v1/action/switch")
        XCTAssertEqual(try client.makeRequest(Endpoint.action(.subupdateAll)).url?.absoluteString, "https://example.test/router/app/v1/action/subupdate")
        XCTAssertEqual(try client.makeRequest(Endpoint.action(.scheduleClear(mac: mac))).url?.absoluteString, "https://example.test/router/app/v1/action/schedule")
        let revoke = try client.makeRequest(Endpoint.action(.revokeApp(id: "8df5a0cb8a35a59a")))
        XCTAssertEqual(revoke.url?.absoluteString, "https://example.test/router/app/v1/devices/revoke")
        XCTAssertEqual(revoke.timeoutInterval, 15)
        XCTAssertEqual(revoke.httpMethod, "POST")
        let all = try client.makeRequest(Endpoint.action(.revokeAll(web: false)))
        XCTAssertEqual(all.url?.absoluteString, "https://example.test/router/app/v1/devices/revoke-all")
        XCTAssertEqual(try client.makeRequest(Endpoint.action(.zapretcheck)).timeoutInterval, 30)
        XCTAssertEqual(try client.makeRequest(Endpoint.zapret).url?.absoluteString, "https://example.test/router/app/v1/zapret")
        XCTAssertEqual(try client.makeRequest(Endpoint.tgws).url?.absoluteString, "https://example.test/router/app/v1/tgws")
        XCTAssertEqual(try client.makeRequest(Endpoint.mydirect).url?.absoluteString, "https://example.test/router/app/v1/mydirect")
        XCTAssertEqual(try client.makeRequest(Endpoint.vds).url?.absoluteString, "https://example.test/router/app/v1/vds")
        let dev = try client.makeRequest(Endpoint.devices)
        XCTAssertEqual(dev.url?.absoluteString, "https://example.test/router/app/v1/devices")
        XCTAssertEqual(dev.httpMethod, "GET")
        XCTAssertEqual(dev.timeoutInterval, 15)
        XCTAssertTrue(APIClient.isSafePath("devices/revoke-all"))
        XCTAssertFalse(APIClient.isSafePath("-x"))
        XCTAssertFalse(APIClient.isSafePath("action/../x"))
        XCTAssertFalse(APIClient.isSafePath("action/Switch"))
    }

    func testNamesAndFlags() {
        XCTAssertEqual(RouterAction.switchDirect.name, "switch")
        XCTAssertTrue(RouterAction.switchDirect.isSwitchDirect)
        XCTAssertFalse(RouterAction.switchServer(id: "Hd3Fs9Qa").isSwitchDirect)
        XCTAssertEqual(RouterAction.revokeAll(web: true).name, "revoke-all")
        XCTAssertEqual(RouterAction.revokeWeb(ref: "x").path, "devices/revoke")

        let confirmable: [RouterAction] = [
            .restart, .update, .reboot, .switchServer(id: "a"), .switchDirect, .subupdate(sid: "a"), .subupdateAll,
            .block(mac: mac), .direct(mac: mac, on: true), .schedule(mac: mac, off: "2300", on: "0700"),
            .diradd(domain: "a.ru"), .dirdel(domain: "a.ru"), .svcdirect(name: "YouTube", on: true),
            .zapretset(on: true), .tgwsset(on: true), .revokeAll(web: false)
        ]
        let plain: [RouterAction] = [
            .ping, .ledset(on: true), .pingone(id: "a"), .speedtest(via: .vpn), .unblock(mac: mac), .scheduleClear(mac: mac),
            .zapretstrat(n: 1), .zapretcheck, .rename(mac: mac, name: "x"), .revokeApp(id: "a"), .revokeWeb(ref: "a")
        ]
        for a in confirmable {
            XCTAssertTrue(a.isConfirmable, a.name)
            XCTAssertNotNil(a.expectedDanger, a.name)
        }
        for a in plain {
            XCTAssertFalse(a.isConfirmable, a.name)
            XCTAssertNil(a.expectedDanger, a.name)
        }
        XCTAssertEqual(RouterAction.switchDirect.expectedDanger, .critical)
        XCTAssertEqual(RouterAction.switchServer(id: "Hd3Fs9Qa").expectedDanger, .high)
        XCTAssertEqual(RouterAction.revokeAll(web: true).expectedDanger, .critical)
        XCTAssertEqual(RouterAction.schedule(mac: mac, off: "2300", on: "0700").expectedDanger, .medium)
        XCTAssertEqual(RouterAction.tgwsset(on: true).expectedDanger, .medium)
        XCTAssertEqual(RouterAction.block(mac: mac).expectedDanger, .high)

        XCTAssertTrue(RouterAction.speedtest(via: .vpn).isJob)
        XCTAssertTrue(RouterAction.ping.isJob)
        XCTAssertFalse(RouterAction.pingone(id: "a").isJob)

        let pw: [RouterAction] = [.switchDirect, .restart, .update, .subupdate(sid: "a"), .subupdateAll, .direct(mac: mac, on: true), .diradd(domain: "a.ru"), .dirdel(domain: "a.ru"), .svcdirect(name: "x", on: true), .zapretset(on: true)]
        for a in pw {
            XCTAssertTrue(a.isPassWall, a.name)
            XCTAssertTrue(ActionAftermath.passWallActionNames.contains(a.name))
        }
        for a in [RouterAction.block(mac: mac), .tgwsset(on: true), .zapretstrat(n: 1), .reboot, .rename(mac: mac, name: "")] {
            XCTAssertFalse(a.isPassWall, a.name)
        }

        XCTAssertTrue(RouterAction.block(mac: mac).forcesDestructiveConfirm)
        XCTAssertTrue(RouterAction.dirdel(domain: "a.ru").forcesDestructiveConfirm)
        XCTAssertTrue(RouterAction.revokeAll(web: false).forcesDestructiveConfirm)
        XCTAssertFalse(RouterAction.diradd(domain: "a.ru").forcesDestructiveConfirm)
        XCTAssertFalse(RouterAction.direct(mac: mac, on: true).forcesDestructiveConfirm)

        XCTAssertTrue(RouterAction.rename(mac: mac, name: "").worksOffline)
        XCTAssertTrue(RouterAction.revokeAll(web: false).worksOffline)
        XCTAssertFalse(RouterAction.block(mac: mac).worksOffline)
    }

    func testDestructiveAndBiometrics() throws {
        let block = try decodeJSON(ConfirmPrompt.self, SampleJSON.confirmBlockNamed)
        XCTAssertFalse(block.isDestructive)
        XCTAssertTrue(block.isDestructive(for: .block(mac: mac)))
        XCTAssertFalse(block.requiresBiometrics, "block is not Face ID")
        let dirdel = try decodeJSON(ConfirmPrompt.self, SampleJSON.confirmDirdel)
        XCTAssertTrue(dirdel.isDestructive(for: .dirdel(domain: "kinopoisk.ru")))
        let diradd = try decodeJSON(ConfirmPrompt.self, SampleJSON.confirmDiradd)
        XCTAssertFalse(diradd.isDestructive(for: .diradd(domain: "ozon.ru")))
        let direct = try decodeJSON(ConfirmPrompt.self, SampleJSON.confirmSwitchDirect)
        XCTAssertTrue(direct.isDestructive(for: .switchDirect))
        XCTAssertTrue(direct.requiresBiometrics)
        let all = try decodeJSON(ConfirmPrompt.self, SampleJSON.confirmRevokeAll)
        XCTAssertTrue(all.requiresBiometrics)
        XCTAssertTrue(all.isDestructive(for: .revokeAll(web: false)))
        let sched = try decodeJSON(ConfirmPrompt.self, SampleJSON.confirmSchedule)
        XCTAssertFalse(sched.requiresBiometrics)
        XCTAssertFalse(sched.isDestructive(for: .schedule(mac: mac, off: "2300", on: "0700")))
        let tg = try decodeJSON(ConfirmPrompt.self, SampleJSON.confirmTgwsOn)
        XCTAssertFalse(tg.requiresBiometrics)
    }

    // MARK: - Validation

    func testValidationAcceptsGoodParameters() {
        let good: [RouterAction] = [
            .pingone(id: "Wm6Tj2Gk"), .switchServer(id: "Hd3Fs9Qa"), .switchDirect, .subupdate(sid: "cfg_5a1b2c"), .subupdateAll,
            .speedtest(via: .direct), .block(mac: "00:00:5E:00:53:03"), .unblock(mac: mac), .direct(mac: mac, on: true),
            .schedule(mac: mac, off: "2300", on: "0700"), .schedule(mac: mac, off: "0000", on: "2359"), .scheduleClear(mac: mac),
            .diradd(domain: "ozon.ru"), .diradd(domain: "a.ru"), .diradd(domain: "xn--80ak6aa92e.com"), .diradd(domain: "my-site.example.co"),
            .dirdel(domain: "kinopoisk.ru"), .svcdirect(name: "Хайпиксель", on: true), .svcdirect(name: String(repeating: "я", count: 20), on: false),
            .zapretset(on: true), .zapretstrat(n: 1), .zapretstrat(n: 3), .zapretcheck, .tgwsset(on: false),
            .rename(mac: mac, name: ""), .rename(mac: mac, name: "   "), .rename(mac: mac, name: String(repeating: "Ж", count: 40)),
            .rename(mac: mac, name: "  " + String(repeating: "a", count: 40) + "  "),
            .revokeApp(id: "8df5a0cb8a35a59a"), .revokeWeb(ref: "8207c706de3f72c7"), .revokeAll(web: true),
            .ping, .restart, .update, .reboot, .ledset(on: true)
        ]
        for a in good {
            XCTAssertNil(a.validationError, "\(a)")
        }
    }

    func testValidationRefusesBadParameters() {
        let bad: [RouterAction] = [
            .pingone(id: "direct"), .pingone(id: "_direct"), .pingone(id: ""), .pingone(id: String(repeating: "a", count: 33)),
            .switchServer(id: "_direct"), .switchServer(id: "a-b"), .subupdate(sid: "cfg-1"), .subupdate(sid: ""),
            .block(mac: "00:00:5e:00:53"), .block(mac: "00-00-5e-00-53-03"), .unblock(mac: "zz:00:5e:00:53:03"),
            .direct(mac: "", on: true), .scheduleClear(mac: "x"),
            .diradd(domain: "Ozon.ru"), .diradd(domain: "сайт.рф"), .diradd(domain: "a.b"), .diradd(domain: "-a.ru"), .diradd(domain: "a-.ru"),
            .diradd(domain: "ozon"), .diradd(domain: "a..ru"), .diradd(domain: "1.23"), .diradd(domain: "https://ozon.ru"),
            .diradd(domain: String(repeating: "a", count: 60) + "." + String(repeating: "b", count: 40) + ".ru"),
            .dirdel(domain: "geosite:category-ru"),
            .svcdirect(name: "", on: true), .svcdirect(name: "A&B", on: true), .svcdirect(name: "a|b", on: true), .svcdirect(name: "a\nb", on: true),
            .svcdirect(name: "~x", on: true), .svcdirect(name: String(repeating: "я", count: 21), on: true),
            .zapretstrat(n: 0), .zapretstrat(n: 4), .rename(mac: mac, name: "a\tb"), .rename(mac: "bad", name: "x"),
            .revokeApp(id: "8DF5A0CB8A35A59A"), .revokeApp(id: "abc"), .revokeWeb(ref: "")
        ]
        for a in bad {
            XCTAssertNotNil(a.validationError, "\(a)")
        }
        XCTAssertEqual(RouterAction.diradd(domain: "сайт.рф").validationError, "Нужен домен вида site.ru")
        XCTAssertEqual(RouterAction.schedule(mac: mac, off: "2300", on: "2300").validationError, "Укажи разное время выключения и включения.")
        XCTAssertEqual(RouterAction.schedule(mac: mac, off: "23:00", on: "0700").validationError, "Неверное время.")
        XCTAssertEqual(RouterAction.schedule(mac: mac, off: "2400", on: "0700").validationError, "Неверное время.")
        XCTAssertEqual(RouterAction.schedule(mac: mac, off: "2360", on: "0700").validationError, "Неверное время.")
        XCTAssertEqual(RouterAction.svcdirect(name: "A&B", on: true).validationError, "Это имя нельзя изменить из приложения.")
        let long = Validation.actionError(.rename(mac: mac, name: String(repeating: "Ж", count: 41)))
        XCTAssertEqual(long?.code, "too_long")
        XCTAssertEqual(long?.userMessage, "Слишком длинное значение.")
        XCTAssertEqual(Validation.actionError(.zapretstrat(n: 9))?.code, "bad_param")
    }

    func testValidationHelpers() {
        XCTAssertTrue(Validation.isValidMAC("00:00:5e:00:53:03"))
        XCTAssertFalse(Validation.isValidMAC("00:00:5E:00:53:03"))
        XCTAssertTrue(Validation.isValidHHMM("0000"))
        XCTAssertTrue(Validation.isValidHHMM("2359"))
        XCTAssertFalse(Validation.isValidHHMM("2400"))
        XCTAssertFalse(Validation.isValidHHMM("1260"))
        XCTAssertFalse(Validation.isValidHHMM("700"))
        XCTAssertTrue(Validation.isValidDomain(String(repeating: "a", count: 63) + ".ru"))
        XCTAssertFalse(Validation.isValidDomain(String(repeating: "a", count: 64) + ".ru"))
        XCTAssertFalse(Validation.isValidDomain(String(repeating: "a.", count: 50) + "ru"), "102 bytes")
        XCTAssertTrue(Validation.isValidDomain(String(repeating: "a.", count: 49) + "ru"), "100 bytes")
        XCTAssertTrue(Validation.isValidServiceName(String(repeating: "x", count: 40)))
        XCTAssertFalse(Validation.isValidServiceName(String(repeating: "x", count: 41)))
        XCTAssertEqual(Validation.renameValue("  ТВ \n"), "ТВ")
        XCTAssertEqual(Validation.limitRenameInput("a\u{0007}b" + String(repeating: "c", count: 50)).unicodeScalars.count, 40)
        XCTAssertTrue(Validation.limitRenameInput("a\u{0007}b").hasPrefix("ab"))
        XCTAssertTrue(Validation.isValidHex16("8207c706de3f72c7"))
        XCTAssertTrue(Validation.isValidSubscriptionID("cfg_5a1b2c"))
        XCTAssertFalse(Validation.isValidNodeID("_direct"))
    }

    // MARK: - Client

    func testPerformRefusesInvalidLocally() async throws {
        let transport = MockTransport()
        let client = makeClient(transport)
        do {
            _ = try await client.perform(.diradd(domain: "сайт.рф"))
            XCTFail("expected an error")
        } catch let e as APIError {
            XCTAssertEqual(e.kind, .client)
            XCTAssertEqual(e.code, "bad_param")
            XCTAssertEqual(e.userMessage, "Нужен домен вида site.ru")
        }
        do {
            _ = try await client.perform(.rename(mac: mac, name: String(repeating: "ы", count: 41)))
            XCTFail("expected an error")
        } catch let e as APIError {
            XCTAssertEqual(e.code, "too_long")
        }
        do {
            _ = try await client.perform(.unblock(mac: mac), confirm: "79217acbd9c66e9e1af7693324516b75")
            XCTFail("expected an error")
        } catch let e as APIError {
            XCTAssertEqual(e.code, "bad_param", "confirm on a non-confirmable action is refused")
        }
        do {
            _ = try await client.perform(.scheduleClear(mac: mac), confirm: "79217acbd9c66e9e1af7693324516b75")
            XCTFail("expected an error")
        } catch let e as APIError {
            XCTAssertEqual(e.code, "bad_param")
        }
        XCTAssertEqual(transport.requests.count, 0)
    }

    func testRevokeAllConfirmFlow() async throws {
        let transport = MockTransport()
        let client = makeClient(transport)
        transport.enqueue(428, SampleJSON.confirmRevokeAllWeb)
        transport.enqueue(200, SampleJSON.revokeAllResult)
        let first = try await client.perform(.revokeAll(web: true))
        guard case .confirm(let p) = first else {
            return XCTFail("expected a confirm")
        }
        XCTAssertEqual(p.danger, .critical)
        let second = try await client.perform(.revokeAll(web: true), confirm: p.confirm)
        guard case .done(let v) = second else {
            return XCTFail("expected done")
        }
        XCTAssertEqual(ActionOK(json: v).revoked, 7)
        XCTAssertEqual(bodyJSON(transport.requests[0]), .object(["web": .bool(true)]))
        XCTAssertEqual(bodyJSON(transport.requests[1]), .object(["web": .bool(true), "confirm": .string("518a7f2c40f50edf1a650e872fb6cb70")]))
        XCTAssertTrue(ActionAftermath.after(.revokeAll(web: true), result: v).logsOut)
    }

    func testRevokeOneNotFound() async throws {
        let transport = MockTransport()
        let client = makeClient(transport)
        transport.enqueue(404, SampleJSON.errNotFound)
        do {
            _ = try await client.perform(.revokeApp(id: "8df5a0cb8a35a59a"))
            XCTFail("expected an error")
        } catch let e as APIError {
            XCTAssertEqual(ActionErrorPolicy.message(for: .revokeApp(id: "8df5a0cb8a35a59a"), error: e), "Этого входа уже нет — список обновлён.")
            XCTAssertEqual(ActionErrorPolicy.rereads(for: .revokeApp(id: "8df5a0cb8a35a59a"), error: e), [.devices])
        }
    }

    func testSpeedtestJob() async throws {
        let transport = MockTransport()
        let clock = FakeClock(start: nowT)
        let client = makeClient(transport, clock: clock)
        transport.enqueue(202, SampleJSON.speedtestJobStart)
        transport.enqueue(200, #"{"state":"running","action":"speedtest"}"#)
        transport.enqueue(200, SampleJSON.speedtestJobDone)
        let started = try await client.perform(.speedtest(via: .vpn))
        guard case .job(let id, let every) = started else {
            return XCTFail("expected a job")
        }
        XCTAssertEqual(id, "34045d1894d672ac")
        let done = try await client.waitForJob(id: id, pollEvery: every)
        XCTAssertEqual(done.speed?.down, 90000000)
        XCTAssertEqual(bodyJSON(transport.requests[0]), .object(["via": .string("vpn")]))
        let after = ActionAftermath.after(.speedtest(via: .vpn), result: done.result)
        XCTAssertEqual(after.toast, "Тест через VPN: 90,0\u{00A0}Мбит/с загрузка, 40,0\u{00A0}Мбит/с отдача.")
        XCTAssertEqual(after.rereads, [ScheduledRead(.data, after: 5)])
        let s = try decodeJSON(RouterStatus.self, SampleJSON.statusStage4).applyingSuccess(of: .speedtest(via: .vpn), result: done.result)
        XCTAssertEqual(s.speed.vpn?.down, 90000000)
        XCTAssertEqual(s.speed.vpn?.ts, 1791899279)
    }

    func testSpeedtestJobRouterBusy() async throws {
        let transport = MockTransport()
        let clock = FakeClock(start: nowT)
        let client = makeClient(transport, clock: clock)
        transport.enqueue(200, SampleJSON.speedtestJobBusy)
        do {
            _ = try await client.waitForJob(id: "34045d1894d672ac", pollEvery: 3)
            XCTFail("expected an error")
        } catch let e as APIError {
            XCTAssertEqual(ActionErrorPolicy.message(for: .speedtest(via: .direct), error: e), "Тест скорости уже идёт — дождись результата.")
        }
    }

    func testReadsDecode() async throws {
        let transport = MockTransport()
        let client = makeClient(transport)
        transport.enqueue(200, SampleJSON.zapretOn)
        transport.enqueue(200, SampleJSON.tgwsOn)
        transport.enqueue(200, SampleJSON.mydirect)
        transport.enqueue(200, SampleJSON.vds)
        transport.enqueue(200, SampleJSON.accessList)
        transport.enqueue(500, SampleJSON.mydirectNoRule)
        let z = try await client.zapret()
        let t = try await client.tgws()
        let m = try await client.mydirect()
        let v = try await client.vds()
        let a = try await client.accessList()
        XCTAssertEqual(z.strategy, 2)
        XCTAssertEqual(t.redirected, 3412)
        XCTAssertEqual(m.added, ["kinopoisk.ru"])
        XCTAssertEqual(v.servers.count, 3)
        XCTAssertEqual(a.apps.count, 2)
        do {
            _ = try await client.mydirect()
            XCTFail("expected an error")
        } catch let e as APIError {
            XCTAssertEqual(e.code, "no rule")
            XCTAssertFalse(e.entersOfflineMode)
        }
        XCTAssertEqual(transport.requests.map { $0.url?.path ?? "" }, [
            "/router/app/v1/zapret", "/router/app/v1/tgws", "/router/app/v1/mydirect", "/router/app/v1/vds",
            "/router/app/v1/devices", "/router/app/v1/mydirect"
        ])
    }

    // MARK: - Aftermath

    func testAftermathSwitch() {
        let a = ActionAftermath.after(.switchServer(id: "Pz1Yc4Ue"), name: "🇳🇱 Нидерланды")
        XCTAssertEqual(a.quietWindow, 15)
        XCTAssertEqual(a.banner, "VPN переключается на «🇳🇱 Нидерланды»…")
        XCTAssertEqual(a.toast, "Подключаю «🇳🇱 Нидерланды». Статус обновится через 10 секунд.")
        XCTAssertEqual(a.rereadStatusAfter, 10)
        XCTAssertEqual(a.rereads, [ScheduledRead(.status, after: 10)])
        XCTAssertEqual(a.lockedFor, 15)
        XCTAssertEqual(a.disabledButtons, [.check, .restartVPN, .updateSubs, .reboot])
        XCTAssertTrue(a.locks(.diradd(domain: "a.ru"), elapsed: 5))
        XCTAssertTrue(a.locks(.restart, elapsed: 14.9))
        XCTAssertFalse(a.locks(.restart, elapsed: 15))
        XCTAssertFalse(a.locks(.block(mac: mac), elapsed: 1))
        XCTAssertEqual(ActionAftermath.after(.switchServer(id: "Pz1Yc4Ue")).toast, "Подключаю «Pz1Yc4Ue». Статус обновится через 10 секунд.")
        let d = ActionAftermath.after(.switchDirect)
        XCTAssertEqual(d.quietWindow, 15)
        XCTAssertEqual(d.banner, "VPN выключается — всё пойдёт напрямую…")
        XCTAssertEqual(d.toast, "Подключаю «Напрямую (без VPN)». Статус обновится через 10 секунд.")
    }

    func testAftermathOthers() throws {
        let sub = ActionAftermath.after(.subupdate(sid: "cfg7d8e9f"), name: "Reserve")
        XCTAssertEqual(sub.quietWindow, 0)
        XCTAssertNil(sub.banner)
        XCTAssertEqual(sub.toast, "«Reserve»: список серверов обновляется, около минуты.")
        XCTAssertEqual(sub.rereads, [ScheduledRead(.status, after: 45), ScheduledRead(.status, after: 90)])
        XCTAssertEqual(sub.lockedFor, 15)
        XCTAssertEqual(sub.disabledButtons, [.restartVPN, .updateSubs])
        XCTAssertEqual(ActionAftermath.after(.subupdateAll).toast, "Подписки обновляются — список серверов обновится через 1–2 минуты, потом VPN перезапустится на несколько секунд.")

        let block = ActionAftermath.after(.block(mac: mac), name: "Телевизор")
        XCTAssertEqual(block.toast, "Интернет для «Телевизор» выключен.")
        XCTAssertEqual(block.quietWindow, 0)
        XCTAssertEqual(block.rereads, [ScheduledRead(.status, after: 3)])
        XCTAssertTrue(block.lockedActions.isEmpty)
        XCTAssertEqual(ActionAftermath.after(.block(mac: "00:00:5E:00:53:03")).toast, "Интернет для «00:00:5e:00:53:03» выключен.")
        XCTAssertEqual(ActionAftermath.after(.unblock(mac: mac), name: "Телевизор").toast, "Интернет для «Телевизор» снова включён.")

        let direct = ActionAftermath.after(.direct(mac: mac, on: true), name: "Приставка")
        XCTAssertEqual(direct.quietWindow, 12)
        XCTAssertEqual(direct.banner, "VPN перезапускается…")
        XCTAssertEqual(direct.toast, "«Приставка» теперь мимо VPN.")
        XCTAssertEqual(direct.lockedFor, 15)
        XCTAssertEqual(direct.rereads, [ScheduledRead(.status, after: 12)])
        XCTAssertEqual(ActionAftermath.after(.direct(mac: mac, on: false), name: "Приставка").toast, "«Приставка» снова через VPN.")

        XCTAssertEqual(ActionAftermath.after(.schedule(mac: mac, off: "2300", on: "0700"), name: "Телевизор").toast, "«Телевизор»: без интернета с 23:00 до 07:00.")
        XCTAssertEqual(ActionAftermath.after(.scheduleClear(mac: mac), name: "Телевизор").toast, "Расписание «Телевизор» убрано.")

        let add = ActionAftermath.after(.diradd(domain: "ozon.ru"), result: .object(["ok": .bool(true)]))
        XCTAssertEqual(add.quietWindow, 12)
        XCTAssertEqual(add.toast, "ozon.ru теперь напрямую.")
        XCTAssertEqual(add.rereads, [ScheduledRead(.mydirect, after: 0)])
        let same = ActionAftermath.after(.diradd(domain: "ozon.ru"), result: try JSONValue.parse(SampleJSON.sameResult))
        XCTAssertEqual(same.quietWindow, 0)
        XCTAssertNil(same.banner)
        XCTAssertEqual(same.toast, "ozon.ru уже был в списке.")
        XCTAssertEqual(same.lockedFor, 15, "the server pause applies anyway")
        XCTAssertEqual(ActionAftermath.after(.dirdel(domain: "kinopoisk.ru")).toast, "kinopoisk.ru снова через VPN.")
        XCTAssertEqual(ActionAftermath.after(.dirdel(domain: "kinopoisk.ru"), result: try JSONValue.parse(SampleJSON.sameResult)).toast, "kinopoisk.ru уже не было в списке.")

        let svc = ActionAftermath.after(.svcdirect(name: "YouTube", on: true))
        XCTAssertEqual(svc.toast, "YouTube теперь напрямую.")
        XCTAssertEqual(svc.quietWindow, 12)
        XCTAssertEqual(svc.rereads, [ScheduledRead(.mydirect, after: 0), ScheduledRead(.status, after: 12)])
        XCTAssertEqual(ActionAftermath.after(.svcdirect(name: "Хайпиксель", on: false)).toast, "Хайпиксель снова через VPN.")

        let z = ActionAftermath.after(.zapretset(on: true))
        XCTAssertEqual(z.quietWindow, 15)
        XCTAssertEqual(z.banner, "Применяю… VPN перезапускается")
        XCTAssertEqual(z.toast, "Включаю zapret — около 10 секунд.")
        XCTAssertEqual(z.rereads, [ScheduledRead(.zapret, after: 1.5)])
        XCTAssertEqual(z.fastPoll, FastPoll(condition: .zapretBusy))
        XCTAssertEqual(ActionAftermath.after(.zapretset(on: false)).toast, "Выключаю zapret — около 10 секунд.")

        let strat = ActionAftermath.after(.zapretstrat(n: 2))
        XCTAssertNil(strat.toast)
        XCTAssertEqual(strat.rereads.map { $0.after }, [2, 4, 7])
        XCTAssertEqual(strat.verification, .zapretStrategy(2))
        XCTAssertTrue(strat.locks(.zapretstrat(n: 3), elapsed: 3))
        XCTAssertFalse(strat.locks(.zapretstrat(n: 3), elapsed: 7))

        let check = ActionAftermath.after(.zapretcheck)
        XCTAssertNil(check.toast)
        XCTAssertEqual(check.fastPoll?.condition, .zapretChecking)
        XCTAssertEqual(check.fastPoll?.every, 3)
        XCTAssertEqual(check.fastPoll?.maxDuration, 120)

        let tg = ActionAftermath.after(.tgwsset(on: true))
        XCTAssertEqual(tg.toast, "Прокси Telegram включается…")
        XCTAssertEqual(tg.rereads, [ScheduledRead(.tgws, after: 3), ScheduledRead(.tgws, after: 8)])
        XCTAssertEqual(tg.verification, .tgws(on: true))
        XCTAssertEqual(ActionAftermath.after(.tgwsset(on: false)).toast, "Прокси Telegram выключен.")

        XCTAssertEqual(ActionAftermath.after(.rename(mac: mac, name: "ТВ")).toast, "Имя сохранено.")
        XCTAssertNil(ActionAftermath.after(.pingone(id: "Wm6Tj2Gk")).toast)
        XCTAssertEqual(ActionAftermath.after(.revokeApp(id: "8df5a0cb8a35a59a"), name: "Второй iPhone").toast, "Доступ «Второй iPhone» отозван: приложение на телефоне вышло.")
        XCTAssertEqual(ActionAftermath.after(.revokeWeb(ref: "8207c706de3f72c7")).toast, "Сессия веб-панели закрыта.")
        XCTAssertEqual(ActionAftermath.after(.revokeWeb(ref: "8207c706de3f72c7")).rereads, [ScheduledRead(.devices, after: 0)])
        let all = ActionAftermath.after(.revokeAll(web: false))
        XCTAssertTrue(all.logsOut)
        XCTAssertEqual(all.toast, "Вы вышли на всех устройствах. Войти заново — пароль и число в Telegram.")

        let reboot = ActionAftermath.after(.reboot)
        XCTAssertTrue(reboot.locks(.block(mac: mac), elapsed: 100))
        XCTAssertFalse(reboot.locks(.rename(mac: mac, name: ""), elapsed: 100))

        let direct2 = ActionAftermath.after(.speedtest(via: .direct), result: .object(["via": .string("direct"), "down": .int(286000000), "up": .int(0), "up_limited": .bool(true)]))
        XCTAssertEqual(direct2.toast, "Тест напрямую: 286\u{00A0}Мбит/с загрузка.")
    }

    func testFastPoll() throws {
        let busy = try decodeJSON(ZapretState.self, SampleJSON.zapretBusy)
        let on = try decodeJSON(ZapretState.self, SampleJSON.zapretOn)
        let checking = try decodeJSON(ZapretState.self, SampleJSON.zapretOffChecking)
        let p = FastPoll(condition: .zapretBusy)
        XCTAssertTrue(p.shouldContinue(busy, elapsed: 10))
        XCTAssertFalse(p.shouldContinue(busy, elapsed: 120))
        XCTAssertFalse(p.shouldContinue(on, elapsed: 10))
        XCTAssertFalse(p.shouldContinue(nil, elapsed: 0))
        let c = FastPoll(condition: .zapretChecking)
        XCTAssertTrue(c.shouldContinue(checking, elapsed: 3))
        XCTAssertFalse(c.shouldContinue(busy, elapsed: 3))
    }

    func testReadTargets() {
        XCTAssertEqual(ReadTarget.status.defaultInterval, 30)
        XCTAssertEqual(ReadTarget.zapret.defaultInterval, 30)
        XCTAssertEqual(ReadTarget.tgws.defaultInterval, 60)
        XCTAssertEqual(ReadTarget.vds.defaultInterval, 300)
        XCTAssertNil(ReadTarget.mydirect.defaultInterval)
        XCTAssertNil(ReadTarget.devices.defaultInterval)
        XCTAssertTrue(ReadTarget.status.entersOfflineMode)
        XCTAssertFalse(ReadTarget.zapret.entersOfflineMode)
        XCTAssertTrue(ReadTarget.mydirect.needsRouter)
        XCTAssertFalse(ReadTarget.data.needsRouter)
        XCTAssertFalse(ReadTarget.devices.needsRouter)
    }

    // MARK: - Error policy

    func testErrorPolicy() {
        func http(_ status: Int, _ body: String) -> APIError {
            return APIError.fromHTTP(status: status, body: Data(body.utf8), headers: [:])
        }
        let routerBusy = http(409, SampleJSON.errRouterBusy)
        let serverBusy = http(409, #"{"error":"busy","message":"Другое действие ещё выполняется — подожди немного."}"#)
        XCTAssertTrue(ActionErrorPolicy.treatsAsStarted(.zapretcheck, error: routerBusy))
        XCTAssertNil(ActionErrorPolicy.message(for: .zapretcheck, error: routerBusy))
        XCTAssertFalse(ActionErrorPolicy.treatsAsStarted(.zapretcheck, error: serverBusy))
        XCTAssertEqual(ActionErrorPolicy.message(for: .zapretcheck, error: serverBusy), "Другое действие ещё выполняется — подожди немного.")
        XCTAssertEqual(ActionErrorPolicy.message(for: .zapretset(on: true), error: routerBusy), "zapret сейчас занят другим действием — повтори через несколько секунд.")
        XCTAssertEqual(ActionErrorPolicy.message(for: .zapretset(on: true), error: serverBusy), "Другое действие ещё выполняется — подожди немного.")
        XCTAssertEqual(ActionErrorPolicy.message(for: .speedtest(via: .vpn), error: http(409, #"{"error":"busy","message":"Тест скорости или проверка уже идут — дождись результата."}"#)), "Тест скорости или проверка уже идут — дождись результата.")

        let noRule = http(500, SampleJSON.errNoRule)
        XCTAssertEqual(ActionErrorPolicy.message(for: .diradd(domain: "ozon.ru"), error: noRule), "В PassWall нет правила MyDirect. Проверь правило MyDirect в LuCI.")
        XCTAssertEqual(ActionErrorPolicy.rereads(for: .diradd(domain: "ozon.ru"), error: noRule), [.mydirect])
        XCTAssertEqual(ActionErrorPolicy.rereads(for: .switchServer(id: "Hd3Fs9Qa"), error: http(400, SampleJSON.errBadNode)), [.status])
        XCTAssertEqual(ActionErrorPolicy.rereads(for: .svcdirect(name: "x", on: true), error: http(400, SampleJSON.errNoTarget)), [.status])
        XCTAssertEqual(ActionErrorPolicy.rereads(for: .subupdate(sid: "x"), error: http(400, #"{"error":"bad sub","source":"router"}"#)), [.status])
        XCTAssertEqual(ActionErrorPolicy.rereads(for: .dirdel(domain: "sberbank.ru"), error: http(400, SampleJSON.errDirdelNotAdded)), [.mydirect])
        XCTAssertEqual(ActionErrorPolicy.rereads(for: .tgwsset(on: true), error: http(503, SampleJSON.errNotInstalled)), [.tgws])
        XCTAssertEqual(ActionErrorPolicy.rereads(for: .zapretstrat(n: 2), error: http(503, SampleJSON.errNotInstalled)), [.zapret])
        XCTAssertEqual(ActionErrorPolicy.rereads(for: .block(mac: mac), error: http(500, SampleJSON.errNft)), [])
        XCTAssertEqual(ActionErrorPolicy.rereads(for: .dirdel(domain: "a.ru"), error: APIError.client(code: "bad_param", message: nil)), [], "a local refusal re-reads nothing")
        let timeout = http(504, #"{"error":"router_timeout","message":"Роутер не ответил вовремя."}"#)
        XCTAssertEqual(ActionErrorPolicy.message(for: .block(mac: mac), error: timeout), "Роутер не ответил вовремя. Действие могло выполниться — проверь состояние через минуту.")
        XCTAssertNil(ActionErrorPolicy.message(for: .block(mac: mac), error: APIError(kind: .cancelled)))
    }

    // MARK: - Local patches

    func testStatusPatches() throws {
        let s = try decodeJSON(RouterStatus.self, SampleJSON.statusStage4)
        XCTAssertEqual(s.applyingSuccess(of: .switchServer(id: "Pz1Yc4Ue")).current, "Pz1Yc4Ue")
        XCTAssertEqual(s.applyingSuccess(of: .switchDirect).current, "_direct")
        let p = s.applyingSuccess(of: .pingone(id: "Wm6Tj2Gk"), result: try JSONValue.parse(SampleJSON.pingOneResult))
        XCTAssertEqual(p.ping?.nodes.first(where: { $0.id == "Wm6Tj2Gk" })?.ms, 7)
        XCTAssertEqual(s.applyingSuccess(of: .pingone(id: "Wm6Tj2Gk")), s, "no result → no change")
        let b = s.applyingSuccess(of: .block(mac: "00:00:5E:00:53:03"), result: try JSONValue.parse(SampleJSON.blockResult))
        XCTAssertEqual(b.devices.first(where: { $0.mac == mac })?.blocked, true)
        let u = b.applyingSuccess(of: .unblock(mac: mac), result: try JSONValue.parse(SampleJSON.unblockResult))
        XCTAssertEqual(u.devices.first(where: { $0.mac == mac })?.blocked, false)
        XCTAssertEqual(s.applyingSuccess(of: .direct(mac: mac, on: true)).devices.first(where: { $0.mac == mac })?.direct, true)
        XCTAssertEqual(s.applyingSuccess(of: .schedule(mac: "00:00:5e:00:53:02", off: "2200", on: "0600")).devices.first(where: { $0.mac == "00:00:5e:00:53:02" })?.sched, "2200-0600")
        XCTAssertNil(s.applyingSuccess(of: .scheduleClear(mac: mac)).devices.first(where: { $0.mac == mac })?.sched)
        XCTAssertEqual(s.applyingSuccess(of: .svcdirect(name: "YouTube", on: true)).svcDirect, ["Хайпиксель", "YouTube"])
        XCTAssertEqual(s.applyingSuccess(of: .svcdirect(name: "Хайпиксель", on: false)).svcDirect, [])
        XCTAssertEqual(s.applyingSuccess(of: .restart), s)
    }

    func testMyDirectAndZapretPatches() throws {
        let m = try decodeJSON(MyDirectList.self, SampleJSON.mydirect)
        let added = m.applyingSuccess(of: .diradd(domain: "ozon.ru"))
        XCTAssertEqual(added.added, ["kinopoisk.ru", "ozon.ru"])
        XCTAssertTrue(added.domains.contains("ozon.ru"))
        let removed = m.applyingSuccess(of: .dirdel(domain: "kinopoisk.ru"))
        XCTAssertEqual(removed.added, [])
        XCTAssertFalse(removed.domains.contains("kinopoisk.ru"))
        let z = try decodeJSON(ZapretState.self, SampleJSON.zapretOn)
        XCTAssertTrue(z.applyingSuccess(of: .zapretset(on: false)).busy)
        XCTAssertTrue(z.applyingSuccess(of: .zapretcheck).checking)
        XCTAssertEqual(z.applyingSuccess(of: .zapretstrat(n: 1)), z)
    }
}
