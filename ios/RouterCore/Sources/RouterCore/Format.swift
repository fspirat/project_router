import Foundation

/// Colour/level of a value or an item. The app maps it to the colour tokens (contract §6):
/// ok → acc / acc-tx, warn → warn, err → err, info → info, neutral → faint.
public enum Tone: String, Equatable, Sendable {
    case ok
    case warn
    case err
    case info
    case neutral
}

/// Formatting ported from `web/app.js` (contract §5). Decimal separator is "." like the web.
/// Every time is shown in Europe/Samara (router time, UTC+4, no DST).
public enum Fmt {
    /// Europe/Samara; falls back to a fixed UTC+4 if the tz database is missing.
    public static let samaraTimeZone: TimeZone = TimeZone(identifier: "Europe/Samara") ?? TimeZone(secondsFromGMT: 4 * 3600)!

    /// Genitive month names for «d MMMM».
    public static let monthsGenitive: [String] = [
        "января", "февраля", "марта", "апреля", "мая", "июня",
        "июля", "августа", "сентября", "октября", "ноября", "декабря"
    ]

    // MARK: - Numbers

    /// JS `Math.round`: half up (toward +∞).
    public static func jsRound(_ x: Double) -> Int {
        guard x.isFinite else {
            return 0
        }
        let r = (x + 0.5).rounded(.down)
        if r >= 9.0e18 {
            return Int.max
        }
        if r <= -9.0e18 {
            return Int.min
        }
        return Int(r)
    }

    /// JS `toFixed(1)` for display (half away from zero).
    public static func fixed1(_ x: Double) -> String {
        guard x.isFinite else {
            return "0.0"
        }
        let scaled = (abs(x) * 10).rounded(.toNearestOrAwayFromZero)
        guard scaled < 9.0e18 else {
            return "0.0"
        }
        let tenths = Int(scaled)
        let sign = (x < 0 && tenths != 0) ? "-" : ""
        return "\(sign)\(tenths / 10).\(tenths % 10)"
    }

    /// JS `toFixed(0)`.
    public static func fixed0(_ x: Double) -> String {
        guard x.isFinite else {
            return "0"
        }
        let scaled = abs(x).rounded(.toNearestOrAwayFromZero)
        guard scaled < 9.0e18 else {
            return "0"
        }
        let n = Int(scaled)
        let sign = (x < 0 && n != 0) ? "-" : ""
        return "\(sign)\(n)"
    }

    /// Bits per second → «18.7 Мбит/с», «123 Мбит/с», «640 кбит/с».
    public static func speed(_ bitsPerSecond: Int) -> String {
        let b = Double(bitsPerSecond)
        if b >= 1e6 {
            let v = b / 1e6
            return (b >= 1e8 ? fixed0(v) : fixed1(v)) + " Мбит/с"
        }
        return "\(jsRound(b / 1e3)) кбит/с"
    }

    /// KiB → «121 МБ», «3.4 МБ», «2.0 ГБ».
    public static func mb(_ kib: Double) -> String {
        if kib >= 1048576 {
            return fixed1(kib / 1048576) + " ГБ"
        }
        if kib < 10240 {
            return fixed1(kib / 1024) + " МБ"
        }
        return "\(jsRound(kib / 1024)) МБ"
    }

    /// KiB (integer) → see `mb(_: Double)`.
    public static func mb(kib: Int) -> String {
        return mb(Double(kib))
    }

    /// Bytes → `mb(bytes / 1024)`: «38.0 ГБ», «51 МБ», «0.0 МБ».
    public static func bytes(_ b: Int) -> String {
        return mb(Double(b) / 1024)
    }

    /// «48 мс».
    public static func ms(_ v: Int) -> String {
        return "\(v) мс"
    }

    /// `msCls`: < 120 ok, < 250 warn (mid), else err (slow).
    public static func msTone(_ v: Int) -> Tone {
        if v < 120 {
            return .ok
        }
        if v < 250 {
            return .warn
        }
        return .err
    }

    /// Ping bars 0–5: no answer 0; < 60 → 5; < 120 → 4; < 250 → 3; < 400 → 2; else 1.
    public static func pingLevel(_ v: Int?) -> Int {
        guard let v = v, v > 0 else {
            return 0
        }
        if v < 60 {
            return 5
        }
        if v < 120 {
            return 4
        }
        if v < 250 {
            return 3
        }
        if v < 400 {
            return 2
        }
        return 1
    }

