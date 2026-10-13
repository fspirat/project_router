import Foundation

// Connection history chart for 24 h / 7 d / 30 d (contract-stage4 §5.1.6), port of app.js renderChart / chartTip.
// Day points are raw minutes `[ts, ms]`; week/month points are buckets `[mid, value, fails, off]`.

/// A VPN-failure bar at the bottom of the chart.
public struct ChartFailMark: Equatable, Sendable {
    /// x (clamped to the domain).
    public var ts: Int
    /// `true` = the point itself is a failure (value 0): taller bar. `false` = an ok bucket with `fails > 0`: short bar.
    public var isTall: Bool
}

/// A full-height «router offline» band.
public struct ChartBand: Equatable, Sendable {
    public var from: Int
    public var to: Int
}

/// The tooltip under a finger (app.js:361-379).
public struct ChartTooltip: Equatable, Sendable {
    /// The point's own ts (bucket mid).
    public var ts: Int
    /// «сегодня 14:10» or, for buckets, «сегодня 12:00–12:30».
    public var time: String
    /// «48 мс», «48 мс в среднем · сбоев VPN: 2», «сбой VPN», «нет ответа», «роутер не на связи».
    public var value: String
    public var tone: Tone
    /// The y value for the dot (`nil` when not ok).
    public var ms: Int?
}

/// One chart («Связь» or a service).
public struct HistoryChart: Equatable, Sendable {
    public enum Series: Equatable, Sendable {
        /// «Связь».
        case connection
        /// A service from `tpoints`.
        case service(String)
    }

    public var series: Series
    public var range: DataRange
    /// Bucket width (0 for raw day points).
    public var step: Int
    /// x-domain `[now − span, now]`.
    public var from: Int
    public var to: Int
    /// y-domain `0 … max(150, max ok) × 1.15`.
    public var yMax: Double
    /// Line segments (with an area for «Связь»); a one-point segment is drawn as a 2 pt dot.
    /// Sample ts are clamped to `to` (a current bucket's mid may be after now).
    public var segments: [[ChartSample]]
    public var failMarks: [ChartFailMark]
    /// Offline bands (only «Связь»): width `step` (or 300 s for day points), centred, clamped to the domain.
    public var offlineBands: [ChartBand]
    /// The points inside the window (unclamped), for the tooltip.
    public var points: [DataPoint]
    public var isEmpty: Bool
    /// «Связь за 7 дней» / «YouTube за 24 часа».
    public var title: String
    /// «шкала до 173 мс» / «данных за этот период пока нет» / «истории пока нет — она копится на сервере».
    public var caption: String

    /// Width of a day-range offline band, seconds (app.js:329).
    public static let daySlot = 300

    /// Gap that breaks a line: `max(step, 300) × 2.5`.
    public var gapBreak: Int {
        return max(step, HistoryChart.daySlot) * 5 / 2
    }

    /// «Связь» chart. `points` = `data[range].points` (for `day` without data: `status.history`).
    public static func connection(points: [DataPoint], range: DataRange, step: Int? = nil, now: TimeInterval) -> HistoryChart {
        return build(series: .connection, points: points, range: range, step: step ?? range.step, now: now)
    }

    /// A service chart from `data[range].tpoints[name]`.
    public static func service(_ name: String, points: [DataPoint], range: DataRange, step: Int? = nil, now: TimeInterval) -> HistoryChart {
        return build(series: .service(name), points: points, range: range, step: step ?? range.step, now: now)
    }

    /// The «Связь» points for a range: `data.points` when `data` is of that range; for `day` without data the
    /// `status.history` fallback; else `[]`.
    public static func connectionPoints(data: DataResponse?, range: DataRange, status: RouterStatus?) -> [DataPoint] {
        if let d = data, d.dataRange == range {
            return d.points
        }
        if range == .day {
            return status?.history ?? []
        }
        return []
    }

