import Foundation
import XCTest
@testable import RouterCore

/// «Устройства», the device card and the schedule (contract-stage4 §5.2, §5.3, §10.1).
final class DevicesTests: XCTestCase {

    func fixtures() throws -> (RouterStatus, DataResponse) {
        return (try decodeJSON(RouterStatus.self, SampleJSON.statusStage4), try decodeJSON(DataResponse.self, SampleJSON.dataWeek))
    }

    func testListGroups() throws {
        let (s, d) = try fixtures()
        let l = Devices.list(s.devices, names: d.names, traffic: d.traffic)
        XCTAssertEqual(l.summary, "4\u{00A0}в сети из 6")
        XCTAssertEqual(l.total, 6)
        XCTAssertEqual(l.online, 4)
        XCTAssertNil(l.emptyText)
        XCTAssertEqual(l.sections.map { $0.kind }, [.wifi5, .wifi24, .wired, .offline])
        XCTAssertEqual(l.sections.map { $0.title }, ["Wi-Fi 5\u{00A0}ГГц", "Wi-Fi 2,4\u{00A0}ГГц", "По кабелю", "Не в сети"])
        XCTAssertEqual(l.sections.map { $0.symbol }, ["wifi", "wifi", "cable.connector", "wifi.slash"])
        XCTAssertEqual(l.sections.map { $0.count }, [2, 1, 1, 2])
        XCTAssertEqual(l.sections.map { $0.isCollapsed }, [false, false, false, true])
        XCTAssertEqual(l.sections[3].header, "Не в сети: 2")
        XCTAssertEqual(l.sections[0].header, "Wi-Fi 5\u{00A0}ГГц")

        let five = l.sections[0].rows
        XCTAssertEqual(five.map { $0.title }, ["ipad", "iPhone владельца"])
        XCTAssertEqual(five[0].labels, [DeviceLabel(text: "по расписанию", tone: .err, symbol: nil)])
        XCTAssertEqual(five[0].subtitle, "192.168.1.41 · 144\u{00A0}Мбит/с")
        XCTAssertEqual(five[0].signalLevel, 1)
        XCTAssertNil(five[0].todayText)
        XCTAssertEqual(five[1].labels, [])
        XCTAssertEqual(five[1].subtitle, "192.168.1.23 · 866\u{00A0}Мбит/с", "no «скрытый MAC» because it has a name")
        XCTAssertEqual(five[1].signalLevel, 4)
        XCTAssertEqual(five[1].signalAccessibility, "Сигнал \u{2212}51\u{00A0}dBm")
        XCTAssertEqual(five[1].todayText, "↓ 1,5\u{00A0}ГБ")

        let tv = l.sections[1].rows[0]
        XCTAssertEqual(tv.title, "tv-living")
        XCTAssertEqual(tv.labels, [DeviceLabel(text: "23:00–07:00", tone: .neutral, symbol: "timer")])
        XCTAssertEqual(tv.signalLevel, 2)

        let wired = l.sections[2].rows[0]
        XCTAssertEqual(wired.title, "Без имени")
        XCTAssertFalse(wired.hasName)
        XCTAssertEqual(wired.labels, [DeviceLabel(text: "мимо VPN", tone: .info, symbol: nil)])
        XCTAssertEqual(wired.subtitle, "192.168.1.40")
        XCTAssertNil(wired.signalLevel)
        XCTAssertEqual(wired.todayText, "↓ 10\u{00A0}МБ")

        let off = l.sections[3].rows
        XCTAssertEqual(off.map { $0.title }, ["old-laptop", "Без имени"])
        XCTAssertEqual(off[0].labels.map { $0.text }, ["без интернета"])
        XCTAssertNil(off[0].signalLevel)
        XCTAssertEqual(off[1].subtitle, "192.168.1.90 · скрытый MAC")
    }

