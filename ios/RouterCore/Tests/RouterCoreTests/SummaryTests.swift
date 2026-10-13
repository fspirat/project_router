import Foundation
import XCTest
@testable import RouterCore

final class SummaryTests: XCTestCase {

    private func status(_ text: String) throws -> RouterStatus {
        return try decodeJSON(RouterStatus.self, text)
    }

    private func item(_ v: Verdict, _ name: String) -> VerdictItem? {
        return v.items.first(where: { $0.name == name })
    }

    // MARK: - Verdict

    func testCheckingBeforeFirstLoad() {
        let v = Summary.verdict(status: nil, isOffline: false, firstLoadFinished: false, now: nowT)
        XCTAssertEqual(v.level, .neutral)
        XCTAssertEqual(v.title, "Проверяю…")
        XCTAssertTrue(v.items.isEmpty)
        XCTAssertFalse(v.showsCurrentServer)
    }

    func testOfflineVerdict() throws {
        let a = Summary.verdict(status: nil, isOffline: false, firstLoadFinished: true, now: nowT)
        XCTAssertEqual(a.level, .err)
        XCTAssertEqual(a.title, "Есть проблема")
        XCTAssertEqual(a.items, [VerdictItem(name: "Роутер", level: .err, text: "не на связи")])
        XCTAssertFalse(a.showsCurrentServer)

        let b = Summary.verdict(status: try status(SampleJSON.statusNormal), isOffline: true, firstLoadFinished: true, now: nowT)
        XCTAssertEqual(b.items, [VerdictItem(name: "Роутер", level: .err, text: "не на связи")])
        XCTAssertEqual(b.level, .err)
    }

    func testNormalVerdict() throws {
        let v = Summary.verdict(status: try status(SampleJSON.statusNormal), isOffline: false, firstLoadFinished: true, now: nowT)
        XCTAssertEqual(v.level, .warn)
        XCTAssertEqual(v.title, "Требует внимания")
        XCTAssertEqual(v.items, [
            VerdictItem(name: "Роутер", level: .ok, text: "в сети"),
            VerdictItem(name: "VPN", level: .ok, text: "работает"),
            VerdictItem(name: "Интернет", level: .ok, text: "есть"),
            VerdictItem(name: "Серверы", level: .ok, text: "3\u{00A0}из\u{00A0}5"),
            VerdictItem(name: "Сервисы", level: .warn, text: "нет ответа: Discord")
        ])
        XCTAssertNil(v.splitWarning)
        XCTAssertTrue(v.showsCurrentServer)
    }

    func testAllOkVerdict() throws {
        let text = SampleJSON.statusNormal.replacingOccurrences(
            of: #"{"kind":"web","name":"Discord","host":"discord.com","vpn":0}"#,
            with: #"{"kind":"web","name":"Discord","host":"discord.com","vpn":80}"#
        )
        let v = Summary.verdict(status: try status(text), isOffline: false, firstLoadFinished: true, now: nowT)
        XCTAssertEqual(item(v, "Сервисы"), VerdictItem(name: "Сервисы", level: .ok, text: "отвечают"))
        XCTAssertEqual(v.level, .ok)
        XCTAssertEqual(v.title, "Всё работает")
    }

    func testAfterRebootVerdict() throws {
        let v = Summary.verdict(status: try status(SampleJSON.statusAfterReboot), isOffline: false, firstLoadFinished: true, now: nowT)
        XCTAssertEqual(v.items, [
            VerdictItem(name: "Роутер", level: .ok, text: "в сети"),
            VerdictItem(name: "VPN", level: .ok, text: "работает"),
            VerdictItem(name: "Интернет", level: .ok, text: "есть"),
            VerdictItem(name: "Серверы", level: .warn, text: "ещё не проверены")
        ])
        XCTAssertEqual(v.title, "Требует внимания")
    }

