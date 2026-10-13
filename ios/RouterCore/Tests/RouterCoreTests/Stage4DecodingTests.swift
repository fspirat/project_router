import Foundation
import XCTest
@testable import RouterCore

/// Decoding of every stage 4 fixture (contract-stage4 §2, §10).
final class Stage4DecodingTests: XCTestCase {

    func testStatusStage4() throws {
        let s = try decodeJSON(RouterStatus.self, SampleJSON.statusStage4)
        XCTAssertEqual(s.current, "Kq7Lm2Xp")
        let nodes = try XCTUnwrap(s.ping?.nodes)
        XCTAssertEqual(nodes.count, 7)
        XCTAssertEqual(nodes[3].name, "🇳🇱 Нидерланды", "stray spaces are trimmed")
        XCTAssertEqual(nodes[5].group, "Reserve")
        XCTAssertEqual(s.svcDirect, ["Хайпиксель"])
        XCTAssertEqual(s.targetList.count, 4)
        XCTAssertEqual(s.svc["Pz1Yc4Ue"]?.list.map { $0.vpn }, [38, 71, 0, 97])
        XCTAssertEqual(s.svc["direct"]?.base, 9)
        XCTAssertEqual(s.subs?.count, 2)
        XCTAssertNil(s.subs?[1].expire)
        XCTAssertEqual(s.speed.direct?.upLimited, true)
        XCTAssertEqual(s.speed.direct?.up, 0)
        XCTAssertEqual(s.devices.count, 6)
        XCTAssertEqual(s.devices[3].sblocked, true)
        XCTAssertEqual(s.devices[3].sched, "1300-1500")
        XCTAssertEqual(s.devices[4].blocked, true)
        XCTAssertNil(s.devices[4].band)
        XCTAssertEqual(s.log.count, 4)
    }

    func testDataWeekPointsAreBuckets() throws {
        let d = try decodeJSON(DataResponse.self, SampleJSON.dataWeek)
        XCTAssertEqual(d.dataRange, .week)
        XCTAssertEqual(d.step, 1800)
        XCTAssertEqual(d.points.count, 8)
        XCTAssertEqual(d.points[1], DataPoint(ts: 1791875700, ms: 49, fails: 1, offline: 0))
        XCTAssertEqual(d.points[3], DataPoint(ts: 1791879300, ms: -1, fails: 0, offline: 30))
        XCTAssertTrue(d.points.allSatisfy { $0.isBucket })
        XCTAssertEqual(d.stats.offlineMin, 32)
        XCTAssertEqual(d.events.count, 7)
        XCTAssertEqual(d.names, ["5a:00:5e:00:53:01": "iPhone владельца"])
        XCTAssertEqual(d.tpoints["YouTube"]?.count, 3)
        XCTAssertEqual(d.traffic["00:00:5e:00:53:02"]?.dayDown, 10485760)
        XCTAssertEqual(d.traffic["5a:00:5e:00:53:01"]?.monthDown, 28991029248)
        XCTAssertEqual(d.speed.count, 2)
        XCTAssertEqual(d.speed[0].via, "direct")
        XCTAssertEqual(d.newdevs, [NewDevice(json: .object(["ts": .int(1791700000), "mac": .string("00:00:5e:00:53:02")]))])
        XCTAssertEqual(d.site.bot, "FSRouter_bot")
    }

    func testDayPointsAreNotBuckets() throws {
        let d = try decodeJSON(DataResponse.self, SampleJSON.dataDay)
        XCTAssertEqual(d.dataRange, .day)
        XCTAssertFalse(d.points.isEmpty)
        XCTAssertTrue(d.points.allSatisfy { !$0.isBucket })
    }

