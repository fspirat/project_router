import Foundation
import XCTest
@testable import RouterCore

/// Stage 4 formatting (contract-stage4 §7, §9): decimal comma, NBSP before units, new helpers.
final class FormatStage4Tests: XCTestCase {

    func testDecimalCommaAndNBSP() throws {
        XCTAssertEqual(Fmt.nbsp, "\u{00A0}")
        XCTAssertEqual(Fmt.fixed1(9.24), "9,2")
        XCTAssertEqual(Fmt.fixed1(.nan), "0,0")
        XCTAssertEqual(Fmt.speed(12345678), "12,3\u{00A0}Мбит/с")
        XCTAssertEqual(Fmt.bytes(9878424780), "9,2\u{00A0}ГБ")
        XCTAssertEqual(Fmt.ms(64), "64\u{00A0}мс")
        XCTAssertFalse(Fmt.speed(18734216).contains(" "), "no breaking space inside a number with a unit")
        let s = try decodeJSON(RouterStatus.self, SampleJSON.statusStage4)
        XCTAssertEqual(Summary.onlineText(s), "4\u{00A0}в сети")
        XCTAssertEqual(Summary.meters(s.sys)[0].caption, "Средняя нагрузка 0,21 0,17 0,15 · ядер: 2")
        let line = try XCTUnwrap(Summary.subscriptionLine(s, now: nowT))
        XCTAssertEqual(line.text, "«nosok» до 31 октября · осталось 17\u{00A0}дн. · израсходовано 39,2\u{00A0}ГБ из 200,0\u{00A0}ГБ")
        XCTAssertEqual(LatencyTile.title, "Проверка через VPN")
        XCTAssertEqual(LatencyTile.caption, "Задержка — как пинг: ответ сайта через VPN по уже открытому соединению. Раз в 5 минут.")
        XCTAssertEqual(LatencyTile.accessibilityLabel(value: Fmt.ms(48)), "Проверка через VPN, задержка 48\u{00A0}мс")
    }

    func testHelpers() {
        XCTAssertEqual(Fmt.loadText("0.21 0.17 0.15"), "0,21 0,17 0,15")
        XCTAssertEqual(Fmt.nodeDisplayName("  🇳🇱 Нидерланды "), "🇳🇱 Нидерланды")
        XCTAssertEqual(Fmt.sortKeyName("🇳🇱 Нидерланды"), "нидерланды")
        XCTAssertEqual(Fmt.sortKeyName("  #1 Fast "), "1 fast")
        XCTAssertEqual(Fmt.sortKeyName("fspiratNL"), "fspiratnl")
        XCTAssertEqual(Fmt.sortKeyName("🔥"), "")
        XCTAssertEqual(Fmt.flag("NL"), "🇳🇱 ")
        XCTAssertEqual(Fmt.flag("RU"), "🇷🇺 ")
        XCTAssertEqual(Fmt.flag("nl"), "")
        XCTAssertEqual(Fmt.flag("RUS"), "")
        XCTAssertEqual(Fmt.flag(""), "")
        XCTAssertEqual(Fmt.signalText(-51), "\u{2212}51\u{00A0}dBm")
        XCTAssertEqual(Fmt.signalText(0), "—")
        XCTAssertEqual(Fmt.signalText(nil), "—")
        XCTAssertEqual(Fmt.bandText("5g"), "Wi-Fi 5\u{00A0}ГГц")
        XCTAssertEqual(Fmt.bandText("6g"), "Wi-Fi 6\u{00A0}ГГц")
        XCTAssertEqual(Fmt.bandText("2g"), "Wi-Fi 2,4\u{00A0}ГГц")
        XCTAssertEqual(Fmt.bandText("wired"), "кабель")
        XCTAssertNil(Fmt.bandText(nil))
        XCTAssertNil(Fmt.bandText("lte"))
        XCTAssertEqual(Fmt.schedText("2300-0700"), "23:00–07:00")
        XCTAssertEqual(Fmt.schedText("oops"), "oops")
        XCTAssertEqual(Fmt.seenText(0, now: nowT), "—")
        XCTAssertEqual(Fmt.seenText(1791886500, now: nowT), "1\u{00A0}мин назад")
        XCTAssertEqual(Fmt.seenText(1791886560 - 3599, now: nowT), "60\u{00A0}мин назад")
        XCTAssertEqual(Fmt.seenText(1791886560 - 3600, now: nowT), "сегодня 13:16")
        XCTAssertEqual(Fmt.seenText(1791713760, now: nowT), "11.10 14:16")
        XCTAssertEqual(Fmt.osText("18.1"), "iOS 18.1")
        XCTAssertEqual(Fmt.osText("iOS 26.0"), "iOS 26.0")
        XCTAssertEqual(Fmt.osText(""), "")
        XCTAssertEqual(Fmt.vdsMem(total: 2014084, avail: 1302500), "35% из 1,9\u{00A0}ГБ")
        XCTAssertEqual(Fmt.vdsMem(total: 0, avail: 0), "0% из 0,0\u{00A0}ГБ")
        XCTAssertEqual(Fmt.count(2, "подписка", "подписки", "подписок"), "2\u{00A0}подписки")
        XCTAssertEqual(Fmt.count(14, "сервер", "сервера", "серверов"), "14\u{00A0}серверов")
        XCTAssertEqual(Fmt.count(21, "запись", "записи", "записей"), "21\u{00A0}запись")
    }

    func testDayLabel() {
        let midnight = 1791835200
        XCTAssertEqual(Fmt.dayLabel(midnight, now: nowT), "Сегодня")
        XCTAssertEqual(Fmt.dayLabel(midnight - 1, now: nowT), "Вчера")
        XCTAssertEqual(Fmt.dayLabel(midnight - 86400, now: nowT), "Вчера")
        XCTAssertEqual(Fmt.dayLabel(midnight - 86401, now: nowT), "11 октября")
        XCTAssertEqual(Fmt.dayLabel(1791700000, now: nowT), "11 октября")
        XCTAssertEqual(Fmt.dayLabel(1767211200, now: nowT), "1 января")      // 01.01.2026 00:00 Samara
        XCTAssertEqual(Fmt.dayLabel(1767211199, now: nowT), "31 декабря 2025")
        XCTAssertEqual(Fmt.dayLabel(1767211200 + 5, now: 1767211200 + 10), "Сегодня")
        XCTAssertEqual(Fmt.dayLabel(1767211199, now: 1767211200 + 10), "Вчера", "yesterday across the new year")
    }

    func testEventDisplayText() {
        XCTAssertEqual(Fmt.eventDisplayText("Автопереключение: fspiratDE -> fspiratNL 41ms"), "Автопереключение: fspiratDE → fspiratNL 41\u{00A0}мс")
        XCTAssertEqual(Fmt.eventDisplayText("Сервер выбран вручную: _direct"), "Сервер выбран вручную: Напрямую (без VPN)")
        XCTAssertEqual(Fmt.eventDisplayText("41msx и 12 ms"), "41msx и 12 ms")
        XCTAssertEqual(Fmt.eventDisplayText("Перезапуск VPN"), "Перезапуск VPN")
    }
}