    static func build(series: Series, points: [DataPoint], range: DataRange, step: Int, now: TimeInterval) -> HistoryChart {
        let to = Int(now.rounded(.down))
        let from = to - range.span
        let pts = points.filter { $0.ts >= from }
        var maxOk = 0
        for p in pts where p.ms > maxOk {
            maxOk = p.ms
        }
        let yMax = Double(max(150, maxOk)) * 1.15
        let gap = max(step, daySlot) * 5 / 2
        let isConnection = series == .connection
        var segments: [[ChartSample]] = []
        var seg: [ChartSample] = []
        var fails: [ChartFailMark] = []
        var bands: [ChartBand] = []
        var prev: Int? = nil
        func flush() {
            if !seg.isEmpty {
                segments.append(seg)
                seg = []
            }
        }
        for p in pts {
            let x = min(p.ts, to)
            if let pr = prev, p.ts - pr > gap {
                flush()
            }
            prev = p.ts
            if p.ms > 0 {
                seg.append(ChartSample(ts: x, ms: p.ms))
                if isConnection && (p.fails ?? 0) > 0 {
                    fails.append(ChartFailMark(ts: x, isTall: false))
                }
                continue
            }
            flush()
            if p.ms < 0 && isConnection {
                let w = step > 0 ? step : daySlot
                let a = max(from, p.ts - w / 2)
                let b = min(to, p.ts + w / 2)
                if b > a {
                    bands.append(ChartBand(from: a, to: b))
                }
            } else {
                fails.append(ChartFailMark(ts: x, isTall: true))
            }
        }
        flush()
        let title: String
        let caption: String
        switch series {
        case .connection:
            title = "Связь за " + range.title
            caption = pts.isEmpty ? Summary.emptyChart : "шкала до \(Fmt.jsRound(yMax))" + Fmt.nbsp + "мс"
        case .service(let name):
            title = name + " за " + range.title
            let anyOk = pts.contains { $0.ms > 0 }
            caption = anyOk ? "шкала до \(Fmt.jsRound(yMax))" + Fmt.nbsp + "мс" : "истории пока нет — она копится на сервере"
        }
        return HistoryChart(
            series: series, range: range, step: step, from: from, to: to, yMax: yMax,
            segments: segments, failMarks: fails, offlineBands: bands, points: pts,
            isEmpty: pts.isEmpty, title: title, caption: caption
        )
    }

    /// Tooltip for the nearest point to `t` (unix seconds); `nil` when farther than `max(step, 300) × 1.5`.
    public func tooltip(at t: TimeInterval, now: TimeInterval) -> ChartTooltip? {
        var best: DataPoint? = nil
        var dist = Double.infinity
        for p in points {
            let d = abs(Double(p.ts) - t)
            if d < dist {
                dist = d
                best = p
            }
        }
        guard let p = best, dist <= Double(max(step, HistoryChart.daySlot)) * 1.5 else {
            return nil
        }
        let time: String
        if step > 0 {
            time = Fmt.when(p.ts - step / 2, now: now) + "–" + Fmt.hourMinute(p.ts + step / 2)
        } else {
            time = Fmt.when(p.ts, now: now)
        }
        let value: String
        let tone: Tone
        if p.ms > 0 {
            var v = Fmt.ms(p.ms)
            if step > 0 {
                v += " в среднем"
            }
            if series == .connection, let f = p.fails, f > 0 {
                v += " · сбоев VPN: \(f)"
            }
            value = v
            tone = Fmt.msTone(p.ms)
        } else if p.ms < 0 {
            value = "роутер не на связи"
            tone = .err
        } else {
            value = series == .connection ? "сбой VPN" : "нет ответа"
            tone = .err
        }
        return ChartTooltip(ts: p.ts, time: time, value: value, tone: tone, ms: p.ms > 0 ? p.ms : nil)
    }

    /// Stats row. «Связь»: from `data.stats` when given (counts raw minutes), else computed from the points
    /// («Без связи» «—»). Service: «Средняя», «Лучшая», «Худшая» of ok values, «Не ответил» «N раз».
    public func statsFacts(_ stats: DataStats? = nil) -> [Fact] {
        let ok = points.filter { $0.ms > 0 }.map { $0.ms }
        func msText(_ v: Int?) -> String {
            guard let v = v, v > 0 else {
                return "—"
            }
            return Fmt.ms(v)
        }
        let avg: Int? = ok.isEmpty ? nil : Fmt.jsRound(Double(ok.reduce(0, +)) / Double(ok.count))
        switch series {
        case .connection:
            if let st = stats {
                return [
                    Fact(label: "Средняя", value: msText(st.avg)),
                    Fact(label: "Лучшая", value: msText(st.min)),
                    Fact(label: "Худшая", value: msText(st.max)),
                    Fact(label: "Сбоев", value: "\(st.fails)"),
                    Fact(label: "Без связи", value: Fmt.minutes(st.offlineMin))
                ]
            }
            return [
                Fact(label: "Средняя", value: msText(avg)),
                Fact(label: "Лучшая", value: msText(ok.min())),
                Fact(label: "Худшая", value: msText(ok.max())),
                Fact(label: "Сбоев", value: "\(points.filter { $0.ms == 0 }.count)"),
                Fact(label: "Без связи", value: "—")
            ]
        case .service:
            return [
                Fact(label: "Средняя", value: msText(avg)),
                Fact(label: "Лучшая", value: msText(ok.min())),
                Fact(label: "Худшая", value: msText(ok.max())),
                Fact(label: "Не ответил", value: "\(points.filter { $0.ms <= 0 }.count)" + Fmt.nbsp + "раз")
            ]
        }
    }

    /// Series chips: «Связь» + one per service; a chosen service that disappeared → `.connection`.
    public static func validSeries(_ chosen: Series, services: [ServiceRef]) -> Series {
        if case .service(let name) = chosen, !services.contains(where: { $0.name == name }) {
            return .connection
        }
        return chosen
    }
}