    func testFiltersAndSearch() throws {
        let (s, d) = try fixtures()
        let limited = Devices.list(s.devices, names: d.names, traffic: d.traffic, filter: .limited)
        XCTAssertEqual(limited.summary, "найдено 4 из 6")
        XCTAssertEqual(Set(limited.sections.flatMap { $0.rows.map { $0.mac } }), ["00:00:5e:00:53:05", "00:00:5e:00:53:02", "00:00:5e:00:53:03", "00:00:5e:00:53:04"])
        let online = Devices.list(s.devices, names: d.names, traffic: d.traffic, filter: .online)
        XCTAssertEqual(online.sections.map { $0.kind }, [.wifi5, .wifi24, .wired])
        let offline = Devices.list(s.devices, names: d.names, traffic: d.traffic, filter: .offline)
        XCTAssertEqual(offline.sections.map { $0.kind }, [.offline])
        XCTAssertFalse(offline.sections[0].isCollapsed, "expanded with the «Не в сети» filter")
        XCTAssertEqual(offline.sections[0].header, "Не в сети")
        let ip = Devices.list(s.devices, names: d.names, traffic: d.traffic, query: "192.168.1.4")
        XCTAssertEqual(ip.summary, "найдено 2 из 6")
        let byOwnName = Devices.list(s.devices, names: d.names, traffic: d.traffic, query: " ВЛАДЕЛЬЦА ")
        XCTAssertEqual(byOwnName.sections.flatMap { $0.rows.map { $0.title } }, ["iPhone владельца"])
        let byMAC = Devices.list(s.devices, names: d.names, traffic: d.traffic, query: "ae:00")
        XCTAssertEqual(byMAC.sections.map { $0.kind }, [.offline])
        XCTAssertFalse(byMAC.sections[0].isCollapsed, "expanded while searching")
        let none = Devices.list(s.devices, names: d.names, traffic: d.traffic, query: "zzz")
        XCTAssertEqual(none.sections, [])
        XCTAssertEqual(none.emptyText, "Ничего не найдено — измени поиск или фильтр.")
        XCTAssertEqual(Devices.list([], names: [:], traffic: [:]).emptyText, "Устройства не найдены: роутер пока никому не выдал адрес.")
        XCTAssertEqual(Devices.list([], names: [:], traffic: [:]).summary, "0\u{00A0}в сети из 0")
        XCTAssertEqual(DeviceFilter.allCases.map { $0.title }, ["Все", "В сети", "Не в сети", "Ограничены"])
    }

    func testHelpers() throws {
        let (s, d) = try fixtures()
        XCTAssertEqual(Devices.displayName(s.devices[0], names: d.names), "iPhone владельца")
        XCTAssertEqual(Devices.displayName(s.devices[0], names: [:]), "iPhone")
        XCTAssertEqual(Devices.displayName(s.devices[1], names: ["00:00:5e:00:53:02": "  "]), "")
        XCTAssertTrue(Devices.isHiddenMAC("5a:00:5e:00:53:01"))
        XCTAssertTrue(Devices.isHiddenMAC("AE:00:5E:00:53:06"))
        XCTAssertTrue(Devices.isHiddenMAC("x2:00"))
        XCTAssertTrue(Devices.isHiddenMAC("06:00:00:00:00:00"))
        XCTAssertFalse(Devices.isHiddenMAC("00:00:5e:00:53:02"))
        XCTAssertFalse(Devices.isHiddenMAC("01:00:5e:00:53:02"))
        XCTAssertEqual(Devices.signalLevel(nil), 0)
        XCTAssertEqual(Devices.signalLevel(0), 0)
        XCTAssertEqual(Devices.signalLevel(-54), 4)
        XCTAssertEqual(Devices.signalLevel(-55), 3)
        XCTAssertEqual(Devices.signalLevel(-64), 3)
        XCTAssertEqual(Devices.signalLevel(-65), 2)
        XCTAssertEqual(Devices.signalLevel(-74), 2)
        XCTAssertEqual(Devices.signalLevel(-75), 1)
        XCTAssertEqual(Devices.signalLevel(-90), 1)
        XCTAssertTrue(Devices.isLimited(s.devices[2]), "schedule")
        XCTAssertFalse(Devices.isLimited(s.devices[0]))
        // labels order: blocked first, then «мимо VPN», then the schedule
        var all = s.devices[2]
        all.blocked = true
        all.direct = true
        XCTAssertEqual(Devices.labels(all).map { $0.text }, ["без интернета", "мимо VPN", "23:00–07:00"])
    }

    func testUnnamedSortLast() {
        func dev(_ name: String, _ mac: String) -> RouterDevice {
            return RouterDevice(json: .object(["name": .string(name), "mac": .string(mac), "online": .bool(true), "band": .string("2g")]))
        }
        let list = [dev("", "00:00:5e:00:53:10"), dev("zebra", "00:00:5e:00:53:11"), dev("Apple TV", "00:00:5e:00:53:12"), dev("box 10", "00:00:5e:00:53:13"), dev("box 9", "00:00:5e:00:53:14")]
        XCTAssertEqual(Devices.sortedByName(list, names: [:]).map { $0.name }, ["Apple TV", "box 9", "box 10", "zebra", ""])
        let ru = [dev("Телевизор", "00:00:5e:00:53:20"), dev("", "00:00:5e:00:53:21"), dev("апельсин", "00:00:5e:00:53:22")]
        XCTAssertEqual(Devices.sortedByName(ru, names: ["00:00:5e:00:53:21": "Ёлка"]).map { $0.mac }, ["00:00:5e:00:53:22", "00:00:5e:00:53:21", "00:00:5e:00:53:20"])
    }

