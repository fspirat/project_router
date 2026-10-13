import Foundation
import XCTest
@testable import RouterCore

final class DecodingTests: XCTestCase {

    func testStatusNormal() throws {
        let s = try decodeJSON(RouterStatus.self, SampleJSON.statusNormal)
        XCTAssertTrue(s.running)
        XCTAssertTrue(s.splitActive)
        XCTAssertEqual(s.current, "Kq7Lm2Xp")
        let p = try XCTUnwrap(s.ping)
        XCTAssertEqual(p.updated, 1791886200)
        XCTAssertEqual(p.socks, true)
        XCTAssertEqual(p.real, 48)
        XCTAssertEqual(p.nodes.count, 5)
        XCTAssertEqual(p.nodes[0].name, "fspiratNL")
        XCTAssertTrue(p.nodes[0].own)
        XCTAssertEqual(p.nodes[1].ms, 0)
        XCTAssertFalse(p.nodes[2].own)
        XCTAssertEqual(p.nodes[2].group, "nosok")
        XCTAssertEqual(s.log.count, 2)
        XCTAssertEqual(s.history, [DataPoint(ts: 1791885900, ms: 52), DataPoint(ts: 1791886200, ms: 48)])
        XCTAssertEqual(s.targets?.list.count, 3)
        XCTAssertEqual(s.targets?.list[1].name, "Discord")
        XCTAssertEqual(s.targets?.list[1].vpn, 0)
        XCTAssertEqual(s.sub?.down, 40802189312)
        XCTAssertEqual(s.sub?.total, 214748364800)
        XCTAssertEqual(s.sub?.expire, 1793404800)
        XCTAssertEqual(s.subs?.count, 1)
        XCTAssertEqual(s.subs?.first?.hwid, true)
        XCTAssertEqual(s.subs?.first?.nodes, 14)
        XCTAssertEqual(s.targetList.count, 3)
        XCTAssertEqual(s.svc.count, 3)
        XCTAssertEqual(s.svc["direct"]?.base, 9)
        XCTAssertEqual(s.svc["Hd3Fs9Qa"]?.list.first?.vpn, 88)
        XCTAssertFalse(s.svcRunning)
        XCTAssertEqual(s.speed.vpn?.down, 91234567)
        XCTAssertEqual(s.speed.vpn?.country, "NL")
        XCTAssertEqual(s.speed.vpn?.upLimited, false)
        XCTAssertNil(s.speed.direct)
        XCTAssertEqual(s.devices.count, 4)
        XCTAssertEqual(s.devices[0].band, "5g")
        XCTAssertEqual(s.devices[0].signal, -51)
        XCTAssertEqual(s.devices[0].rate, 866)
        XCTAssertTrue(s.devices[0].isRandomizedMAC)
        XCTAssertEqual(s.devices[1].band, "wired")
        XCTAssertTrue(s.devices[1].direct)
        XCTAssertFalse(s.devices[1].isRandomizedMAC)
        XCTAssertEqual(s.devices[2].sched, "2300-0700")
        XCTAssertNil(s.devices[3].band)
        XCTAssertTrue(s.devices[3].blocked)
        XCTAssertFalse(s.devices[3].online)
        XCTAssertEqual(s.sys.cpu, 7)
        XCTAssertEqual(s.sys.load, "0.21 0.17 0.15")
        XCTAssertEqual(s.sys.memTotal, 245632)
        XCTAssertNil(s.sys.temp)
        XCTAssertEqual(s.sys.uptime, 352812)
        XCTAssertEqual(s.sys.net.rx, 18734216)
        XCTAssertEqual(s.sys.net.rxTotal, 96385412736)
    }