    func testDirectModeVerdict() throws {
        let s = try status(SampleJSON.statusDirectMode)
        let v = Summary.verdict(status: s, isOffline: false, firstLoadFinished: true, now: nowT)
        XCTAssertEqual(item(v, "VPN"), VerdictItem(name: "VPN", level: .warn, text: "выключен — всё напрямую"))
        XCTAssertEqual(item(v, "Сервисы"), VerdictItem(name: "Сервисы", level: .warn, text: "нет ответа: YouTube, Discord, Telegram"))
        XCTAssertEqual(item(v, "Серверы"), VerdictItem(name: "Серверы", level: .ok, text: "2\u{00A0}из\u{00A0}2"))
        XCTAssertEqual(v.title, "Требует внимания")
        XCTAssertEqual(Summary.currentServer(s).name, "Напрямую (без VPN)")
        XCTAssertEqual(Summary.currentServer(s).tag, "без VPN")
        XCTAssertTrue(Summary.currentServer(s).isDirect)
        XCTAssertEqual(Summary.routerFacts(s.sys)[0].value, "51\u{00A0}°C")
        XCTAssertEqual(Summary.routerFacts(s.sys)[1].value, "1\u{00A0}ч 1\u{00A0}мин")
        XCTAssertEqual(Summary.routerTitle(s.sys), "Роутер")
    }

    func testVPNFailingVerdict() throws {
        let s = try status(SampleJSON.statusVPNFailing)
        let v = Summary.verdict(status: s, isOffline: false, firstLoadFinished: true, now: nowT)
        XCTAssertEqual(item(v, "VPN"), VerdictItem(name: "VPN", level: .err, text: "не проходит"))
        XCTAssertEqual(item(v, "Интернет"), VerdictItem(name: "Интернет", level: .ok, text: "есть"))
        XCTAssertEqual(item(v, "Серверы"), VerdictItem(name: "Серверы", level: .warn, text: "1\u{00A0}из\u{00A0}2"))
        XCTAssertEqual(v.level, .err)
        XCTAssertEqual(v.title, "Есть проблема")
        XCTAssertEqual(Summary.latency(s, now: nowT).value, "VPN не проходит")
        XCTAssertEqual(Summary.latency(s, now: nowT).tone, .err)
        XCTAssertTrue(Summary.needsPingPreDialog(s))
        XCTAssertTrue(PingPreDialog.isNeeded(s))
    }

    func testVPNFailingWithoutDirectBaseMeansNoInternet() throws {
        var s = try status(SampleJSON.statusVPNFailing)
        s.svc["direct"]?.base = 0
        let v = Summary.verdict(status: s, isOffline: false, firstLoadFinished: true, now: nowT)
        XCTAssertEqual(item(v, "Интернет"), VerdictItem(name: "Интернет", level: .err, text: "нет"))
    }

    func testSocksFalseVariant() throws {
        var s = try status(SampleJSON.statusVPNFailing)
        s.ping?.socks = false
        s.ping?.real = nil
        let v = Summary.verdict(status: s, isOffline: false, firstLoadFinished: true, now: nowT)
        XCTAssertEqual(item(v, "VPN"), VerdictItem(name: "VPN", level: .ok, text: "работает"))
        XCTAssertEqual(Summary.latency(s, now: nowT).value, "—")
        XCTAssertEqual(Summary.latency(s, now: nowT).tone, .neutral)
        XCTAssertFalse(Summary.needsPingPreDialog(s))
    }

    func testVPNStoppedAndSlow() throws {
        var s = try status(SampleJSON.statusNormal)
        s.running = false
        var v = Summary.verdict(status: s, isOffline: false, firstLoadFinished: true, now: nowT)
        XCTAssertEqual(item(v, "VPN"), VerdictItem(name: "VPN", level: .err, text: "остановлен"))
        XCTAssertEqual(item(v, "Интернет"), VerdictItem(name: "Интернет", level: .ok, text: "есть"))

        s.running = true
        s.ping?.real = 300
        v = Summary.verdict(status: s, isOffline: false, firstLoadFinished: true, now: nowT)
        XCTAssertEqual(item(v, "VPN"), VerdictItem(name: "VPN", level: .warn, text: "работает"))
        XCTAssertEqual(Summary.latency(s, now: nowT).value, "300\u{00A0}мс")
        XCTAssertEqual(Summary.latency(s, now: nowT).tone, .err)
    }