    func testNewThisWeek() throws {
        let (s, d) = try fixtures()
        let rows = Devices.newThisWeek(d.newdevs, devices: s.devices, names: d.names, now: nowT)
        XCTAssertEqual(rows, [NewDeviceRow(mac: "00:00:5e:00:53:02", ts: 1791700000, title: "Без имени", whenText: "11.10 10:26", isKnown: true)])
        let dup = [
            NewDevice(json: .object(["ts": .int(1791800000), "mac": .string("00:00:5E:00:53:99")])),
            NewDevice(json: .object(["ts": .int(1791850000), "mac": .string("00:00:5e:00:53:99")])),
            NewDevice(json: .object(["ts": .int(1791700000), "mac": .string("5a:00:5e:00:53:01")])),
            NewDevice(json: .object(["ts": .int(1791600000), "mac": .string("00:00:5e:00:53:98")]))
        ]
        let r = Devices.newThisWeek(dup, devices: s.devices, names: ["00:00:5e:00:53:98": "Гость"], now: nowT)
        XCTAssertEqual(r.map { $0.mac }, ["00:00:5e:00:53:99", "5a:00:5e:00:53:01", "00:00:5e:00:53:98"])
        XCTAssertEqual(r[0].ts, 1791850000, "the newest is kept")
        XCTAssertEqual(r[0].title, "00:00:5e:00:53:99", "lease gone and no name → the MAC")
        XCTAssertFalse(r[0].isKnown)
        XCTAssertEqual(r[0].whenText, "сегодня 04:06")
        XCTAssertEqual(r[1].title, "iPhone")
        XCTAssertEqual(r[2].title, "Гость")
        XCTAssertEqual(Devices.unseenCount(dup, seenAt: 1791790000), 1)
        XCTAssertEqual(Devices.unseenCount(dup, seenAt: 0), 3)
        XCTAssertEqual(Devices.unseenCount([], seenAt: 0), 0)
    }