    func testDataMonthAndObserved() throws {
        let m = try decodeJSON(DataResponse.self, SampleJSON.dataMonth)
        XCTAssertEqual(m.dataRange, .month)
        XCTAssertEqual(m.step, 7200)
        XCTAssertEqual(m.points.last?.ts, 1791889200)
        XCTAssertGreaterThan(m.points.last?.ts ?? 0, m.now, "the current bucket mid may be after now")
        let o = try decodeJSON(DataResponse.self, SampleJSON.dataWeekObserved)
        XCTAssertEqual(o.points.count, 2, "the «…» element is skipped")
        XCTAssertEqual(o.newdevs.first?.mac, "00:00:5e:00:53:02")
        XCTAssertEqual(o.events.first?.text, "Сервер выбран вручную: _direct")
    }

    func testDataRangeHelpers() {
        XCTAssertEqual(DataRange.day.span, 86400)
        XCTAssertEqual(DataRange.week.span, 604800)
        XCTAssertEqual(DataRange.month.span, 2592000)
        XCTAssertEqual(DataRange.week.step, 1800)
        XCTAssertEqual(DataRange.month.step, 7200)
        XCTAssertEqual(DataRange.day.shortLabel, "24\u{00A0}ч")
        XCTAssertEqual(DataRange.week.shortLabel, "7\u{00A0}дн")
        XCTAssertEqual(DataRange.month.title, "30\u{00A0}дней")
        XCTAssertEqual(DataRange.day.title, "24\u{00A0}часа")
    }

    func testZapret() throws {
        let on = try decodeJSON(ZapretState.self, SampleJSON.zapretOn)
        XCTAssertFalse(on.absent)
        XCTAssertTrue(on.installed && on.enabled && on.isWorking)
        XCTAssertEqual(on.strategy, 2)
        XCTAssertEqual(on.pktsTCP, 18234)
        XCTAssertEqual(on.pktsUDP, 5120)
        XCTAssertEqual(on.vpnExcluded, 1)
        XCTAssertEqual(on.version, "v72.5")
        let c = try XCTUnwrap(on.check)
        XCTAssertEqual(c.via, "isp")
        XCTAssertEqual(c.ts, 1791886000)
        XCTAssertEqual(c.list.count, 4)
        XCTAssertEqual(c.list[3].name, "Discord CDN")
        XCTAssertFalse(c.list[3].ok)
        XCTAssertEqual(c.list[3].code, "000")
        XCTAssertEqual(c.list[0].queued, 6)

        let fb = try decodeJSON(ZapretState.self, SampleJSON.zapretFallback)
        XCTAssertTrue(fb.fallback)
        XCTAssertEqual(fb.check?.error, "xray")
        XCTAssertEqual(fb.check?.list, [])

        let absent = try decodeJSON(ZapretState.self, SampleJSON.zapretAbsent)
        XCTAssertTrue(absent.absent)
        XCTAssertFalse(absent.installed)
        XCTAssertEqual(absent.strategy, 3)
        XCTAssertNil(absent.check)

        XCTAssertTrue(try decodeJSON(ZapretState.self, SampleJSON.zapretBusy).busy)
        XCTAssertTrue(try decodeJSON(ZapretState.self, SampleJSON.zapretOffChecking).checking)
        XCTAssertFalse(try decodeJSON(ZapretState.self, SampleJSON.zapretNotInstalled).installed)
        XCTAssertFalse(try decodeJSON(ZapretState.self, SampleJSON.zapretPartial).routeLive)
    }

    func testTgws() throws {
        let on = try decodeJSON(TgwsState.self, SampleJSON.tgwsOn)
        XCTAssertTrue(on.installed && on.auto && on.enabled && on.running && on.listening)
        XCTAssertEqual(on.redirected, 3412)
        XCTAssertEqual(on.host, "192.168.1.1")
        XCTAssertEqual(on.port, 1443)
        XCTAssertEqual(on.version, "1.1.3")
        let absent = try decodeJSON(TgwsState.self, SampleJSON.tgwsAbsent)
        XCTAssertTrue(absent.absent)
        XCTAssertFalse(try decodeJSON(TgwsState.self, SampleJSON.tgwsOff).enabled)
        XCTAssertFalse(try decodeJSON(TgwsState.self, SampleJSON.tgwsStarting).listening)
    }

