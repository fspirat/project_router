import Foundation
import XCTest
@testable import RouterCore

/// «VPN» tab rules (contract-stage4 §5.1, expected values of §10.1).
final class VPNTests: XCTestCase {

    func status() throws -> RouterStatus {
        return try decodeJSON(RouterStatus.self, SampleJSON.statusStage4)
    }

    func statusWith(_ patch: (inout [String: JSONValue]) -> Void) throws -> RouterStatus {
        guard case .object(var o) = try JSONValue.parse(SampleJSON.statusStage4) else {
            throw XCTSkip("fixture")
        }
        patch(&o)
        return RouterStatus(json: .object(o))
    }

    func testBasics() throws {
        let s = try status()
        XCTAssertEqual(VPN.services(s).map { $0.name }, ["YouTube", "Discord", "Telegram", "Хайпиксель"])
        XCTAssertEqual(VPN.svcOf(s, "Kq7Lm2Xp"), s.targets, "current → fresh targets")
        XCTAssertEqual(VPN.svcOf(s, "Hd3Fs9Qa")?.ts, 1791884590)
        XCTAssertEqual(VPN.svcOf(s, "direct")?.base, 9)
        XCTAssertEqual(VPN.svcOf(s, "_direct")?.base, 9)
        XCTAssertNil(VPN.svcOf(s, "Bx2Kd7Lr"), "not measured")
        XCTAssertEqual(VPN.svcVal(VPN.svcOf(s, "Pz1Yc4Ue"), "Telegram"), 0)
        XCTAssertNil(VPN.svcVal(nil, "Telegram"))
        XCTAssertNil(VPN.svcVal(VPN.svcOf(s, "Pz1Yc4Ue"), "Instagram"))
        XCTAssertEqual(VPN.nodeName(s, "Pz1Yc4Ue"), "🇳🇱 Нидерланды")
        XCTAssertEqual(VPN.nodeName(s, "_direct"), "Напрямую (без VPN)")
        XCTAssertEqual(VPN.nodeName(s, "direct"), "Напрямую (без VPN)")
        XCTAssertEqual(VPN.nodeName(s, "Zz9Zz9Zz"), "Zz9Zz9Zz")
        XCTAssertEqual(VPN.nodeName(nil, "Zz9Zz9Zz"), "Zz9Zz9Zz")
        XCTAssertEqual(VPN.mode(s), .vpn)
        XCTAssertEqual(VPN.connected(s).name, "fspiratNL")
        XCTAssertEqual(VPN.connected(s).tag, "свой")
        XCTAssertNil(VPN.splitWarning(s))
        let direct = try decodeJSON(RouterStatus.self, SampleJSON.statusDirectMode)
        XCTAssertEqual(VPN.mode(direct), .direct)
        let noSplit = try statusWith { $0["split_active"] = .bool(false) }
        XCTAssertEqual(VPN.splitWarning(noSplit), Summary.splitWarningText)
    }