    func testDetail() throws {
        let (s, d) = try fixtures()
        let phone = Devices.detail(mac: "5A:00:5E:00:53:01", device: s.devices[0], names: d.names, traffic: d.traffic)
        XCTAssertEqual(phone.mac, "5a:00:5e:00:53:01")
        XCTAssertEqual(phone.title, "iPhone владельца")
        XCTAssertEqual(phone.networkNameCaption, "Имя в сети: iPhone")
        XCTAssertTrue(phone.isKnown)
        XCTAssertEqual(phone.rows.map { $0.label }, ["Статус", "IP", "MAC", "Сигнал", "Сегодня", "За месяц", "Интернет", "Через VPN", "Расписание"])
        XCTAssertEqual(phone.rows.map { $0.value }, [
            "В сети · Wi-Fi 5\u{00A0}ГГц", "192.168.1.23", "5a:00:5e:00:53:01", "\u{2212}51\u{00A0}dBm · 866\u{00A0}Мбит/с",
            "↓ 1,5\u{00A0}ГБ · ↑ 50\u{00A0}МБ", "↓ 27,0\u{00A0}ГБ · ↑ 700\u{00A0}МБ", "Есть", "Да", "Нет"
        ])
        XCTAssertEqual(phone.rows[2].caption, "Скрытый MAC: телефон сам придумал этот адрес для приватности. Он может измениться.")
        XCTAssertEqual(phone.renamePrefill, "iPhone владельца")
        XCTAssertEqual(phone.renamePlaceholder, "iPhone")
        XCTAssertEqual(phone.blockAction, .block(mac: "5a:00:5e:00:53:01"))
        XCTAssertNil(phone.unblockAction)
        XCTAssertEqual(phone.directAction, .direct(mac: "5a:00:5e:00:53:01", on: true))
        XCTAssertEqual(phone.directButtonTitle, "Пускать мимо VPN")
        XCTAssertNil(phone.clearScheduleAction)
        XCTAssertEqual(phone.scheduleButtonTitle, "Расписание…")
        XCTAssertEqual(phone.renameAction(" Мой iPhone "), .rename(mac: "5a:00:5e:00:53:01", name: "Мой iPhone"))
        XCTAssertEqual(phone.footer, "Трафик считает сервер раз в минуту. Учитывается только обычный интернет устройства: Telegram через Cloudflare в нём не виден.")

        let tv = Devices.detail(mac: "00:00:5e:00:53:03", device: s.devices[2], names: [:], traffic: [:])
        XCTAssertEqual(tv.title, "tv-living")
        XCTAssertNil(tv.networkNameCaption)
        XCTAssertEqual(tv.scheduleButtonTitle, "Расписание: 23:00–07:00")
        XCTAssertEqual(tv.clearScheduleAction, .scheduleClear(mac: "00:00:5e:00:53:03"))
        XCTAssertEqual(tv.rows.first(where: { $0.label == "Статус" })?.value, "В сети · Wi-Fi 2,4\u{00A0}ГГц")
        XCTAssertEqual(tv.rows.first(where: { $0.label == "Расписание" })?.value, "23:00–07:00")
        XCTAssertNil(tv.rows.first(where: { $0.label == "Сегодня" }))

        let wired = Devices.detail(mac: "00:00:5e:00:53:02", device: s.devices[1], names: [:], traffic: d.traffic)
        XCTAssertEqual(wired.title, "Без имени")
        XCTAssertEqual(wired.rows.first?.value, "В сети · кабель")
        XCTAssertNil(wired.rows.first(where: { $0.label == "Сигнал" }))
        XCTAssertNil(wired.rows.first(where: { $0.label == "MAC" })?.caption)
        XCTAssertEqual(wired.rows.first(where: { $0.label == "Через VPN" })?.value, "Мимо VPN")
        XCTAssertEqual(wired.directButtonTitle, "Снова через VPN")
        XCTAssertEqual(wired.directAction, .direct(mac: "00:00:5e:00:53:02", on: false))
        XCTAssertEqual(wired.renamePlaceholder, "Имя устройства")

        let laptop = Devices.detail(mac: "00:00:5e:00:53:04", device: s.devices[4], names: [:], traffic: [:])
        XCTAssertEqual(laptop.rows.first?.value, "Не в сети")
        XCTAssertEqual(laptop.rows.first(where: { $0.label == "Интернет" })?.value, "Выключен")
        XCTAssertNil(laptop.blockAction)
        XCTAssertEqual(laptop.unblockAction, .unblock(mac: "00:00:5e:00:53:04"))

        let ipad = Devices.detail(mac: "00:00:5e:00:53:05", device: s.devices[3], names: [:], traffic: [:])
        XCTAssertEqual(ipad.rows.first(where: { $0.label == "Интернет" })?.value, "Выключен по расписанию")
        XCTAssertEqual(ipad.rows.first(where: { $0.label == "Сигнал" })?.value, "\u{2212}77\u{00A0}dBm · 144\u{00A0}Мбит/с")

        let gone = Devices.detail(mac: "00:00:5e:00:53:02", device: nil, names: ["00:00:5e:00:53:02": "Приставка"], traffic: d.traffic)
        XCTAssertFalse(gone.isKnown)
        XCTAssertEqual(gone.title, "Приставка")
        XCTAssertEqual(gone.rows.map { $0.label }, ["MAC", "Сегодня", "За месяц"])
        XCTAssertNil(gone.blockAction)
        XCTAssertNil(gone.unblockAction)
        XCTAssertNil(gone.directAction)
        XCTAssertNil(gone.clearScheduleAction)
        XCTAssertEqual(gone.renameAction(""), .rename(mac: "00:00:5e:00:53:02", name: ""))
    }

    // MARK: - Schedule

