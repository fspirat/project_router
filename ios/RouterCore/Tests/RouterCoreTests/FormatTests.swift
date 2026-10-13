import Foundation
import XCTest
@testable import RouterCore

final class FormatTests: XCTestCase {

    func testSpeed() {
        XCTAssertEqual(Fmt.speed(18734216), "18.7 Мбит/с")
        XCTAssertEqual(Fmt.speed(123456789), "123 Мбит/с")
        XCTAssertEqual(Fmt.speed(1203448), "1.2 Мбит/с")
        XCTAssertEqual(Fmt.speed(640000), "640 кбит/с")
        XCTAssertEqual(Fmt.speed(0), "0 кбит/с")
        XCTAssertEqual(Fmt.speed(1000000), "1.0 Мбит/с")
        XCTAssertEqual(Fmt.speed(1500), "2 кбит/с")
    }

    func testMBAndBytes() {
        XCTAssertEqual(Fmt.mb(123792), "121 МБ")
        XCTAssertEqual(Fmt.mb(245632), "240 МБ")
        XCTAssertEqual(Fmt.mb(3460), "3.4 МБ")
        XCTAssertEqual(Fmt.mb(2097152), "2.0 ГБ")
        XCTAssertEqual(Fmt.mb(kib: 31544), "31 МБ")
        XCTAssertEqual(Fmt.bytes(40802189312), "38.0 ГБ")
        XCTAssertEqual(Fmt.bytes(1621098496), "1.5 ГБ")
        XCTAssertEqual(Fmt.bytes(53477376), "51 МБ")
        XCTAssertEqual(Fmt.bytes(5000000), "4.8 МБ")
        XCTAssertEqual(Fmt.bytes(0), "0.0 МБ")
        XCTAssertEqual(Fmt.bytes(96385412736), "89.8 ГБ")
        XCTAssertEqual(Fmt.bytes(7346121904), "6.8 ГБ")
        XCTAssertEqual(Fmt.bytes(214748364800), "200.0 ГБ")
    }

    func testMsAndLevels() {
        XCTAssertEqual(Fmt.ms(48), "48 мс")
        XCTAssertEqual(Fmt.msTone(48), .ok)
        XCTAssertEqual(Fmt.msTone(119), .ok)
        XCTAssertEqual(Fmt.msTone(120), .warn)
        XCTAssertEqual(Fmt.msTone(180), .warn)
        XCTAssertEqual(Fmt.msTone(250), .err)
        XCTAssertEqual(Fmt.msTone(300), .err)
        XCTAssertEqual(Fmt.pingLevel(nil), 0)
        XCTAssertEqual(Fmt.pingLevel(0), 0)
        XCTAssertEqual(Fmt.pingLevel(-1), 0)
        XCTAssertEqual(Fmt.pingLevel(59), 5)
        XCTAssertEqual(Fmt.pingLevel(60), 4)
        XCTAssertEqual(Fmt.pingLevel(119), 4)
        XCTAssertEqual(Fmt.pingLevel(120), 3)
        XCTAssertEqual(Fmt.pingLevel(249), 3)
        XCTAssertEqual(Fmt.pingLevel(250), 2)
        XCTAssertEqual(Fmt.pingLevel(399), 2)
        XCTAssertEqual(Fmt.pingLevel(400), 1)
        XCTAssertEqual(Fmt.percent(50), "50%")
        XCTAssertEqual(Fmt.temperature(nil), "нет датчика")
        XCTAssertEqual(Fmt.temperature(51), "51 °C")
    }

    func testRounding() {
        XCTAssertEqual(Fmt.jsRound(2.5), 3)
        XCTAssertEqual(Fmt.jsRound(-2.5), -2)
        XCTAssertEqual(Fmt.jsRound(0.49), 0)
        XCTAssertEqual(Fmt.fixed1(0.05), "0.1")
        XCTAssertEqual(Fmt.fixed1(39.2005), "39.2")
        XCTAssertEqual(Fmt.fixed1(-1.25), "-1.3")
        XCTAssertEqual(Fmt.fixed0(122.5), "123")
    }

    func testAgoAndUpdated() {
        XCTAssertEqual(Fmt.ago(1791886200, now: nowT), "6 мин назад")
        XCTAssertEqual(Fmt.ago(1791886530, now: nowT), "только что")
        XCTAssertEqual(Fmt.ago(1791886600, now: nowT), "только что")
        XCTAssertEqual(Fmt.ago(1791886560 - 7200, now: nowT), "2 ч назад")
        XCTAssertEqual(Fmt.updatedLabel(secondsAgo: 0), "обновлено только что")
        XCTAssertEqual(Fmt.updatedLabel(secondsAgo: 4), "обновлено только что")
        XCTAssertEqual(Fmt.updatedLabel(secondsAgo: 5), "обновлено 5 сек назад")
        XCTAssertEqual(Fmt.updatedLabel(secondsAgo: 59), "обновлено 59 сек назад")
        XCTAssertEqual(Fmt.updatedLabel(secondsAgo: 90), "обновлено 2 мин назад")
    }