    func testRouterWarnings() throws {
        var s = try status(SampleJSON.statusNormal)
        s.sys.temp = 90
        var v = Summary.verdict(status: s, isOffline: false, firstLoadFinished: true, now: nowT)
        XCTAssertEqual(item(v, "Роутер"), VerdictItem(name: "Роутер", level: .warn, text: "90°C"))

        s.sys.temp = 84
        s.sys.memAvail = 10000
        v = Summary.verdict(status: s, isOffline: false, firstLoadFinished: true, now: nowT)
        XCTAssertEqual(item(v, "Роутер"), VerdictItem(name: "Роутер", level: .warn, text: "мало памяти"))

        s.sys.memAvail = 121840
        s.sys.diskUsed = 85000
        v = Summary.verdict(status: s, isOffline: false, firstLoadFinished: true, now: nowT)
        XCTAssertEqual(item(v, "Роутер"), VerdictItem(name: "Роутер", level: .warn, text: "флеш почти полон"))

        s.sys.memTotal = 0
        s.sys.diskTotal = 0
        v = Summary.verdict(status: s, isOffline: false, firstLoadFinished: true, now: nowT)
        XCTAssertEqual(item(v, "Роутер"), VerdictItem(name: "Роутер", level: .ok, text: "в сети"))
    }

    func testServersLevels() throws {
        var s = try status(SampleJSON.statusNormal)
        s.ping?.nodes = []
        var v = Summary.verdict(status: s, isOffline: false, firstLoadFinished: true, now: nowT)
        XCTAssertEqual(item(v, "Серверы"), VerdictItem(name: "Серверы", level: .err, text: "0\u{00A0}из\u{00A0}0"))
        XCTAssertEqual(v.level, .err)

        s = try status(SampleJSON.statusNormal)
        for i in 0..<(s.ping?.nodes.count ?? 0) {
            s.ping?.nodes[i].ms = (i == 2) ? 50 : 0
        }
        v = Summary.verdict(status: s, isOffline: false, firstLoadFinished: true, now: nowT)
        XCTAssertEqual(item(v, "Серверы"), VerdictItem(name: "Серверы", level: .warn, text: "1\u{00A0}из\u{00A0}5"))
    }

    func testSubscriptionItems() throws {
        var s = try status(SampleJSON.statusNormal)
        // 2 days left
        s.subs?[0].expire = SampleJSON.now + 2 * 86400 + 100
        var v = Summary.verdict(status: s, isOffline: false, firstLoadFinished: true, now: nowT)
        XCTAssertEqual(item(v, "Подписка"), VerdictItem(name: "Подписка", level: .warn, text: "осталось 2\u{00A0}дн."))
        // 3 days left: still shown
        s.subs?[0].expire = SampleJSON.now + 3 * 86400 + 100
        v = Summary.verdict(status: s, isOffline: false, firstLoadFinished: true, now: nowT)
        XCTAssertEqual(item(v, "Подписка"), VerdictItem(name: "Подписка", level: .warn, text: "осталось 3\u{00A0}дн."))
        // 4 days: hidden
        s.subs?[0].expire = SampleJSON.now + 4 * 86400 + 100
        v = Summary.verdict(status: s, isOffline: false, firstLoadFinished: true, now: nowT)
        XCTAssertNil(item(v, "Подписка"))
        // less than a day / expired
        s.subs?[0].expire = SampleJSON.now + 3600
        v = Summary.verdict(status: s, isOffline: false, firstLoadFinished: true, now: nowT)
        XCTAssertEqual(item(v, "Подписка"), VerdictItem(name: "Подписка", level: .err, text: "закончилась"))
        XCTAssertEqual(v.level, .err)
        // no expiry anywhere → no item
        s.subs?[0].expire = 0
        s.sub?.expire = 0
        v = Summary.verdict(status: s, isOffline: false, firstLoadFinished: true, now: nowT)
        XCTAssertNil(item(v, "Подписка"))
    }