    func testServerListGroupsAndCells() throws {
        let s = try status()
        let l = VPN.serverList(s, now: nowT)
        XCTAssertEqual(l.sort, .default)
        XCTAssertEqual(l.groups.map { $0.title }, ["Свои серверы", "Подписка nosok", "Подписка Reserve"])
        XCTAssertEqual(l.groups[0].kind, .own)
        XCTAssertEqual(l.groups[1].kind, .subscription("nosok"))
        XCTAssertEqual(l.groups.map { $0.rows.map { $0.name } }, [["fspiratNL", "fspiratDE"], ["🇩🇪 Германия", "🇳🇱 Нидерланды"], ["🇸🇪 Швеция"]])
        let nl = l.groups[0].rows[0]
        XCTAssertTrue(nl.isCurrent)
        XCTAssertEqual(nl.tag, "свой")
        XCTAssertEqual(nl.pingText, "41\u{00A0}мс")
        XCTAssertTrue(nl.pingIsBest)
        XCTAssertEqual(nl.pingLevel, 5)
        XCTAssertEqual(nl.servicesLine, "YouTube 61 · Discord — · Telegram 74 · Хайпиксель 112")
        XCTAssertEqual(nl.cells.map { $0.isBest }, [false, false, true, false])
        XCTAssertEqual(nl.cells[1].tone, .err)
        let de = l.groups[0].rows[1]
        XCTAssertTrue(de.isDead)
        XCTAssertEqual(de.pingText, "—")
        XCTAssertEqual(de.pingTone, .err)
        XCTAssertEqual(de.cells, [])
        XCTAssertEqual(de.servicesLine, "")
        let ger = l.groups[1].rows[0]
        XCTAssertEqual(ger.servicesLine, "YouTube 88 · Discord 95 · Telegram 102 · Хайпиксель 140")
        XCTAssertEqual(ger.cells.map { $0.isBest }, [false, false, false, false])
        let nld = l.groups[1].rows[1]
        XCTAssertEqual(nld.servicesLine, "YouTube 38 · Discord 71 · Telegram — · Хайпиксель 97")
        XCTAssertEqual(nld.cells.map { $0.isBest }, [true, true, false, true])
        let swe = l.groups[2].rows[0]
        XCTAssertEqual(swe.cells.map { $0.text }, ["·", "·", "·", "·"])
        XCTAssertEqual(swe.cells[0].hint, "ещё не мерили")
        XCTAssertEqual(l.dead.map { $0.name }, ["🇫🇮 Финляндия", "🇵🇱 Польша"])
        XCTAssertEqual(l.deadTitle, "Не отвечают: 2")
        let d = try XCTUnwrap(l.direct)
        XCTAssertEqual(d.name, "Напрямую")
        XCTAssertEqual(d.tag, "без VPN")
        XCTAssertEqual(d.pingText, "9\u{00A0}мс")
        XCTAssertFalse(d.isCurrent)
        XCTAssertEqual(d.cells.map { $0.text }, ["блок", "блок", "блок", "31"])
        XCTAssertEqual(d.cells[0].hint, "Без VPN этот сайт в России не открывается")
        XCTAssertNil(l.emptyText)
        XCTAssertEqual(l.footer, "Сервисы через другие серверы меряются раз в 30 минут. Проверено 6\u{00A0}мин назад")
    }

    func testDirectRowWhenCurrent() throws {
        let s = try statusWith { $0["current"] = .string("_direct") }
        let l = VPN.serverList(s, now: nowT)
        let d = try XCTUnwrap(l.direct)
        XCTAssertTrue(d.isCurrent)
        // current direct uses the fresh `targets` and never shows «блок»
        XCTAssertEqual(d.cells.map { $0.text }, ["61", "—", "74", "112"])
        XCTAssertFalse(l.groups.flatMap { $0.rows }.contains { $0.isCurrent })
    }