    func testUptimeAndMinutes() {
        XCTAssertEqual(Fmt.uptime(352812), "4 д 2 ч")
        XCTAssertEqual(Fmt.uptime(3700), "1 ч 1 мин")
        XCTAssertEqual(Fmt.uptime(95), "1 мин")
        XCTAssertEqual(Fmt.uptime(0), "0 мин")
        XCTAssertEqual(Fmt.minutes(12), "12 мин")
        XCTAssertEqual(Fmt.minutes(75), "1 ч 15 мин")
        XCTAssertEqual(Fmt.minutes(120), "2 ч")
        XCTAssertEqual(Fmt.minutes(1500), "1 д 1 ч")
        XCTAssertEqual(Fmt.minutes(0), "0 мин")
    }

    func testSamaraDates() {
        let t = Fmt.localTime(SampleJSON.now)
        XCTAssertEqual(t.year, 2026)
        XCTAssertEqual(t.month, 10)
        XCTAssertEqual(t.day, 13)
        XCTAssertEqual(t.hour, 14)
        XCTAssertEqual(t.minute, 16)
        XCTAssertEqual(Fmt.when(1791886200, now: nowT), "сегодня 14:10")
        XCTAssertEqual(Fmt.when(1791870840, now: nowT), "сегодня 09:54")
        XCTAssertEqual(Fmt.when(1791886200 - 86400 * 1 - 18300, now: nowT), "вчера 09:05")
        XCTAssertEqual(Fmt.when(1791886200 - 86400 * 2, now: nowT), "11.10 14:10")
        // Samara midnight: 2026-10-13 00:00 +04 = 1791835200
        XCTAssertEqual(Fmt.when(1791835200, now: nowT), "сегодня 00:00")
        XCTAssertEqual(Fmt.when(1791835199, now: nowT), "вчера 23:59")
        XCTAssertEqual(Fmt.whenShort(1791885840, now: nowT), "14:04")
        XCTAssertEqual(Fmt.whenShort(1791835199, now: nowT), "вчера 23:59")
        XCTAssertEqual(Fmt.dayMonth(1793404800), "31 октября")
        XCTAssertEqual(Fmt.dayMonth(1792836000), "24 октября")
        XCTAssertEqual(Fmt.dayMonth(1823422560), "13 октября")
        XCTAssertEqual(Fmt.dayMonth(1799662560), "11 января")
        XCTAssertEqual(Fmt.dayMonth(951782400), "29 февраля")
        XCTAssertEqual(Fmt.hourMinute(1791885780), "14:03")
    }

    func testPlural() {
        XCTAssertEqual(Fmt.plural(1, "запись", "записи", "записей"), "запись")
        XCTAssertEqual(Fmt.plural(2, "запись", "записи", "записей"), "записи")
        XCTAssertEqual(Fmt.plural(5, "запись", "записи", "записей"), "записей")
        XCTAssertEqual(Fmt.plural(11, "запись", "записи", "записей"), "записей")
        XCTAssertEqual(Fmt.plural(12, "запись", "записи", "записей"), "записей")
        XCTAssertEqual(Fmt.plural(21, "запись", "записи", "записей"), "запись")
        XCTAssertEqual(Fmt.plural(22, "запись", "записи", "записей"), "записи")
        XCTAssertEqual(Fmt.plural(111, "запись", "записи", "записей"), "записей")
    }

    func testRetrySuffix() {
        XCTAssertEqual(Fmt.retrySuffix(2), " Повтори через 2 с.")
        XCTAssertEqual(Fmt.retrySuffix(90), " Повтори через 90 с.")
        XCTAssertEqual(Fmt.retrySuffix(91), " Повтори через 2 мин.")
        XCTAssertEqual(Fmt.retrySuffix(874), " Повтори через 15 мин.")
    }

    func testReplaceDirect() {
        XCTAssertEqual(Fmt.replaceDirect("Сервер выбран вручную: _direct"), "Сервер выбран вручную: Напрямую (без VPN)")
        XCTAssertEqual(Fmt.replaceDirect("A -> _direct 85ms"), "A -> Напрямую (без VPN) 85ms")
        XCTAssertEqual(Fmt.replaceDirect("x_direct"), "x_direct")
        XCTAssertEqual(Fmt.replaceDirect("_directly"), "_directly")
        XCTAssertEqual(Fmt.replaceDirect("_direct"), "Напрямую (без VPN)")
        XCTAssertEqual(Fmt.replaceDirect("без изменений"), "без изменений")
    }

    func testHostOf() {
        XCTAssertEqual(Fmt.hostOf("https://www.youtube.com/generate_204"), "www.youtube.com")
        XCTAssertEqual(Fmt.hostOf("HTTPS://discord.com/api/v10/gateway"), "discord.com")
        XCTAssertEqual(Fmt.hostOf("https://api.telegram.org/"), "api.telegram.org")
        XCTAssertEqual(Fmt.hostOf("mc.example.net:25565"), "mc.example.net")
        XCTAssertEqual(Fmt.hostOf("example.org"), "example.org")
    }
}