    func testSplitInactive() throws {
        var s = try status(SampleJSON.statusNormal)
        s.splitActive = false
        let v = Summary.verdict(status: s, isOffline: false, firstLoadFinished: true, now: nowT)
        XCTAssertEqual(v.items.last, VerdictItem(name: nil, level: .warn, text: "в PassWall выбран не Split"))
        XCTAssertEqual(v.splitWarning, Summary.splitWarningText)
        XCTAssertEqual(v.level, .warn)
    }

    // MARK: - Blocks

    func testCurrentServerAndLatency() throws {
        let s = try status(SampleJSON.statusNormal)
        let c = Summary.currentServer(s)
        XCTAssertEqual(c.name, "fspiratNL")
        XCTAssertEqual(c.tag, "свой")
        XCTAssertFalse(c.isDirect)
        let l = Summary.latency(s, now: nowT)
        XCTAssertEqual(l.value, "48\u{00A0}мс")
        XCTAssertEqual(l.tone, .ok)
        XCTAssertEqual(l.footer, "Проверено 6\u{00A0}мин назад")
        XCTAssertFalse(Summary.needsPingPreDialog(s))

        var other = s
        other.current = "Hd3Fs9Qa"
        XCTAssertEqual(Summary.currentServer(other).name, "🇩🇪 Германия")
        XCTAssertEqual(Summary.currentServer(other).tag, "Подписка nosok")
        other.current = "Unknown1"
        XCTAssertEqual(Summary.currentServer(other).name, "Unknown1")
        XCTAssertNil(Summary.currentServer(other).tag)
        other.current = ""
        XCTAssertEqual(Summary.currentServer(other).name, "—")

        let reboot = try status(SampleJSON.statusAfterReboot)
        XCTAssertEqual(Summary.latency(reboot, now: nowT), LatencyTile(value: "—", tone: .neutral, footer: nil))
        XCTAssertEqual(Summary.latency(nil, now: nowT).value, "—")
        XCTAssertFalse(Summary.needsPingPreDialog(reboot))
        XCTAssertFalse(Summary.needsPingPreDialog(nil))
    }

    func testServiceTiles() throws {
        let s = try status(SampleJSON.statusNormal)
        let tiles = Summary.services(s)
        XCTAssertEqual(tiles.map { $0.name }, ["YouTube", "Discord", "Telegram"])
        XCTAssertEqual(tiles.map { $0.valueText }, ["61\u{00A0}мс", "нет ответа", "74\u{00A0}мс"])
        XCTAssertEqual(tiles.map { $0.tone }, [.ok, .err, .ok])
        XCTAssertEqual(tiles.map { $0.icon }, ["play.rectangle", "bubble.left.and.bubble.right", "paperplane"])

        // targets null → svc[current]; list from target_list
        var t = s
        t.targets = nil
        t.current = "Hd3Fs9Qa"
        let tiles2 = Summary.services(t)
        XCTAssertEqual(tiles2.map { $0.host }, ["www.youtube.com", "discord.com", "api.telegram.org"])
        XCTAssertEqual(tiles2.map { $0.valueText }, ["88\u{00A0}мс", "95\u{00A0}мс", "102\u{00A0}мс"])

        // no results for the current server → «—»
        t.current = "Pz1Yc4Ue"
        XCTAssertEqual(Summary.services(t).map { $0.valueText }, ["—", "—", "—"])
        XCTAssertEqual(Summary.services(t).map { $0.tone }, [.neutral, .neutral, .neutral])

        // after reboot: no list at all
        XCTAssertEqual(Summary.services(try status(SampleJSON.statusAfterReboot)), [])
    }

