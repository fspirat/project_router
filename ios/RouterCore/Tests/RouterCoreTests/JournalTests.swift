import Foundation
import XCTest
@testable import RouterCore

/// «Журнал» (contract-stage4 §5.5, expected values of §10.2).
final class JournalTests: XCTestCase {

    func week() throws -> DataResponse {
        return try decodeJSON(DataResponse.self, SampleJSON.dataWeek)
    }

    func testGroupingBySamaraDay() throws {
        let d = try week()
        let j = Journal.build(d.events, names: d.names, range: .week, now: nowT)
        XCTAssertEqual(j.total, 7)
        XCTAssertEqual(j.shown, 7)
        XCTAssertEqual(j.countText, "7\u{00A0}записей")
        XCTAssertNil(j.emptyText)
        XCTAssertEqual(j.notices, [])
        XCTAssertEqual(j.days.map { $0.title }, ["Сегодня", "Вчера", "11 октября", "10 октября"])
        XCTAssertEqual(j.days.map { $0.rows.count }, [3, 2, 1, 1])
        let rows = j.days.flatMap { $0.rows }
        XCTAssertEqual(rows.map { $0.time }, ["14:10", "13:30", "06:10", "19:46", "19:40", "10:26", "06:40"])
        XCTAssertEqual(rows.map { $0.chip }, ["Действие", "Действие", "Внимание", "Успех", "Ошибка", "Внимание", "Внимание"])
        XCTAssertEqual(rows.map { $0.level }, [.info, .info, .warn, .ok, .err, .warn, .warn])
        XCTAssertEqual(rows[2].text, "Автопереключение: fspiratDE → fspiratNL 41\u{00A0}мс")
        XCTAssertEqual(rows[5].text, "Новое устройство: без имени · 192.168.1.40 · кабель (00:00:5E:00:53:02)")
        XCTAssertEqual(rows.map { $0.symbol }, ["hand.tap", "arrow.counterclockwise", "arrow.triangle.2.circlepath", "wifi", "wifi.slash", "plus.circle", "power"])
        XCTAssertEqual(Set(rows.map { $0.id }).count, 7)
    }

    func testFiltersAndSearch() throws {
        let d = try week()
        let errors = Journal.build(d.events, range: .week, filter: .errors, now: nowT)
        XCTAssertEqual(errors.shown, 1)
        XCTAssertEqual(errors.countText, "найдено 1 из 7")
        XCTAssertEqual(errors.days.map { $0.title }, ["Вчера"])
        XCTAssertEqual(Journal.build(d.events, range: .week, filter: .warnings, now: nowT).shown, 3)
        let actions = Journal.build(d.events, range: .week, filter: .actions, now: nowT)
        XCTAssertEqual(actions.days.flatMap { $0.rows.map { $0.kind } }, ["manual", "restart", "online"], "Действия = info + ok")
        let vpn = Journal.build(d.events, range: .week, query: "vpn", now: nowT)
        XCTAssertEqual(vpn.days.flatMap { $0.rows.map { $0.text } }, ["Перезапуск VPN"])
        XCTAssertEqual(vpn.countText, "найдено 1 из 7")
        let byTime = Journal.build(d.events, range: .week, query: "11.10", now: nowT)
        XCTAssertEqual(byTime.shown, 1, "search also matches the formatted time")
        let yesterday = Journal.build(d.events, range: .week, query: "Вчера", now: nowT)
        XCTAssertEqual(yesterday.shown, 2)
        let none = Journal.build(d.events, range: .week, filter: .errors, query: "vpn", now: nowT)
        XCTAssertEqual(none.days, [])
        XCTAssertEqual(none.emptyText, "Таких записей нет.")
        XCTAssertEqual(none.countText, "найдено 0 из 7")
        XCTAssertEqual(JournalFilter.allCases.map { $0.title }, ["Все", "Ошибки", "Внимание", "Действия"])
    }

    func testEmptyAndNotices() throws {
        let empty = Journal.build([], range: .day, now: nowT)
        XCTAssertEqual(empty.emptyText, "Событий пока нет. Здесь появятся смены сервера, перезагрузки, сбои VPN и новые устройства.")
        XCTAssertEqual(empty.countText, "")
        XCTAssertEqual(empty.notices, [])
        let month = Journal.build([], range: .month, now: nowT)
        XCTAssertEqual(month.notices, ["За 30 дней список может быть неполным."])
        let hundred = (0..<100).map { DataEvent(ts: 1791886000 - $0 * 600, kind: "router", text: "x\($0)") }
        let full = Journal.build(hundred, range: .week, now: nowT)
        XCTAssertEqual(full.notices, ["Сервер отдаёт не больше 100 последних событий за период — более ранние сюда не попали."])
        XCTAssertEqual(full.countText, "100\u{00A0}записей")
        XCTAssertEqual(Journal.build(hundred, range: .month, now: nowT).notices.count, 2)
        XCTAssertEqual(Journal.build(Array(hundred.prefix(99)), range: .week, now: nowT).notices, [])
    }

    func testDayTitlesAcrossYearAndMidnight() {
        let midnight = 1791835200   // 13.10.2026 00:00 Samara
        let events = [
            DataEvent(ts: midnight, kind: "online", text: "a"),
            DataEvent(ts: midnight - 1, kind: "offline", text: "b"),
            DataEvent(ts: midnight - 86400 - 1, kind: "reboot", text: "c"),
            DataEvent(ts: 1760300000, kind: "manual", text: "d")
        ]
        let j = Journal.build(events, range: .month, now: nowT)
        XCTAssertEqual(j.days.map { $0.title }, ["Сегодня", "Вчера", "11 октября", "13 октября 2025"])
        XCTAssertEqual(j.days.flatMap { $0.rows.map { $0.time } }, ["00:00", "23:59", "23:59", "00:13"])
    }

    func testMACNames() {
        let names = ["00:00:5e:00:53:02": "Приставка", "00:00:5e:00:53:03": " "]
        XCTAssertEqual(
            Journal.annotateMACs("Новое устройство: без имени (00:00:5E:00:53:02)", names: names),
            "Новое устройство: без имени (00:00:5E:00:53:02 (Приставка))"
        )
        XCTAssertEqual(Journal.annotateMACs("мимо VPN: 00:00:5e:00:53:03", names: names), "мимо VPN: 00:00:5e:00:53:03", "blank names are ignored")
        XCTAssertEqual(Journal.annotateMACs("нет адресов", names: names), "нет адресов")
        XCTAssertEqual(Journal.annotateMACs("00:00:5e:00:53:02, 00:00:5e:00:53:02", names: names), "00:00:5e:00:53:02 (Приставка), 00:00:5e:00:53:02 (Приставка)")
        let e = DataEvent(ts: 1, kind: "router", text: "мимо VPN: 00:00:5e:00:53:02")
        XCTAssertEqual(Journal.displayText(e, names: names), "мимо VPN: 00:00:5e:00:53:02 (Приставка)")
        let m = DataEvent(ts: 1, kind: "manual", text: "Сервер выбран вручную: _direct 00:00:5e:00:53:02")
        XCTAssertEqual(Journal.displayText(m, names: names), "Сервер выбран вручную: Напрямую (без VPN) 00:00:5e:00:53:02", "only router/newdev texts get names")
        XCTAssertEqual(Journal.symbol(kind: "xraymem"), "memorychip")
        XCTAssertEqual(Journal.symbol(kind: "vpn_down"), "xmark.shield")
        XCTAssertEqual(Journal.symbol(kind: "something"), "circle")
    }
}