    func testStatusAfterReboot() throws {
        let s = try decodeJSON(RouterStatus.self, SampleJSON.statusAfterReboot)
        XCTAssertNil(s.ping)
        XCTAssertNil(s.targets)
        XCTAssertNil(s.sub)
        XCTAssertEqual(s.log, [])
        XCTAssertEqual(s.history, [])
        XCTAssertEqual(s.targetList, [])
        XCTAssertTrue(s.svc.isEmpty)
        XCTAssertNil(s.speed.vpn)
        XCTAssertNil(s.speed.direct)
        XCTAssertNil(s.sys.temp)
        let item = try XCTUnwrap(s.subs?.first)
        XCTAssertEqual(item.name, "nosok")
        XCTAssertNil(item.expire)
        XCTAssertNil(item.ts)
        XCTAssertNil(item.down)
        XCTAssertEqual(s.sys.uptime, 95)
    }

    func testSubsNullAndEmpty() throws {
        let nullSubs = SampleJSON.statusAfterReboot.replacingOccurrences(
            of: #""subs":[{"id":"cfg5a1b2c","name":"nosok","host":"sub.example.net","hwid":true,"nodes":14}]"#,
            with: #""subs":null"#
        )
        XCTAssertNotEqual(nullSubs, SampleJSON.statusAfterReboot)
        let a = try decodeJSON(RouterStatus.self, nullSubs)
        XCTAssertNil(a.subs)
        let b = try decodeJSON(RouterStatus.self, SampleJSON.statusDirectMode)
        XCTAssertEqual(b.subs, [])
        XCTAssertNil(b.sub)
    }

    func testDirectMode() throws {
        let s = try decodeJSON(RouterStatus.self, SampleJSON.statusDirectMode)
        XCTAssertEqual(s.current, "_direct")
        XCTAssertEqual(s.ping?.current, "_direct")
        XCTAssertEqual(s.sys.temp, 51)
        XCTAssertEqual(s.sys.model, "")
        XCTAssertEqual(s.svc["direct"]?.list, [])
        XCTAssertEqual(s.devices, [])
    }