    func testServiceIcons() {
        XCTAssertEqual(Summary.serviceIcon(name: "Видео", host: "rr1.googlevideo.com", kind: "web"), "play.rectangle")
        XCTAssertEqual(Summary.serviceIcon(name: "youtube", host: "", kind: "web"), "play.rectangle")
        XCTAssertEqual(Summary.serviceIcon(name: "X", host: "t.me", kind: "web"), "paperplane")
        XCTAssertEqual(Summary.serviceIcon(name: "X", host: "notyoutube.com", kind: "web"), "globe")
        XCTAssertEqual(Summary.serviceIcon(name: "Insta", host: "scontent.cdninstagram.com", kind: "web"), "camera")
        XCTAssertEqual(Summary.serviceIcon(name: "Server", host: "mc.example.net", kind: "mc"), "cube")
    }

    func testSubscriptionLine() throws {
        let s = try status(SampleJSON.statusNormal)
        let line = try XCTUnwrap(Summary.subscriptionLine(s, now: nowT))
        XCTAssertEqual(line.text, "Подписка до 31 октября · осталось 17\u{00A0}дн. · израсходовано 39,2\u{00A0}ГБ из 200,0\u{00A0}ГБ")
        XCTAssertEqual(line.prefix, "Подписка до ")
        XCTAssertEqual(line.date, "31 октября")
        XCTAssertEqual(line.daysLeft, 17)
        XCTAssertFalse(line.daysLeftIsCritical)

        var many = s
        var second = try XCTUnwrap(s.subs?.first)
        second.name = "backup"
        second.expire = 1792836000
        second.total = 0
        second.down = 1073741824
        second.up = 0
        many.subs?.append(second)
        let line2 = try XCTUnwrap(Summary.subscriptionLine(many, now: nowT))
        XCTAssertEqual(line2.text, "«backup» до 24 октября · осталось 10\u{00A0}дн. · израсходовано 1,0\u{00A0}ГБ, без лимита")

        // fallback to status.sub when subs carry no expiry
        var fb = s
        fb.subs = []
        let line3 = try XCTUnwrap(Summary.subscriptionLine(fb, now: nowT))
        XCTAssertTrue(line3.text.hasPrefix("Подписка до 31 октября"))

        XCTAssertNil(Summary.subscriptionLine(try status(SampleJSON.statusAfterReboot), now: nowT))
    }

    func testMetersAndFacts() throws {
        let s = try status(SampleJSON.statusNormal)
        let m = Summary.meters(s.sys)
        XCTAssertEqual(m[0].title, "Процессор")
        XCTAssertEqual(m[0].percent, 7)
        XCTAssertEqual(m[0].caption, "Средняя нагрузка 0,21 0,17 0,15 · ядер: 2")
        XCTAssertEqual(m[0].tone, .ok)
        XCTAssertEqual(m[1].percent, 50)
        XCTAssertEqual(m[1].caption, "121\u{00A0}МБ из 240\u{00A0}МБ")
        XCTAssertEqual(m[2].percent, 35)
        XCTAssertEqual(m[2].caption, "31\u{00A0}МБ из 87\u{00A0}МБ: пакеты и настройки")
        XCTAssertEqual(Summary.meterTone(percent: 64), .ok)
        XCTAssertEqual(Summary.meterTone(percent: 65), .warn)
        XCTAssertEqual(Summary.meterTone(percent: 85), .err)
        let facts = Summary.routerFacts(s.sys)
        XCTAssertEqual(facts, [Fact(label: "Температура", value: "нет датчика"), Fact(label: "Работает без перезагрузки", value: "4\u{00A0}д 2\u{00A0}ч")])
        XCTAssertEqual(Summary.routerTitle(s.sys), "Xiaomi Mi Router AX3000T")
        XCTAssertEqual(Summary.onlineCount(s), 3)
        XCTAssertEqual(Summary.onlineText(s), "3\u{00A0}в сети")
        XCTAssertEqual(Summary.tmpMeter(s.sys).percent, 3)

        let reboot = try status(SampleJSON.statusAfterReboot)
        XCTAssertEqual(Summary.routerFacts(reboot.sys)[1].value, "1\u{00A0}мин")
    }