    func testUntitledSingleGroupAndEmpty() throws {
        let one = try statusWith { o in
            o["ping"] = try! JSONValue.parse(#"{"updated":1791886200,"nodes":[{"id":"Hd3Fs9Qa","name":"A","ms":57,"group":"nosok"},{"id":"Pz1Yc4Ue","name":"B","ms":40,"group":"nosok"}]}"#)
            o["svc"] = .object([:])
        }
        let l = VPN.serverList(one, now: nowT)
        XCTAssertEqual(l.groups.count, 1)
        XCTAssertNil(l.groups[0].title)
        XCTAssertEqual(l.groups[0].rows.map { $0.name }, ["B", "A"])
        XCTAssertNil(l.direct)
        XCTAssertEqual(l.deadTitle, "")

        let none = try statusWith { o in
            o["ping"] = try! JSONValue.parse(#"{"updated":1791886200,"nodes":[{"id":"Wm6Tj2Gk","name":"X","ms":0,"group":"nosok"}]}"#)
        }
        let e = VPN.serverList(none, now: nowT)
        XCTAssertEqual(e.groups, [])
        XCTAssertEqual(e.emptyText, "Ни один сервер не ответил. Нажми «Проверить».")
        XCTAssertEqual(e.dead.count, 1)
        XCTAssertNotNil(e.direct)

        let groupless = try statusWith { o in
            o["ping"] = try! JSONValue.parse(#"{"nodes":[{"id":"Hd3Fs9Qa","name":"A","ms":57,"group":""},{"id":"Pz1Yc4Ue","name":"B","ms":40,"group":"x"}]}"#)
        }
        XCTAssertEqual(VPN.serverList(groupless, now: nowT).groups.map { $0.title }, ["Подписка x", "Подписка"], "fastest group first; empty group → «Подписка»")

        let running = try statusWith { $0["svc_running"] = .bool(true) }
        XCTAssertTrue(VPN.serverList(running, now: nowT).footer.hasSuffix(" Сервисы перемеряются…"))
    }

    func testSorting() throws {
        let s = try status()
        let byName = VPN.serverList(s, sort: ServerSort(key: .name), now: nowT)
        XCTAssertEqual(byName.groups[1].rows.map { $0.name }, ["🇩🇪 Германия", "🇳🇱 Нидерланды"])
        XCTAssertEqual(byName.groups[0].rows.map { $0.name }, ["fspiratDE", "fspiratNL"])
        let byNameDesc = VPN.serverList(s, sort: ServerSort(key: .name, ascending: false), now: nowT)
        XCTAssertEqual(byNameDesc.groups[1].rows.map { $0.name }, ["🇳🇱 Нидерланды", "🇩🇪 Германия"])
        let byTelegram = VPN.serverList(s, sort: ServerSort(key: .service("Telegram")), now: nowT)
        XCTAssertEqual(byTelegram.groups[1].rows.map { $0.name }, ["🇩🇪 Германия", "🇳🇱 Нидерланды"], "0 is always last")
        let byTelegramDesc = VPN.serverList(s, sort: ServerSort(key: .service("Telegram"), ascending: false), now: nowT)
        XCTAssertEqual(byTelegramDesc.groups[1].rows.map { $0.name }, ["🇩🇪 Германия", "🇳🇱 Нидерланды"], "bad values last regardless of direction")
        let byYouTube = VPN.serverList(s, sort: ServerSort(key: .service("YouTube")), now: nowT)
        XCTAssertEqual(byYouTube.groups[1].rows.map { $0.name }, ["🇳🇱 Нидерланды", "🇩🇪 Германия"])
        let byYouTubeDesc = VPN.serverList(s, sort: ServerSort(key: .service("YouTube"), ascending: false), now: nowT)
        XCTAssertEqual(byYouTubeDesc.groups[1].rows.map { $0.name }, ["🇩🇪 Германия", "🇳🇱 Нидерланды"])
        let byPingDesc = VPN.serverList(s, sort: ServerSort(key: .ping, ascending: false), now: nowT)
        XCTAssertEqual(byPingDesc.groups[1].rows.map { $0.name }, ["🇳🇱 Нидерланды", "🇩🇪 Германия"])
        XCTAssertEqual(byPingDesc.groups[0].rows.map { $0.name }, ["fspiratNL", "fspiratDE"], "dead own servers stay last")
        let gone = VPN.serverList(s, sort: ServerSort(key: .service("Instagram"), ascending: false), now: nowT)
        XCTAssertEqual(gone.sort, .default, "a missing service resets the sort")
    }

    func testSortStorage() {
        XCTAssertEqual(ServerSort(storage: "ping"), .default)
        XCTAssertEqual(ServerSort(storage: "-name"), ServerSort(key: .name, ascending: false))
        XCTAssertEqual(ServerSort(storage: "svc:Хайпиксель"), ServerSort(key: .service("Хайпиксель")))
        XCTAssertEqual(ServerSort(storage: "garbage"), .default)
        XCTAssertEqual(ServerSort(storage: "svc:"), .default)
        XCTAssertEqual(ServerSort(key: .service("YouTube"), ascending: false).storageValue, "-svc:YouTube")
        XCTAssertEqual(ServerSort(storage: ServerSort(key: .name, ascending: false).storageValue), ServerSort(key: .name, ascending: false))
        XCTAssertEqual(ServerSort.default.tapped(.ping), ServerSort(key: .ping, ascending: false))
        XCTAssertEqual(ServerSort(key: .ping, ascending: false).tapped(.name), ServerSort(key: .name))
        XCTAssertEqual(ServerSort(key: .service("YouTube")).label, "YouTube")
        XCTAssertEqual(ServerSort.default.label, "пинг")
    }

    func testBestChips() throws {
        let chips = VPN.bestChips(try status())
        XCTAssertEqual(chips.map { $0.text }, [
            "YouTube: 🇳🇱 Нидерланды 38\u{00A0}мс",
            "Discord: 🇳🇱 Нидерланды 71\u{00A0}мс",
            "Telegram: fspiratNL 74\u{00A0}мс",
            "Хайпиксель: 🇳🇱 Нидерланды 97\u{00A0}мс"
        ])
        XCTAssertEqual(chips.map { $0.isCurrent }, [false, false, true, false])
        XCTAssertEqual(chips[0].action, .switchServer(id: "Pz1Yc4Ue"))
        XCTAssertNil(chips[2].action)
        XCTAssertEqual(chips[0].icon, "play.rectangle")
        XCTAssertEqual(chips[3].icon, "cube")
    }

    func testServerDetail() throws {
        let s = try status()
        let nl = try XCTUnwrap(VPN.serverDetail(s, id: "Pz1Yc4Ue", now: nowT))
        XCTAssertEqual(nl.name, "🇳🇱 Нидерланды")
        XCTAssertEqual(nl.tag, "Подписка nosok")
        XCTAssertFalse(nl.isCurrent)
        XCTAssertNil(nl.currentText)
        XCTAssertEqual(nl.pingText, "63\u{00A0}мс")
        XCTAssertEqual(nl.checkedText, "Проверено 6\u{00A0}мин назад")
        XCTAssertEqual(nl.services.map { $0.valueText }, ["38\u{00A0}мс", "71\u{00A0}мс", "нет ответа", "97\u{00A0}мс"])
        XCTAssertEqual(nl.measuredText, "Замер 33\u{00A0}мин назад")
        XCTAssertTrue(nl.canPingOne)
        XCTAssertTrue(nl.canConnect)
        XCTAssertEqual(nl.pingAction, .pingone(id: "Pz1Yc4Ue"))
        XCTAssertEqual(nl.connectAction, .switchServer(id: "Pz1Yc4Ue"))

        let cur = try XCTUnwrap(VPN.serverDetail(s, id: "Kq7Lm2Xp", now: nowT, pingedAt: nowT - 10))
        XCTAssertTrue(cur.isCurrent)
        XCTAssertEqual(cur.currentText, "Подключён сейчас")
        XCTAssertFalse(cur.canConnect)
        XCTAssertNil(cur.connectAction)
        XCTAssertEqual(cur.checkedText, "Проверено только что")

        let dead = try XCTUnwrap(VPN.serverDetail(s, id: "Wm6Tj2Gk", now: nowT))
        XCTAssertEqual(dead.pingText, "нет ответа")
        XCTAssertEqual(dead.services.map { $0.valueText }, Array(repeating: "сервер не отвечает", count: 4))
        XCTAssertTrue(dead.canConnect)

        let swe = try XCTUnwrap(VPN.serverDetail(s, id: "Bx2Kd7Lr", now: nowT))
        XCTAssertEqual(swe.services.map { $0.valueText }, Array(repeating: "ещё не мерили", count: 4))
        XCTAssertNil(swe.measuredText)

        let direct = try XCTUnwrap(VPN.serverDetail(s, id: "direct", now: nowT))
        XCTAssertTrue(direct.isDirect)
        XCTAssertFalse(direct.canPingOne)
        XCTAssertNil(direct.pingAction)
        XCTAssertTrue(direct.showsDirectButton)
        XCTAssertEqual(direct.connectAction, .switchDirect)
        XCTAssertEqual(direct.pingText, "9\u{00A0}мс")
        XCTAssertEqual(direct.services.map { $0.valueText }, ["не открывается без VPN", "не открывается без VPN", "не открывается без VPN", "31\u{00A0}мс"])

        XCTAssertNil(VPN.serverDetail(s, id: "Zz9Zz9Zz", now: nowT))
    }

    func testSwitchHistory() throws {
        let d = try decodeJSON(DataResponse.self, SampleJSON.dataWeek)
        let h = VPN.switchHistory(data: d, status: nil, now: nowT)
        XCTAssertEqual(h.map { $0.text }, ["Сервер выбран вручную: fspiratNL", "Автопереключение: fspiratDE → fspiratNL 41\u{00A0}мс"])
        XCTAssertEqual(h.map { $0.time }, ["сегодня 14:10", "сегодня 06:10"])
        XCTAssertEqual(h.map { $0.chip }, ["Действие", "Внимание"])
        XCTAssertEqual(h.map { $0.level }, [.info, .warn])
        XCTAssertEqual(VPN.switchHistory(data: d, status: nil, now: nowT, limit: 1).count, 1)
        XCTAssertEqual(VPN.switchHistory(data: d, status: nil, now: nowT, limit: 0).count, 0)
        let o = try decodeJSON(DataResponse.self, SampleJSON.dataWeekObserved)
        XCTAssertEqual(VPN.switchHistory(data: o, status: nil, now: nowT).first?.text, "Сервер выбран вручную: Напрямую (без VPN)")

        let fallback = VPN.switchHistory(data: nil, status: try status(), now: nowT)
        XCTAssertEqual(fallback.count, 1)
        XCTAssertEqual(fallback[0].text, "вручную → fspiratNL")
        XCTAssertEqual(fallback[0].time, "13.10 13:20")
        XCTAssertNil(fallback[0].ts)
        let log = try statusWith { $0["log"] = .array([.string("13.10 10:00 авто: Kq7Lm2Xp -> _direct"), .string("13.10 11:00 вручную -> Hd3Fs9Qa")]) }
        XCTAssertEqual(VPN.switchHistoryFromLog(log).map { $0.text }, ["вручную → 🇩🇪 Германия", "авто: fspiratNL → Напрямую (без VPN)"])
        XCTAssertEqual(VPN.switchHistoryFromLog(log).map { $0.level }, [.info, .warn])
        XCTAssertEqual(VPN.switchHistoryFromLog(nil), [])
    }

    func testSubscriptions() throws {
        let s = try status()
        let subs = VPN.subscriptions(s, now: nowT)
        XCTAssertEqual(VPN.subscriptionsHeader(subs.count), "2\u{00A0}подписки")
        XCTAssertEqual(VPN.subscriptionsHeader(0), "")
        let n = subs[0]
        XCTAssertEqual(n.name, "nosok")
        XCTAssertTrue(n.hwid)
        XCTAssertFalse(n.isCurrentSource)
        XCTAssertEqual(n.info, "sub.example.net · 14\u{00A0}серверов · обновлено 16\u{00A0}мин назад")
        XCTAssertEqual(n.daysLeft, 17)
        XCTAssertEqual(n.daysLeftText, "осталось 17\u{00A0}дн.")
        XCTAssertFalse(n.daysLeftIsCritical)
        XCTAssertEqual(n.usageText, "израсходовано 39,2\u{00A0}ГБ из 200,0\u{00A0}ГБ")
        XCTAssertEqual(n.percent, 20)
        XCTAssertEqual(n.barTone, .ok)
        XCTAssertEqual(n.expiryText, "до 31 октября")
        XCTAssertEqual(n.updateAction, .subupdate(sid: "cfg5a1b2c"))
        let r = subs[1]
        XCTAssertEqual(r.info, "r.example.org · 6\u{00A0}серверов")
        XCTAssertNil(r.daysLeftText)
        XCTAssertNil(r.usageText)
        XCTAssertNil(r.percent)
        XCTAssertNil(r.expiryText)
        XCTAssertEqual(r.updateAction, .subupdate(sid: "cfg7d8e9f"))

        // current node from a subscription → «сервер отсюда подключён»
        let fromSub = try statusWith { $0["current"] = .string("Hd3Fs9Qa") }
        XCTAssertEqual(VPN.subscriptions(fromSub, now: nowT).map { $0.isCurrentSource }, [true, false])

        // `subs == null` → one synthetic item from `sub`
        let synthetic = try statusWith { $0["subs"] = .null }
        let one = VPN.subscriptions(synthetic, now: nowT)
        XCTAssertEqual(one.count, 1)
        XCTAssertEqual(one[0].id, "")
        XCTAssertEqual(one[0].name, "nosok")
        XCTAssertEqual(one[0].info, "5\u{00A0}серверов · обновлено 16\u{00A0}мин назад")
        XCTAssertEqual(one[0].updateAction, .subupdateAll)
        let nothing = try statusWith { o in
            o["subs"] = .null
            o["sub"] = .null
        }
        XCTAssertEqual(VPN.subscriptions(nothing, now: nowT), [])

        // expiry and usage edge cases
        let edge = try statusWith { o in
            o["subs"] = try! JSONValue.parse(#"[{"id":"a","name":"A","host":"","nodes":1,"up":0,"down":1073741824,"total":0,"expire":1791900000},{"id":"b","name":"B","host":"","nodes":2,"up":0,"down":1,"total":100,"expire":1791800000},{"id":"c","name":"C","host":"","nodes":21,"up":70,"down":0,"total":100}]"#)
        }
        let e = VPN.subscriptions(edge, now: nowT)
        XCTAssertEqual(e[0].daysLeft, 0)
        XCTAssertEqual(e[0].daysLeftText, "закончилась")
        XCTAssertTrue(e[0].daysLeftIsCritical)
        XCTAssertEqual(e[0].usageText, "израсходовано 1,0\u{00A0}ГБ · без лимита")
        XCTAssertEqual(e[1].daysLeftText, "закончилась")
        XCTAssertEqual(e[1].percent, 1)
        XCTAssertEqual(e[2].info, "21\u{00A0}сервер")
        XCTAssertEqual(e[2].percent, 70)
        XCTAssertEqual(e[2].barTone, .warn)
    }

    func testSpeedCards() throws {
        let s = try status()
        let vpn = VPN.speedCard(via: .vpn, result: s.speed.vpn, now: nowT)
        XCTAssertEqual(vpn.title, "С роутера, через VPN")
        XCTAssertFalse(vpn.isEmpty)
        XCTAssertEqual(vpn.downText, "91,2\u{00A0}Мбит/с")
        XCTAssertEqual(vpn.upText, "40,1\u{00A0}Мбит/с")
        XCTAssertEqual(vpn.latencyText, "38\u{00A0}мс")
        XCTAssertEqual(vpn.meta, "Выход: 🇳🇱 203.0.113.77, проверено 2\u{00A0}ч назад · Hetzner (Германия), 4 потока")
        let direct = VPN.speedCard(via: .direct, result: s.speed.direct, now: nowT)
        XCTAssertEqual(direct.title, "С роутера, без VPN")
        XCTAssertEqual(direct.downText, "286\u{00A0}Мбит/с")
        XCTAssertEqual(direct.upText, "позже")
        XCTAssertEqual(direct.latencyText, "6\u{00A0}мс")
        XCTAssertEqual(direct.meta, "Выход: 🇷🇺 198.51.100.20, проверено 2\u{00A0}ч назад · Selectel (Россия), 4 потока · Cloudflare ограничил частые замеры отдачи, повтори через пару минут")
        let empty = VPN.speedCard(via: .direct, result: nil, now: nowT)
        XCTAssertTrue(empty.isEmpty)
        XCTAssertEqual(empty.emptyText, "Ещё не запускали.")
        var bare = try XCTUnwrap(s.speed.vpn)
        bare.ip = ""
        bare.up = 0
        bare.upLimited = false
        bare.latency = 0
        bare.server = ""
        let b = VPN.speedCard(via: .vpn, result: bare, now: nowT)
        XCTAssertEqual(b.upText, "—")
        XCTAssertEqual(b.latencyText, "—")
        XCTAssertEqual(b.meta, "проверено 2\u{00A0}ч назад")
    }

    func testSpeedHistory() throws {
        let d = try decodeJSON(DataResponse.self, SampleJSON.dataWeek)
        let h = VPN.speedHistory(d.speed, now: nowT)
        XCTAssertFalse(h.isEmpty)
        XCTAssertEqual(h.from, 1791879000)
        XCTAssertEqual(h.to, 1791879000 + 86400, "span is at least a day")
        XCTAssertEqual(h.yMax, 286000000 * 1.15, accuracy: 0.5)
        XCTAssertEqual(h.series.map { $0.via }, [.vpn, .direct])
        XCTAssertEqual(h.series[0].points, [SpeedPoint(ts: 1791880000, value: 91234567, tooltip: "через VPN: 91,2\u{00A0}Мбит/с, сегодня 12:26")])
        XCTAssertEqual(h.series[1].label, "напрямую")
        XCTAssertEqual(h.caption, "сегодня 12:10 · до 286\u{00A0}Мбит/с")
        let up = VPN.speedHistory(d.speed, now: nowT, upload: true)
        XCTAssertEqual(up.series[1].points[0].value, 0)
        XCTAssertEqual(up.caption, "сегодня 12:10 · до 40\u{00A0}Мбит/с")
        let empty = VPN.speedHistory([], now: nowT)
        XCTAssertTrue(empty.isEmpty)
        XCTAssertEqual(empty.caption, "История появится после первых тестов")
        // long history: domain from the oldest row to now
        let old = SpeedHistoryEntry(json: .array([.int(1791886560 - 5 * 86400), .string("vpn"), .int(1000000), .int(0), .int(10)]))!
        let long = VPN.speedHistory([old], now: nowT)
        XCTAssertEqual(long.to, 1791886560)
    }

    func testOwnServers() throws {
        let v = try decodeJSON(VdsResponse.self, SampleJSON.vds)
        let info = VPN.ownServers(v, now: nowT)
        XCTAssertEqual(info.footer, "Данные 2\u{00A0}мин назад.")
        XCTAssertEqual(info.rows.count, 3)
        let a = info.rows[0]
        XCTAssertEqual(a.name, "Сервер панели")
        XCTAssertEqual(a.caption, "Здесь же панель")
        XCTAssertEqual(a.tone, .ok)
        XCTAssertEqual(a.statusLine, "VPN (Xray) работает · соединений 14")
        XCTAssertEqual(a.loadLine, "Нагрузка 0,08 0,05 0,01 на 2\u{00A0}ядр. · память 35% из 1,9\u{00A0}ГБ · диск 37%")
        XCTAssertEqual(a.uptimeLine, "Без перезагрузки 14\u{00A0}д 0\u{00A0}ч · трафик с запуска ↓855,2\u{00A0}ГБ ↑843,0\u{00A0}ГБ")
        let de = info.rows[1]
        XCTAssertFalse(de.isReachable)
        XCTAssertEqual(de.statusLine, "не отвечает по SSH")
        XCTAssertEqual(de.tone, .err)
        XCTAssertNil(de.loadLine)
        XCTAssertNil(de.caption)
        let nl2 = info.rows[2]
        XCTAssertEqual(nl2.statusLine, "VPN (Xray): inactive · соединений 0")
        XCTAssertEqual(nl2.tone, .err)
        XCTAssertEqual(nl2.loadLine, "Нагрузка 0,50 0,40 0,30 на 1\u{00A0}ядр. · память 80% из 1,0\u{00A0}ГБ · диск 81%")
        XCTAssertEqual(nl2.uptimeLine, "Без перезагрузки 1\u{00A0}д 0\u{00A0}ч · трафик с запуска ↓1,0\u{00A0}МБ ↑2,0\u{00A0}МБ")
        XCTAssertEqual(VPN.ownServers(v, now: Double(1791886440 + 89)).footer, "Данные свежие.")
        XCTAssertEqual(VPN.ownServers(try decodeJSON(VdsResponse.self, SampleJSON.vdsEmpty), now: nowT).footer, "Данных о серверах пока нет — они собираются раз в 5 минут.")
        XCTAssertEqual(VPN.ownServers(nil, now: nowT).rows, [])
        let noXray = try decodeJSON(VdsResponse.self, #"{"ts":1791886500,"servers":[{"name":"X","stat":{"xray":"","conns":1}}]}"#)
        XCTAssertEqual(VPN.ownServers(noXray, now: nowT).rows[0].statusLine, "VPN (Xray): не запущен · соединений 1")
    }

    func testCompactOfflineLine() throws {
        let d = try decodeJSON(DataResponse.self, SampleJSON.dataDayOffline)
        XCTAssertEqual(OfflineBanner.compactLine(data: d, now: nowT), "Роутер не на связи с 14:04 · уже 12\u{00A0}мин")
        XCTAssertEqual(OfflineBanner.compactLine(data: nil, now: nowT), "Роутер не на связи")
    }
}