    func testMyDirectAndNoRule() throws {
        let m = try decodeJSON(MyDirectList.self, SampleJSON.mydirect)
        XCTAssertEqual(m.domains.count, 5)
        XCTAssertEqual(m.added, ["kinopoisk.ru"])
        let e = APIError.fromHTTP(status: 500, body: Data(SampleJSON.mydirectNoRule.utf8), headers: [:])
        XCTAssertEqual(e.code, "no rule")
        XCTAssertEqual(e.source, "router")
        XCTAssertEqual(e.userMessage, "В PassWall нет правила MyDirect.")
    }

    func testVds() throws {
        let v = try decodeJSON(VdsResponse.self, SampleJSON.vds)
        XCTAssertEqual(v.ts, 1791886440)
        XCTAssertEqual(v.servers.count, 3)
        XCTAssertTrue(v.servers[0].local)
        XCTAssertEqual(v.servers[0].stat?.memTotal, 2014084)
        XCTAssertEqual(v.servers[0].stat?.load, "0.08 0.05 0.01")
        XCTAssertEqual(v.servers[0].stat?.xray, "active")
        XCTAssertNil(v.servers[1].stat)
        XCTAssertFalse(v.servers[1].local)
        XCTAssertEqual(v.servers[2].stat?.disk, "81%")
        let empty = try decodeJSON(VdsResponse.self, SampleJSON.vdsEmpty)
        XCTAssertNil(empty.ts)
        XCTAssertEqual(empty.servers, [])
        XCTAssertEqual(try decodeJSON(VdsResponse.self, SampleJSON.vdsObserved).servers.count, 3)
    }

    func testAccessList() throws {
        let a = try decodeJSON(AccessList.self, SampleJSON.accessList)
        XCTAssertEqual(a.apps.count, 2)
        XCTAssertTrue(a.apps[0].current)
        XCTAssertEqual(a.apps[0].lastIP, "203.0.113.50")
        XCTAssertEqual(a.apps[1].os, "18.1")
        XCTAssertEqual(a.apps[1].hardExpires, 1821536000)
        XCTAssertEqual(a.web.count, 1)
        XCTAssertEqual(a.web[0].ref, "8207c706de3f72c7")
        XCTAssertFalse(a.web[0].current)
        XCTAssertEqual(a.logins.map { $0.result }, ["issued", "denied"])
        XCTAssertEqual(a.authLog.count, 6)
        XCTAssertEqual(a.authLog[0].what, "APP_OK")
        let o = try decodeJSON(AccessList.self, SampleJSON.accessListObserved)
        XCTAssertEqual(o.logins, [])
        XCTAssertEqual(o.apps[1].app, "1.0 (12)")
    }