    /// «50%».
    public static func percent(_ p: Int) -> String {
        return "\(p)%"
    }

    /// Fact «51 °C» / «нет датчика».
    public static func temperature(_ t: Int?) -> String {
        guard let t = t else {
            return "нет датчика"
        }
        return "\(t) °C"
    }

    /// `n%10==1 && n%100!=11` → one; `n%10 ∈ 2…4 && n%100 ∉ 12…14` → few; else many.
    public static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let a = abs(n)
        let d10 = a % 10
        let d100 = a % 100
        if d10 == 1 && d100 != 11 {
            return one
        }
        if d10 >= 2 && d10 <= 4 && !(d100 >= 12 && d100 <= 14) {
            return few
        }
        return many
    }

    /// « Повтори через N с.» (N ≤ 90) or « Повтори через M мин.» (M = ceil(N/60)). Starts with a space.
    public static func retrySuffix(_ seconds: Int) -> String {
        if seconds <= 90 {
            return " Повтори через \(seconds) с."
        }
        return " Повтори через \((seconds + 59) / 60) мин."
    }

    // MARK: - Durations

    /// «только что» / «N мин назад» / «N ч назад».
    public static func ago(_ ts: Int, now: TimeInterval) -> String {
        let s = max(0, jsRound(now - Double(ts)))
        if s < 60 {
            return "только что"
        }
        if s < 3600 {
            return "\(jsRound(Double(s) / 60)) мин назад"
        }
        return "\(jsRound(Double(s) / 3600)) ч назад"
    }

    /// «обновлено только что» / «обновлено N сек назад» / «обновлено N мин назад».
    public static func updatedLabel(secondsAgo: Int) -> String {
        let s = max(0, secondsAgo)
        if s < 5 {
            return "обновлено только что"
        }
        if s < 60 {
            return "обновлено \(s) сек назад"
        }
        return "обновлено \(jsRound(Double(s) / 60)) мин назад"
    }

    /// Uptime: «4 д 2 ч», «1 ч 1 мин», «1 мин».
    public static func uptime(_ seconds: Int) -> String {
        let s = max(0, seconds)
        let d = s / 86400
        let h = s % 86400 / 3600
        let m = s % 3600 / 60
        if d > 0 {
            return "\(d) д \(h) ч"
        }
        if h > 0 {
            return "\(h) ч \(m) мин"
        }
        return "\(m) мин"
    }

    /// Minutes: «12 мин», «1 ч 15 мин», «2 ч», «1 д 1 ч».
    public static func minutes(_ minutes: Int) -> String {
        let m = max(0, minutes)
        if m < 60 {
            return "\(m) мин"
        }
        if m < 1440 {
            let rest = m % 60
            return rest > 0 ? "\(m / 60) ч \(rest) мин" : "\(m / 60) ч"
        }
        return "\(m / 1440) д \(m % 1440 / 60) ч"
    }

    // MARK: - Dates (Europe/Samara)

    /// Local (Samara) calendar parts of a unix time.
    public struct LocalTime: Equatable, Sendable {
        /// Days since 1970-01-01 in local time.
        public var dayNumber: Int
        public var year: Int
        public var month: Int
        public var day: Int
        public var hour: Int
        public var minute: Int
    }

    public static func localTime(_ ts: Int) -> LocalTime {
        let offset = samaraTimeZone.secondsFromGMT(for: Date(timeIntervalSince1970: TimeInterval(ts)))
        let local = ts + offset
        let days = floorDiv(local, 86400)
        let secs = local - days * 86400
        let c = civil(fromDays: days)
        return LocalTime(
            dayNumber: days,
            year: c.year,
            month: c.month,
            day: c.day,
            hour: secs / 3600,
            minute: secs % 3600 / 60
        )
    }

    /// Journal time: «сегодня 14:20», «вчера 09:05», «12.10 14:20».
    public static func when(_ ts: Int, now: TimeInterval) -> String {
        let t = localTime(ts)
        let n = localTime(Int(now.rounded(.down)))
        let hm = two(t.hour) + ":" + two(t.minute)
        if t.dayNumber == n.dayNumber {
            return "сегодня " + hm
        }
        if t.dayNumber == n.dayNumber - 1 {
            return "вчера " + hm
        }
        return two(t.day) + "." + two(t.month) + " " + hm
    }

    /// Offline banner time: «14:20», «вчера 09:05», «12.10 14:20».
    public static func whenShort(_ ts: Int, now: TimeInterval) -> String {
        let t = localTime(ts)
        let n = localTime(Int(now.rounded(.down)))
        let hm = two(t.hour) + ":" + two(t.minute)
        if t.dayNumber == n.dayNumber {
            return hm
        }
        if t.dayNumber == n.dayNumber - 1 {
            return "вчера " + hm
        }
        return two(t.day) + "." + two(t.month) + " " + hm
    }

    /// «31 октября».
    public static func dayMonth(_ ts: Int) -> String {
        let t = localTime(ts)
        let idx = min(max(t.month - 1, 0), 11)
        return "\(t.day) \(monthsGenitive[idx])"
    }

    /// «HH:mm» in Samara time.
    public static func hourMinute(_ ts: Int) -> String {
        let t = localTime(ts)
        return two(t.hour) + ":" + two(t.minute)
    }

    // MARK: - Text helpers

    /// Replaces the whole word `_direct` (JS `\b_direct\b`) with «Напрямую (без VPN)».
    public static func replaceDirect(_ text: String) -> String {
        let needle: [Unicode.Scalar] = Array("_direct".unicodeScalars)
        let s: [Unicode.Scalar] = Array(text.unicodeScalars)
        let replacement = Summary.directName
        var out = String.UnicodeScalarView()
        var i = 0
        while i < s.count {
            var matched = false
            if i + needle.count <= s.count {
                matched = true
                var k = 0
                while k < needle.count {
                    if s[i + k] != needle[k] {
                        matched = false
                        break
                    }
                    k += 1
                }
                if matched && i > 0 && isWordScalar(s[i - 1]) {
                    matched = false
                }
                if matched && i + needle.count < s.count && isWordScalar(s[i + needle.count]) {
                    matched = false
                }
            }
            if matched {
                out.append(contentsOf: replacement.unicodeScalars)
                i += needle.count
            } else {
                out.append(s[i])
                i += 1
            }
        }
        return String(out)
    }

    /// `hostOf`: drop `scheme://` and everything from the first `/` or `:`.
    public static func hostOf(_ address: String) -> String {
        var rest = Substring(address)
        if let r = address.range(of: "://") {
            let scheme = address[address.startIndex..<r.lowerBound]
            var lettersOnly = !scheme.isEmpty
            for u in scheme.unicodeScalars {
                let v = u.value
                if !((v >= 0x41 && v <= 0x5A) || (v >= 0x61 && v <= 0x7A)) {
                    lettersOnly = false
                    break
                }
            }
            if lettersOnly {
                rest = address[r.upperBound...]
            }
        }
        if let idx = rest.firstIndex(where: { $0 == "/" || $0 == ":" }) {
            rest = rest[rest.startIndex..<idx]
        }
        return String(rest)
    }

    // MARK: - Internals

    static func two(_ n: Int) -> String {
        return n < 10 ? "0\(n)" : "\(n)"
    }

    static func isWordScalar(_ u: Unicode.Scalar) -> Bool {
        let v = u.value
        return (v >= 0x30 && v <= 0x39) || (v >= 0x41 && v <= 0x5A) || (v >= 0x61 && v <= 0x7A) || v == 0x5F
    }

    static func floorDiv(_ a: Int, _ b: Int) -> Int {
        let q = a / b
        if (a % b != 0) && ((a < 0) != (b < 0)) {
            return q - 1
        }
        return q
    }

    /// Howard Hinnant's civil_from_days.
    static func civil(fromDays days: Int) -> (year: Int, month: Int, day: Int) {
        let z = days + 719468
        let era = (z >= 0 ? z : z - 146096) / 146097
        let doe = z - era * 146097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365
        let y = yoe + era * 400
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let d = doy - (153 * mp + 2) / 5 + 1
        let m = mp < 10 ? mp + 3 : mp - 9
        return (m <= 2 ? y + 1 : y, m, d)
    }
}