    func testSplitInactiveAndSocksFalse() throws {
        let text = SampleJSON.statusNormal
            .replacingOccurrences(of: #""split_active":true"#, with: #""split_active":false"#)
            .replacingOccurrences(of: #""socks":true,"real":48"#, with: #""socks":false,"real":null"#)
        let s = try decodeJSON(RouterStatus.self, text)
        XCTAssertFalse(s.splitActive)
        XCTAssertEqual(s.ping?.socks, false)
        XCTAssertNil(s.ping?.real)
    }

    func testNumbersAsStringsAndFractionsAreTolerated() throws {
        let text = """
        {"running":"1","split_active":true,"current":"X","ping":{"updated":"1791886200","socks":1,"real":"48.6","nodes":[{"id":"X","name":"  🇩🇪 Германия ","ms":"57"},7,null,{"id":"Y","ms":12.5}]},\
        "log":"nope","history":[[1,2],"bad",[3],[4,5.4]],"targets":"oops","sub":[],"subs":{},"svc":[],"speed":null,\
        "devices":[{"name":"a","mac":"AA:BB:CC:00:00:01","online":true,"up":"100","dn":2.5e3},"broken",{"name":5}],\
        "sys":{"cpu":"12","cores":2,"load":0.5,"mem_total":"1000","mem_avail":500,"temp":"48","uptime":3600.4,"net":{"rx":"8000"}}}
        """
        let s = try decodeJSON(RouterStatus.self, text)
        XCTAssertTrue(s.running)
        XCTAssertEqual(s.ping?.updated, 1791886200)
        XCTAssertEqual(s.ping?.socks, true)
        XCTAssertEqual(s.ping?.real, 49)
        XCTAssertEqual(s.ping?.nodes.count, 2)
        XCTAssertEqual(s.ping?.nodes.first?.name, "🇩🇪 Германия")
        XCTAssertEqual(s.ping?.nodes.first?.ms, 57)
        XCTAssertEqual(s.ping?.nodes.last?.ms, 13)
        XCTAssertEqual(s.log, [])
        XCTAssertEqual(s.history, [DataPoint(ts: 1, ms: 2), DataPoint(ts: 4, ms: 5)])
        XCTAssertNil(s.targets)
        XCTAssertNil(s.sub)
        XCTAssertNil(s.subs)
        XCTAssertTrue(s.svc.isEmpty)
        XCTAssertNil(s.speed.vpn)
        XCTAssertEqual(s.devices.count, 2)
        XCTAssertEqual(s.devices[0].mac, "aa:bb:cc:00:00:01")
        XCTAssertEqual(s.devices[0].up, 100)
        XCTAssertEqual(s.devices[0].dn, 2500)
        XCTAssertEqual(s.devices[1].name, "5")
        XCTAssertEqual(s.sys.cpu, 12)
        XCTAssertEqual(s.sys.load, "0.5")
        XCTAssertEqual(s.sys.memTotal, 1000)
        XCTAssertEqual(s.sys.temp, 48)
        XCTAssertEqual(s.sys.uptime, 3600)
        XCTAssertEqual(s.sys.net.rx, 8000)
        XCTAssertEqual(s.sys.net.dev, "")
    }

    func testStatusMustBeAnObject() {
        XCTAssertThrowsError(try decodeJSON(RouterStatus.self, "[]"))
        XCTAssertThrowsError(try decodeJSON(RouterStatus.self, "<html>captive</html>"))
    }

    func testVPNFailingFixture() throws {
        let s = try decodeJSON(RouterStatus.self, SampleJSON.statusVPNFailing)
        XCTAssertEqual(s.ping?.real, 0)
        XCTAssertEqual(s.ping?.socks, true)
        XCTAssertEqual(s.ping?.nodes.count, 2)
    }

    func testNet() throws {
        let n = try decodeJSON(NetStats.self, SampleJSON.net)
        XCTAssertEqual(n.dev, "wan")
        XCTAssertEqual(n.rx, 18734216)
        XCTAssertEqual(n.tx, 1203448)
        XCTAssertEqual(n.rxTotal, 96385412736)
        XCTAssertEqual(n.txTotal, 7346121904)
    }

    func testLed() throws {
        let on = try decodeJSON(LedState.self, SampleJSON.ledOn)
        XCTAssertTrue(on.isAvailable)
        XCTAssertTrue(on.on)
        XCTAssertEqual(on.items.count, 4)
        XCTAssertEqual(on.items[1].name, "yellow:status")
        XCTAssertFalse(on.items[1].on)

        let absent = try decodeJSON(LedState.self, SampleJSON.ledAbsent)
        XCTAssertFalse(absent.isAvailable)
        XCTAssertTrue(absent.items.isEmpty)

        let off = try decodeJSON(LedState.self, SampleJSON.ledsetOff)
        XCTAssertTrue(off.isAvailable)
        XCTAssertFalse(off.on)
    }

    func testDataDay() throws {
        let d = try decodeJSON(DataResponse.self, SampleJSON.dataDay)
        XCTAssertEqual(d.now, 1791886560)
        XCTAssertEqual(d.range, "day")
        XCTAssertEqual(d.points.count, 4)
        XCTAssertEqual(d.points[2], DataPoint(ts: 1791886440, ms: -1))
        XCTAssertEqual(d.stats.avg, 50)
        XCTAssertEqual(d.stats.fails, 1)
        XCTAssertEqual(d.stats.offlineMin, 1)
        XCTAssertEqual(d.events.count, 6)
        XCTAssertEqual(d.events[0].kind, "manual")
        XCTAssertEqual(d.events[2].level, .warn)
        XCTAssertEqual(d.events[4].level, .err)
        XCTAssertNil(d.offlineSince)
        XCTAssertEqual(d.lastOK, 1791886530)
        XCTAssertEqual(d.names["5a:00:5e:00:53:01"], "iPhone владельца")
        XCTAssertEqual(d.tpoints["Discord"], [DataPoint(ts: 1791886205, ms: 0)])
        XCTAssertEqual(d.traffic["5a:00:5e:00:53:01"], TrafficEntry(dayUp: 52428800, dayDown: 1610612736, monthUp: 734003200, monthDown: 28991029248))
        XCTAssertEqual(d.speed.count, 2)
        XCTAssertEqual(d.speed[0].via, "direct")
        XCTAssertEqual(d.speed[1].down, 91234567)
        XCTAssertEqual(d.site.luci, "https://router.fspirat.xyz/")
        XCTAssertEqual(d.site.bot, "FSRouter_bot")
        XCTAssertEqual(d.site.panels, ["fspirat.xyz"])
        XCTAssertEqual(d.newdevs.count, 1)
        XCTAssertEqual(d.newdevs[0].mac, "00:00:5e:00:53:02")
    }

    func testDataEmptyAndOffline() throws {
        let e = try decodeJSON(DataResponse.self, SampleJSON.dataDayEmpty)
        XCTAssertEqual(e.points, [])
        XCTAssertNil(e.stats.avg)
        XCTAssertNil(e.stats.min)
        XCTAssertNil(e.stats.max)
        XCTAssertEqual(e.events, [])
        XCTAssertTrue(e.names.isEmpty)
        XCTAssertTrue(e.traffic.isEmpty)
        XCTAssertEqual(e.site.luci, "")

        let o = try decodeJSON(DataResponse.self, SampleJSON.dataDayOffline)
        XCTAssertEqual(o.offlineSince, 1791885840)
        XCTAssertEqual(o.lastOK, 1791885780)
        XCTAssertEqual(o.points.last?.ms, -1)
    }

    func testDataWeekPoints() throws {
        let text = #"{"now":100,"range":"week","step":1800,"points":[[10,55,2,0],[20,0,5,0],[30,-1,0,30]],"stats":{"avg":55,"min":40,"max":70,"fails":7,"offline_min":30},"events":[],"names":{},"tpoints":{},"traffic":{},"speed":[],"site":{},"newdevs":[]}"#
        let d = try decodeJSON(DataResponse.self, text)
        XCTAssertEqual(d.step, 1800)
        XCTAssertEqual(d.points[0], DataPoint(ts: 10, ms: 55, fails: 2, offline: 0))
        XCTAssertEqual(d.points[2].offline, 30)
    }

    func testMe() throws {
        let me = try decodeJSON(MeResponse.self, SampleJSON.me)
        XCTAssertEqual(me.device.id, "49139e3a1db5a6ac")
        XCTAssertEqual(me.device.name, "iPhone владельца")
        XCTAssertEqual(me.device.expires, 1799662560)
        XCTAssertEqual(me.device.hardExpires, 1823422560)
        XCTAssertEqual(me.now, 1791886560)
    }

    func testAuthBodies() throws {
        let c = try decodeJSON(LoginChallenge.self, SampleJSON.loginStart)
        XCTAssertEqual(c.number, 24)
        XCTAssertEqual(c.expiresIn, 120)
        XCTAssertEqual(c.pollEvery, 2)
        XCTAssertEqual(c.loginID.count, 64)

        let pending = try decodeJSON(PollResult.self, SampleJSON.pollPending)
        XCTAssertEqual(pending, .pending(expiresIn: 118))

        let approved = try decodeJSON(PollResult.self, SampleJSON.pollApproved)
        guard case .approved(let a) = approved else {
            return XCTFail("expected approved")
        }
        XCTAssertTrue(Validation.isValidToken(a.token))
        XCTAssertEqual(a.deviceID, "49139e3a1db5a6ac")
        XCTAssertEqual(a.expires, 1799662560)
        XCTAssertEqual(a.hardExpires, 1823422560)

        XCTAssertThrowsError(try decodeJSON(PollResult.self, #"{"state":"approved","token":"bearer x"}"#))
        XCTAssertThrowsError(try decodeJSON(PollResult.self, #"{"state":"weird"}"#))
        XCTAssertThrowsError(try decodeJSON(LoginChallenge.self, #"{"number":24}"#))

        let cancel = try decodeJSON(CancelResult.self, SampleJSON.cancelOK)
        XCTAssertTrue(cancel.ok)
        XCTAssertEqual(cancel.state, "cancelled")
    }

    func testConfirmPrompts() throws {
        let r = try decodeJSON(ConfirmPrompt.self, SampleJSON.confirmRestart)
        XCTAssertEqual(r.confirm, "79217acbd9c66e9e1af7693324516b75")
        XCTAssertEqual(r.expiresIn, 60)
        XCTAssertEqual(r.danger, .high)
        XCTAssertEqual(r.title, "Перезапустить VPN?")
        XCTAssertEqual(r.text, "Связь через VPN пропадёт на несколько секунд.")
        XCTAssertEqual(r.button, "Перезапустить")
        XCTAssertFalse(r.isDestructive)
        XCTAssertFalse(r.requiresBiometrics)

        let b = try decodeJSON(ConfirmPrompt.self, SampleJSON.confirmReboot)
        XCTAssertEqual(b.danger, .critical)
        XCTAssertTrue(b.isDestructive)
        XCTAssertTrue(b.requiresBiometrics)
        XCTAssertEqual(b.button, "Перезагрузить")

        let u = try decodeJSON(ConfirmPrompt.self, SampleJSON.confirmUpdate)
        XCTAssertEqual(u.title, "Обновить подписки VPN?")
        XCTAssertEqual(u.danger, .high)

        XCTAssertEqual(Danger(serverValue: "medium"), .medium)
        XCTAssertEqual(Danger(serverValue: "???"), .critical)
    }

    func testJobBodies() throws {
        let start = try decodeJSON(JobStart.self, SampleJSON.jobStart)
        XCTAssertEqual(start.job, "fbe9f93b0caf8a91")
        XCTAssertEqual(start.pollEvery, 3)

        XCTAssertEqual(try decodeJSON(JobStatus.self, SampleJSON.jobRunning), .running(action: "ping"))

        let done = try decodeJSON(JobStatus.self, SampleJSON.jobDone)
        guard case .done(let d) = done else {
            return XCTFail("expected done")
        }
        XCTAssertEqual(d.http, 200)
        XCTAssertEqual(d.status?.current, "Kq7Lm2Xp")
        XCTAssertEqual(d.status, try decodeJSON(RouterStatus.self, SampleJSON.statusNormal))

        let failed = try decodeJSON(JobStatus.self, SampleJSON.jobErrorOffline)
        guard case .failed(let action, let e) = failed else {
            return XCTFail("expected failed")
        }
        XCTAssertEqual(action, "ping")
        XCTAssertEqual(e.status, 502)
        XCTAssertEqual(e.code, "router_offline")
        XCTAssertTrue(e.entersOfflineMode)
        XCTAssertEqual(e.userMessage, "Роутер не на связи: туннель до сервера оборван или дома нет интернета.")
    }

    func testJSONValueRoundTrip() throws {
        let v = try JSONValue.parse(#"{"a":1,"b":[true,null,"x",1.5],"c":{"d":96385412736}}"#)
        XCTAssertEqual(v["a"], .int(1))
        XCTAssertEqual(v["b"]?[0], .bool(true))
        XCTAssertEqual(v["b"]?[1], .null)
        XCTAssertEqual(v["b"]?[3], .double(1.5))
        XCTAssertEqual(v["c"]?["d"]?.intValue, 96385412736)
        let again = try JSONValue.parse(try JSONEncoder().encode(v))
        XCTAssertEqual(again, v)
        let led = try JSONValue.parse(SampleJSON.ledOn).decode(LedState.self)
        XCTAssertTrue(led.on)
    }
}