    func testTrafficEventsAndDevices() throws {
        let d = try decodeJSON(DataResponse.self, SampleJSON.dataDay)
        let today = Summary.trafficToday(d)
        XCTAssertEqual(today.downText, "1,5\u{00A0}ГБ")
        XCTAssertEqual(today.upText, "51\u{00A0}МБ")
        XCTAssertTrue(today.isVisible)
        XCTAssertFalse(Summary.trafficToday(try decodeJSON(DataResponse.self, SampleJSON.dataDayEmpty)).isVisible)

        let ev = Summary.recentEvents(d, now: nowT)
        XCTAssertEqual(ev.count, 5)
        XCTAssertEqual(ev.map { $0.time }, ["сегодня 14:10", "сегодня 13:30", "сегодня 12:26", "сегодня 10:00", "сегодня 09:54"])
        XCTAssertEqual(ev.map { $0.chip }, ["Действие", "Действие", "Внимание", "Успех", "Ошибка"])
        XCTAssertEqual(ev.map { $0.level }, [.info, .info, .warn, .ok, .err])
        XCTAssertEqual(ev[0].text, "Сервер выбран вручную: fspiratNL")
        XCTAssertEqual(Summary.eventLevel(kind: "vpn_down"), .err)
        XCTAssertEqual(Summary.eventLevel(kind: "xraymem"), .warn)
        XCTAssertEqual(Summary.eventLevel(kind: "vpn_up"), .ok)
        XCTAssertEqual(Summary.eventLevel(kind: "update"), .info)
        XCTAssertEqual(Summary.eventLevel(kind: "something"), .info)

        let s = try status(SampleJSON.statusNormal)
        let top = Summary.topOnlineDevices(s, data: d)
        XCTAssertEqual(top.count, 3)
        XCTAssertEqual(top[0].name, "iPhone владельца")
        XCTAssertEqual(top[0].todayDown, 1610612736)
        XCTAssertEqual(top[1].mac, "00:00:5e:00:53:02")
        XCTAssertEqual(top[1].name, "Без имени")
        XCTAssertEqual(top[2].name, "tv-living")
        XCTAssertEqual(Summary.topOnlineDevices(s, data: nil, limit: 1).map { $0.name }, ["iPhone"])
    }

    func testOfflineBanner() throws {
        let d = try decodeJSON(DataResponse.self, SampleJSON.dataDayOffline)
        XCTAssertEqual(OfflineBanner.line(data: d, now: nowT), "Не на связи с 14:04 · уже 12\u{00A0}мин · последний ответ 14:03")
        let e = try decodeJSON(DataResponse.self, SampleJSON.dataDayEmpty)
        XCTAssertEqual(OfflineBanner.line(data: e, now: nowT), "Сервер не получает ответа от роутера")
        XCTAssertEqual(OfflineBanner.line(data: nil, now: nowT), "Сервер не получает ответа от роутера")
        var same = d
        same.offlineSince = nil
        XCTAssertEqual(OfflineBanner.line(data: same, now: nowT), "Не на связи с 14:03 · уже 13\u{00A0}мин")
    }

    func testChart() throws {
        let d = try decodeJSON(DataResponse.self, SampleJSON.dataDay)
        let c = Summary.chart(points: d.points, now: nowT)
        XCTAssertFalse(c.isEmpty)
        XCTAssertEqual(c.to, SampleJSON.now)
        XCTAssertEqual(c.from, SampleJSON.now - 86400)
        XCTAssertEqual(c.segments, [[ChartSample(ts: 1791886320, ms: 47)], [ChartSample(ts: 1791886500, ms: 52)]])
        XCTAssertEqual(c.failMarks, [1791886380])
        XCTAssertEqual(c.offlineBands, [1791886440])
        XCTAssertEqual(c.yMax, 150 * 1.15, accuracy: 0.0001)

        let gap = [
            DataPoint(ts: SampleJSON.now - 3000, ms: 40),
            DataPoint(ts: SampleJSON.now - 2940, ms: 200),
            DataPoint(ts: SampleJSON.now - 2000, ms: 45),
            DataPoint(ts: SampleJSON.now - 90000, ms: 999)
        ]
        let g = Summary.chart(points: gap, now: nowT)
        XCTAssertEqual(g.segments.count, 2)
        XCTAssertEqual(g.segments[0].count, 2)
        XCTAssertEqual(g.yMax, 230, accuracy: 0.0001)

        let empty = Summary.chart(points: [], now: nowT)
        XCTAssertTrue(empty.isEmpty)
        XCTAssertEqual(Summary.emptyChart, "данных за этот период пока нет")

        let facts = Summary.statsFacts(d.stats)
        XCTAssertEqual(facts.map { $0.value }, ["50\u{00A0}мс", "47\u{00A0}мс", "52\u{00A0}мс", "1", "1\u{00A0}мин"])
        let emptyFacts = Summary.statsFacts(try decodeJSON(DataResponse.self, SampleJSON.dataDayEmpty).stats)
        XCTAssertEqual(emptyFacts.map { $0.value }, ["—", "—", "—", "0", "0\u{00A0}мин"])
    }