    func testScheduleParsingAndTexts() {
        let w = ScheduleWindow(sched: "2300-0700")
        XCTAssertEqual(w, ScheduleWindow(off: "2300", on: "0700"))
        XCTAssertEqual(w?.text, "23:00–07:00")
        XCTAssertEqual(w?.offText, "23:00")
        XCTAssertEqual(w?.onText, "07:00")
        XCTAssertEqual(w?.sched, "2300-0700")
        XCTAssertEqual(w?.crossesMidnight, true)
        XCTAssertEqual(w?.offHour, 23)
        XCTAssertEqual(w?.onMinute, 0)
        XCTAssertNil(ScheduleWindow(sched: "2400-0700"))
        XCTAssertNil(ScheduleWindow(sched: "23:00-07:00"))
        XCTAssertNil(ScheduleWindow(sched: "2300"))
        XCTAssertNil(ScheduleWindow(sched: "2300-0700-0800"))
        XCTAssertEqual(ScheduleWindow.initial(for: nil), ScheduleWindow(off: "2300", on: "0700"))
        XCTAssertEqual(ScheduleWindow.initial(for: "bad"), ScheduleWindow(off: "2300", on: "0700"))
        XCTAssertEqual(ScheduleWindow.initial(for: "1300-1500"), ScheduleWindow(off: "1300", on: "1500"))
        XCTAssertEqual(ScheduleWindow(offHour: 7, offMinute: 5, onHour: 23, onMinute: 59), ScheduleWindow(off: "0705", on: "2359"))
        XCTAssertEqual(ScheduleWindow.hhmm(hour: 25, minute: -3), "2300")
        XCTAssertTrue(ScheduleWindow(off: "2300", on: "0700").isValid)
        XCTAssertFalse(ScheduleWindow(off: "0700", on: "0700").isValid, "equal times are refused")
        XCTAssertTrue(ScheduleWindow(off: "0700", on: "0700").hasSameTimes)
        XCTAssertFalse(ScheduleWindow(off: "2360", on: "0700").isValid)
        XCTAssertEqual(ScheduleWindow(off: "2300", on: "0700").action(mac: "00:00:5e:00:53:03"), .schedule(mac: "00:00:5e:00:53:03", off: "2300", on: "0700"))
        XCTAssertEqual(ScheduleTexts.title("Телевизор"), "Расписание: Телевизор")
        XCTAssertEqual(ScheduleTexts.buttonTitle(sched: nil), "Расписание…")
        XCTAssertEqual(ScheduleTexts.buttonTitle(sched: "1300-1500"), "Расписание: 13:00–15:00")
        XCTAssertEqual(ScheduleTexts.sameTime, "Укажи разное время выключения и включения.")
    }

    func testScheduleActiveAcrossMidnight() {
        let w = ScheduleWindow(off: "2300", on: "0700")
        XCTAssertTrue(w.isActive(hhmm: 2300), "off is inside")
        XCTAssertTrue(w.isActive(hhmm: 2359))
        XCTAssertTrue(w.isActive(hhmm: 0))
        XCTAssertTrue(w.isActive(hhmm: 659))
        XCTAssertFalse(w.isActive(hhmm: 700), "on is outside")
        XCTAssertFalse(w.isActive(hhmm: 1200))
        XCTAssertFalse(w.isActive(hhmm: 2259))
        let day = ScheduleWindow(off: "1300", on: "1500")
        XCTAssertFalse(day.crossesMidnight)
        XCTAssertTrue(day.isActive(hhmm: 1300))
        XCTAssertTrue(day.isActive(hhmm: 1459))
        XCTAssertFalse(day.isActive(hhmm: 1500))
        XCTAssertFalse(day.isActive(hhmm: 1259))
        XCTAssertFalse(day.isActive(hhmm: 2300))
        XCTAssertFalse(ScheduleWindow(off: "0700", on: "0700").isActive(hhmm: 700), "equal times: never active")
        XCTAssertFalse(ScheduleWindow(off: "xx", on: "0700").isActive(hhmm: 100))
    }

    func testScheduleActiveInSamaraTime() {
        let midnight = 1791835200.0          // 13.10.2026 00:00 Samara
        let night = ScheduleWindow(off: "2300", on: "0700")
        XCTAssertFalse(night.isActive(now: nowT), "14:16")
        XCTAssertTrue(night.isActive(now: midnight + 23 * 3600 + 30 * 60), "23:30")
        XCTAssertTrue(night.isActive(now: midnight + 6 * 3600 + 59 * 60 + 59), "06:59:59")
        XCTAssertFalse(night.isActive(now: midnight + 7 * 3600), "07:00")
        XCTAssertTrue(night.isActive(now: midnight), "00:00")
        XCTAssertTrue(night.isActive(now: midnight - 1), "23:59:59 the day before")
        XCTAssertTrue(ScheduleWindow(off: "1300", on: "1500").isActive(now: nowT), "14:16 is inside 13:00–15:00")
        // 19:00 UTC = 23:00 Samara: the phone's own time zone does not matter
        XCTAssertTrue(night.isActive(now: midnight + 23 * 3600))
    }
}
