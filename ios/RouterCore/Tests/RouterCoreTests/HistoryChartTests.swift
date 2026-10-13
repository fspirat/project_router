import Foundation
import XCTest
@testable import RouterCore

/// Connection history chart for 24 h / 7 d / 30 d (contract-stage4 §5.1.6, §10.2, §10.3).
final class HistoryChartTests: XCTestCase {

    func testWeek() throws {
        let d = try decodeJSON(DataResponse.self, SampleJSON.dataWeek)
        let c = HistoryChart.connection(points: d.points, range: .week, step: d.step, now: nowT)
        XCTAssertEqual(c.from, 1791886560 - 604800)
        XCTAssertEqual(c.to, 1791886560)
        XCTAssertEqual(c.step, 1800)
        XCTAssertEqual(c.segments.map { $0.map { $0.ms } }, [[52, 49], [50, 47, 48, 50]])
        XCTAssertEqual(c.failMarks, [ChartFailMark(ts: 1791875700, isTall: false), ChartFailMark(ts: 1791877500, isTall: true)])
        XCTAssertEqual(c.offlineBands, [ChartBand(from: 1791878400, to: 1791880200)])
        XCTAssertEqual(c.yMax, 172.5, accuracy: 0.0001)
        XCTAssertEqual(c.caption, "шкала до 173\u{00A0}мс")
        XCTAssertEqual(c.title, "Связь за 7\u{00A0}дней")
        XCTAssertFalse(c.isEmpty)
        XCTAssertEqual(c.gapBreak, 4500)
        XCTAssertEqual(c.statsFacts(d.stats).map { $0.value }, ["50\u{00A0}мс", "38\u{00A0}мс", "71\u{00A0}мс", "3", "32\u{00A0}мин"])

        let off = try XCTUnwrap(c.tooltip(at: 1791879300, now: nowT))
        XCTAssertEqual(off.time, "сегодня 12:00–12:30")
        XCTAssertEqual(off.value, "роутер не на связи")
        XCTAssertEqual(off.tone, .err)
        XCTAssertNil(off.ms)
        let failing = try XCTUnwrap(c.tooltip(at: 1791875800, now: nowT))
        XCTAssertEqual(failing.value, "49\u{00A0}мс в среднем · сбоев VPN: 1")
        XCTAssertEqual(failing.ms, 49)
        XCTAssertEqual(try XCTUnwrap(c.tooltip(at: 1791877500, now: nowT)).value, "сбой VPN")
        XCTAssertNil(c.tooltip(at: 1791873900 - 2701, now: nowT), "farther than 1.5 steps")
        XCTAssertNotNil(c.tooltip(at: 1791873900 - 2700, now: nowT))
    }

    func testMonthClipsTheCurrentBucket() throws {
        let d = try decodeJSON(DataResponse.self, SampleJSON.dataMonth)
        let c = HistoryChart.connection(points: d.points, range: .month, now: nowT)
        XCTAssertEqual(c.step, 7200)
        XCTAssertEqual(c.segments.map { $0.map { $0.ts } }, [[1791867600, 1791874800], [1791886560]], "mid after now is drawn at now")
        XCTAssertEqual(c.failMarks, [ChartFailMark(ts: 1791874800, isTall: false), ChartFailMark(ts: 1791882000, isTall: true)])
        XCTAssertEqual(c.offlineBands, [])
        XCTAssertEqual(c.points.last?.ts, 1791889200, "tooltips keep the real mid")
        let t = try XCTUnwrap(c.tooltip(at: nowT, now: nowT))
        XCTAssertEqual(t.time, "сегодня 14:00–16:00")
        XCTAssertEqual(t.value, "50\u{00A0}мс в среднем")
        XCTAssertEqual(c.title, "Связь за 30\u{00A0}дней")
    }