    func testActionResults() throws {
        let p = try decodeJSON(PingOneResult.self, SampleJSON.pingOneResult)
        XCTAssertEqual(p, PingOneResult(json: .object(["id": .string("Wm6Tj2Gk"), "ms": .int(7), "ts": .int(1791899279)])))
        XCTAssertEqual(p.ms, 7)
        let ok = try decodeJSON(ActionOK.self, SampleJSON.okResult)
        XCTAssertTrue(ok.ok)
        XCTAssertFalse(ok.same)
        let b = try decodeJSON(ActionOK.self, SampleJSON.blockResult)
        XCTAssertEqual(b.blocked, true)
        XCTAssertEqual(b.mac, "00:00:5e:00:53:03")
        XCTAssertEqual(try decodeJSON(ActionOK.self, SampleJSON.unblockResult).blocked, false)
        XCTAssertEqual(try decodeJSON(ActionOK.self, SampleJSON.directResult).direct, true)
        XCTAssertTrue(try decodeJSON(ActionOK.self, SampleJSON.sameResult).same)
        XCTAssertEqual(try decodeJSON(ActionOK.self, SampleJSON.revokeAllResult).revoked, 7)
        let r = try decodeJSON(RenameResult.self, #"{"ok":true,"names":{"00:00:5E:00:53:03":"Телевизор","00:00:5e:00:53:02":"Приставка","x":5}}"#)
        XCTAssertEqual(r.names, ["00:00:5e:00:53:03": "Телевизор", "00:00:5e:00:53:02": "Приставка", "x": "5"])
        XCTAssertEqual(try decodeJSON(RenameResult.self, SampleJSON.renameResult).names.count, 2)
    }

    func testSpeedtestJob() throws {
        let start = try decodeJSON(JobStart.self, SampleJSON.speedtestJobStart)
        XCTAssertEqual(start.job, "34045d1894d672ac")
        let done = try decodeJSON(JobStatus.self, SampleJSON.speedtestJobDone)
        guard case .done(let d) = done else {
            return XCTFail("expected done")
        }
        XCTAssertEqual(d.action, "speedtest")
        XCTAssertNil(d.status)
        XCTAssertEqual(d.speed?.down, 90000000)
        XCTAssertEqual(d.speed?.country, "DE")
        let busy = try decodeJSON(JobStatus.self, SampleJSON.speedtestJobBusy)
        guard case .failed(let action, let e) = busy else {
            return XCTFail("expected failed")
        }
        XCTAssertEqual(action, "speedtest")
        XCTAssertEqual(e.status, 409)
        XCTAssertEqual(e.source, "router")
        XCTAssertTrue(ActionErrorPolicy.isRouterBusy(e))
    }

    func testConfirmFixtures() throws {
        let cases: [(String, Danger, String)] = [
            (SampleJSON.confirmSwitchNode, .high, "Подключить «🇩🇪 Германия»?"),
            (SampleJSON.confirmSwitchCurrent, .high, "Подключить «fspiratNL»?"),
            (SampleJSON.confirmSwitchDead, .high, "Подключить «🇫🇮 Финляндия»?"),
            (SampleJSON.confirmSwitchUnknown, .high, "Подключить другой сервер?"),
            (SampleJSON.confirmSwitchDirect, .critical, "Пустить весь трафик напрямую, без VPN?"),
            (SampleJSON.confirmSubupdateSid, .high, "Обновить подписку «Reserve»?"),
            (SampleJSON.confirmSubupdateAll, .high, "Обновить подписки VPN?"),
            (SampleJSON.confirmBlockNamed, .high, "Выключить интернет устройству?"),
            (SampleJSON.confirmBlockUnnamed, .high, "Выключить интернет устройству?"),
            (SampleJSON.confirmDirectOn, .high, "Пускать устройство мимо VPN?"),
            (SampleJSON.confirmDirectOff, .high, "Пускать устройство снова через VPN?"),
            (SampleJSON.confirmSchedule, .medium, "Включить расписание интернета?"),
            (SampleJSON.confirmDiradd, .high, "Пускать ozon.ru напрямую?"),
            (SampleJSON.confirmDirdel, .high, "Убрать kinopoisk.ru из MyDirect?"),
            (SampleJSON.confirmSvcdirectOn, .high, "Пускать YouTube напрямую?"),
            (SampleJSON.confirmSvcdirectOff, .high, "Хайпиксель снова через VPN?"),
            (SampleJSON.confirmZapretOn, .high, "Включить zapret для YouTube и Discord?"),
            (SampleJSON.confirmZapretOff, .high, "Выключить zapret?"),
            (SampleJSON.confirmTgwsOn, .medium, "Включить прокси Telegram?"),
            (SampleJSON.confirmTgwsOff, .medium, "Выключить прокси Telegram?"),
            (SampleJSON.confirmRevokeAll, .critical, "Выйти на всех устройствах?"),
            (SampleJSON.confirmRevokeAllWeb, .critical, "Выйти на всех устройствах?")
        ]
        for (body, danger, title) in cases {
            let p = try decodeJSON(ConfirmPrompt.self, body)
            XCTAssertEqual(p.danger, danger, title)
            XCTAssertEqual(p.title, title)
            XCTAssertEqual(p.expiresIn, 60)
            XCTAssertFalse(p.button.isEmpty)
        }
        let dead = try decodeJSON(ConfirmPrompt.self, SampleJSON.confirmSwitchDead)
        XCTAssertTrue(dead.text.hasSuffix("Сервер сейчас не отвечает — дом может остаться без VPN до автопереключения (~10 мин)."))
        let cur = try decodeJSON(ConfirmPrompt.self, SampleJSON.confirmSwitchCurrent)
        XCTAssertTrue(cur.text.hasPrefix("Этот сервер уже подключён. "))
        let blockUnnamed = try decodeJSON(ConfirmPrompt.self, SampleJSON.confirmBlockUnnamed)
        XCTAssertTrue(blockUnnamed.text.hasPrefix("Устройство 00:00:5e:00:53:04 останется в Wi-Fi"))
        let web = try decodeJSON(ConfirmPrompt.self, SampleJSON.confirmRevokeAllWeb)
        XCTAssertTrue(web.text.hasSuffix("Также закроются все сессии веб-панели, и каждый браузер снова попросит код из Telegram."))
        XCTAssertEqual(web.button, "Выйти везде")
    }

    func testErrorFixtures() {
        func err(_ status: Int, _ body: String) -> APIError {
            return APIError.fromHTTP(status: status, body: Data(body.utf8), headers: [:])
        }
        XCTAssertEqual(err(400, SampleJSON.errBadNode).userMessage, "Такого сервера нет — обнови список.")
        XCTAssertEqual(err(400, SampleJSON.errTime).userMessage, "Неверное время.")
        XCTAssertEqual(err(400, SampleJSON.errNoTarget).code, "no target")
        XCTAssertEqual(err(500, SampleJSON.errNft).userMessage, "Роутер не смог изменить правила.")
        XCTAssertEqual(err(503, SampleJSON.errNotInstalled).userMessage, "Не установлено на роутере.")
        XCTAssertTrue(ActionErrorPolicy.isRouterBusy(err(409, SampleJSON.errRouterBusy)))
        XCTAssertEqual(err(400, SampleJSON.errDirdelNotAdded).userMessage, "Убрать можно только домены, добавленные из панели или приложения.")
        XCTAssertEqual(err(400, SampleJSON.errTooLong).code, "too_long")
        XCTAssertEqual(err(429, SampleJSON.errRateLimited).userMessage, "Слишком часто — подожди немного. Повтори через 30\u{00A0}с.")
        XCTAssertEqual(err(404, SampleJSON.errNotFound).userMessage, "Не найдено.")
        XCTAssertEqual(err(400, SampleJSON.errConfirmInvalid).userMessage, "Подтверждение не подошло — повтори действие.")
        // A router code without a message falls back to the dictionary.
        XCTAssertEqual(err(400, #"{"error":"bad sub","source":"router"}"#).userMessage, "Нет такой подписки — обнови список.")
        XCTAssertEqual(err(500, #"{"error":"subscribe.lua not found","source":"router"}"#).userMessage, "На роутере нет скрипта подписок PassWall.")
        XCTAssertEqual(err(500, #"{"error":"weird","source":"router"}"#).userMessage, "Роутер не смог выполнить действие.")
    }

    func testReplacingNames() throws {
        let d = try decodeJSON(DataResponse.self, SampleJSON.dataWeek)
        let r = d.replacingNames(["00:00:5E:00:53:03": "Телевизор"])
        XCTAssertEqual(r.names, ["00:00:5e:00:53:03": "Телевизор"])
        XCTAssertEqual(r.points, d.points)
    }
}