    func testUpdatedLabelAndExpiry() throws {
        XCTAssertNil(Summary.updatedLabel(lastSuccess: nil, now: nowT))
        XCTAssertEqual(Summary.updatedLabel(lastSuccess: nowT - 12, now: nowT), "обновлено 12\u{00A0}сек назад")

        let me = try decodeJSON(MeResponse.self, SampleJSON.meExpiring)
        XCTAssertEqual(
            ExpiryNotice.loginWarning(hardExpires: me.device.hardExpires, now: TimeInterval(me.now)),
            "Вход действует до 24 октября. Потом нужно будет войти заново: пароль и число в Telegram."
        )
        let fresh = try decodeJSON(MeResponse.self, SampleJSON.me)
        XCTAssertNil(ExpiryNotice.loginWarning(hardExpires: fresh.device.hardExpires, now: TimeInterval(fresh.now)))
        XCTAssertEqual(ExpiryNotice.loginUntil(expires: fresh.device.expires), "Вход до 11 января")
        XCTAssertEqual(ExpiryNotice.notLongerThan(hardExpires: fresh.device.hardExpires), "Не дольше 13 октября")

        let build = SampleJSON.now - 80 * 86400
        XCTAssertNotNil(ExpiryNotice.buildWarning(buildDate: build, now: nowT))
        XCTAssertNil(ExpiryNotice.buildWarning(buildDate: SampleJSON.now, now: nowT))
        XCTAssertEqual(ExpiryNotice.buildValidUntil(buildDate: SampleJSON.now), "Сборка действует до 11 января")

        var session = SessionInfo(deviceID: "a", expires: 1, hardExpires: 2)
        session.update(from: fresh)
        XCTAssertEqual(session, SessionInfo(deviceID: "49139e3a1db5a6ac", expires: 1799662560, hardExpires: 1823422560))
    }

    func testAftermath() {
        let r = ActionAftermath.after(.restart)
        XCTAssertEqual(r.quietWindow, 15)
        XCTAssertEqual(r.rereadStatusAfter, 15)
        XCTAssertEqual(r.banner, "VPN перезапускается…")
        XCTAssertEqual(r.disabledButtons, [.check, .restartVPN, .updateSubs, .reboot])
        let u = ActionAftermath.after(.update)
        XCTAssertEqual(u.quietWindow, 0)
        XCTAssertEqual(u.rereadStatusAfter, 60)
        XCTAssertEqual(u.disabledButtons, [.restartVPN, .updateSubs])
        let b = ActionAftermath.after(.reboot)
        XCTAssertEqual(b.quietWindow, 150)
        XCTAssertTrue(b.disabledButtons.contains(.led))
        XCTAssertEqual(ActionAftermath.after(.ledset(on: true)).toast, "Подсветка роутера включена.")
        XCTAssertEqual(ActionAftermath.after(.ledset(on: false)).toast, "Подсветка роутера выключена.")
        XCTAssertEqual(ActionAftermath.after(.ping).toast, "Проверка серверов завершена.")
    }
}