    func testDayRawPointsGapsAndBands() {
        let now = nowT
        let t0 = 1791886560 - 3600
        let pts = [
            DataPoint(ts: 1791886560 - 90000, ms: 99),   // before the window: dropped
            DataPoint(ts: t0, ms: 40),
            DataPoint(ts: t0 + 60, ms: 42),
            DataPoint(ts: t0 + 1000, ms: 41),          // gap 940 s > 750 → new segment
            DataPoint(ts: t0 + 1060, ms: -1),          // offline band 300 s
            DataPoint(ts: t0 + 1120, ms: 0),           // VPN failure
            DataPoint(ts: t0 + 1180, ms: 400)
        ]
        let c = HistoryChart.connection(points: pts, range: .day, now: now)
        XCTAssertEqual(c.step, 0)
        XCTAssertEqual(c.gapBreak, 750)
        XCTAssertEqual(c.points.count, 6)
        XCTAssertEqual(c.segments.map { $0.map { $0.ms } }, [[40, 42], [41], [400]])
        XCTAssertEqual(c.offlineBands, [ChartBand(from: t0 + 910, to: t0 + 1210)])
        XCTAssertEqual(c.failMarks, [ChartFailMark(ts: t0 + 1120, isTall: true)])
        XCTAssertEqual(c.yMax, 460, accuracy: 0.0001)
        XCTAssertEqual(c.caption, "шкала до 460\u{00A0}мс")
        XCTAssertEqual(c.title, "Связь за 24\u{00A0}часа")
        let tip = c.tooltip(at: Double(t0 + 60), now: now)
        XCTAssertEqual(tip?.time, "сегодня 13:17")
        XCTAssertEqual(tip?.value, "42\u{00A0}мс")
        XCTAssertNil(c.tooltip(at: Double(t0 - 451), now: now))
        // computed stats when /data is missing
        XCTAssertEqual(c.statsFacts().map { $0.value }, ["131\u{00A0}мс", "40\u{00A0}мс", "400\u{00A0}мс", "1", "—"])
        // an offline band is clamped to the window
        let edge = HistoryChart.connection(points: [DataPoint(ts: 1791886560 - 100, ms: -1)], range: .day, now: now)
        XCTAssertEqual(edge.offlineBands, [ChartBand(from: 1791886560 - 250, to: 1791886560)])
    }

    func testEmptyAndFallbackPoints() throws {
        let e = HistoryChart.connection(points: [], range: .week, now: nowT)
        XCTAssertTrue(e.isEmpty)
        XCTAssertEqual(e.caption, "данных за этот период пока нет")
        XCTAssertEqual(e.yMax, 172.5, accuracy: 0.0001)
        let s = try decodeJSON(RouterStatus.self, SampleJSON.statusStage4)
        let week = try decodeJSON(DataResponse.self, SampleJSON.dataWeek)
        XCTAssertEqual(HistoryChart.connectionPoints(data: nil, range: .day, status: s), s.history)
        XCTAssertEqual(HistoryChart.connectionPoints(data: nil, range: .week, status: s), [])
        XCTAssertEqual(HistoryChart.connectionPoints(data: week, range: .week, status: s), week.points)
        XCTAssertEqual(HistoryChart.connectionPoints(data: week, range: .day, status: s), s.history, "data of another range is not used")
    }

    func testServiceSeries() throws {
        let d = try decodeJSON(DataResponse.self, SampleJSON.dataWeek)
        let yt = HistoryChart.service("YouTube", points: d.tpoints["YouTube"] ?? [], range: .week, now: nowT)
        XCTAssertEqual(yt.title, "YouTube за 7\u{00A0}дней")
        XCTAssertEqual(yt.segments.map { $0.map { $0.ms } }, [[61], [58]])
        XCTAssertEqual(yt.failMarks, [ChartFailMark(ts: 1791884700, isTall: true)])
        XCTAssertEqual(yt.offlineBands, [])
        XCTAssertEqual(yt.caption, "шкала до 173\u{00A0}мс")
        XCTAssertEqual(yt.statsFacts().map { $0.label }, ["Средняя", "Лучшая", "Худшая", "Не ответил"])
        XCTAssertEqual(yt.statsFacts().map { $0.value }, ["60\u{00A0}мс", "58\u{00A0}мс", "61\u{00A0}мс", "1\u{00A0}раз"])
        XCTAssertEqual(yt.tooltip(at: 1791884700, now: nowT)?.value, "нет ответа")
        let discord = HistoryChart.service("Discord", points: d.tpoints["Discord"] ?? [], range: .week, now: nowT)
        XCTAssertEqual(discord.caption, "истории пока нет — она копится на сервере")
        XCTAssertEqual(discord.statsFacts().map { $0.value }, ["—", "—", "—", "1\u{00A0}раз"])
        let services = [ServiceRef(name: "YouTube", kind: "web", host: "www.youtube.com")]
        XCTAssertEqual(HistoryChart.validSeries(.service("YouTube"), services: services), .service("YouTube"))
        XCTAssertEqual(HistoryChart.validSeries(.service("Discord"), services: services), .connection)
        XCTAssertEqual(HistoryChart.validSeries(.connection, services: []), .connection)
    }
}
