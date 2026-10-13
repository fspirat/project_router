import Foundation

// Stage 4 formatting helpers (contract-stage4 §7). Same rules as `Fmt`: decimal comma, NBSP before units,
// every time in Europe/Samara.

extension Fmt {
    /// `sys.load` / `/vds` load: «0.21 0.17 0.15» → «0,21 0,17 0,15».
    public static func loadText(_ load: String) -> String {
        return load.replacingOccurrences(of: ".", with: ",")
    }

    /// Node name for display: trimmed («  🇳🇱 Нидерланды » → «🇳🇱 Нидерланды»).
    public static func nodeDisplayName(_ name: String) -> String {
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Sort key of a server name (app.js:245): leading characters that are not letters or digits
    /// (`^[^\p{L}\p{N}]+`, e.g. a flag emoji and spaces) removed, trimmed, lowercased.
    public static func sortKeyName(_ name: String) -> String {
        var scalars = Substring(name).unicodeScalars[...]
        while let first = scalars.first, !isLetterOrNumber(first) {
            scalars = scalars.dropFirst()
        }
        return String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// `flag(cc)` (app.js:575): `^[A-Z]{2}$` → two regional indicator symbols and a space; else "".
    public static func flag(_ countryCode: String) -> String {
        let scalars = Array(countryCode.unicodeScalars)
        guard scalars.count == 2 else {
            return ""
        }
        var out = String.UnicodeScalarView()
        for u in scalars {
            guard u.value >= 0x41 && u.value <= 0x5A, let ri = Unicode.Scalar(0x1F1E6 + u.value - 0x41) else {
                return ""
            }
            out.append(ri)
        }
        return String(out) + " "
    }

    /// «−51 dBm» (U+2212 minus, NBSP) or «—» when unknown (0 or nil).
    public static func signalText(_ dbm: Int?) -> String {
        guard let d = dbm, d != 0 else {
            return "—"
        }
        let n = d < 0 ? "\u{2212}\(-d)" : "\(d)"
        return n + nbsp + "dBm"
    }

    /// `5g` «Wi-Fi 5 ГГц», `6g` «Wi-Fi 6 ГГц», `2g` «Wi-Fi 2,4 ГГц», `wired` «кабель»; anything else `nil`.
    public static func bandText(_ band: String?) -> String? {
        switch band ?? "" {
        case "5g":
            return "Wi-Fi 5" + nbsp + "ГГц"
        case "6g":
            return "Wi-Fi 6" + nbsp + "ГГц"
        case "2g":
            return "Wi-Fi 2,4" + nbsp + "ГГц"
        case "wired":
            return "кабель"
        default:
            return nil
        }
    }

    /// `"2300-0700"` → «23:00–07:00» (en dash); a malformed value is returned as is.
    public static func schedText(_ sched: String) -> String {
        guard let w = ScheduleWindow(sched: sched) else {
            return sched
        }
        return w.text
    }

    /// `seenTxt` (app.js:1088): within an hour → `ago`, else `when`; 0 → «—».
    public static func seenText(_ ts: Int, now: TimeInterval) -> String {
        if ts <= 0 {
            return "—"
        }
        if now - Double(ts) < 3600 {
            return ago(ts, now: now)
        }
        return when(ts, now: now)
    }

    /// `osTxt` (app.js:1089): a value starting with a digit gets «iOS » in front («18.1» → «iOS 18.1»).
    public static func osText(_ os: String) -> String {
        guard let first = os.unicodeScalars.first, first.value >= 0x30 && first.value <= 0x39 else {
            return os
        }
        return "iOS " + os
    }

    /// Journal day header in Samara time: «Сегодня», «Вчера», «12 октября», «12 октября 2025» (another year).
    public static func dayLabel(_ ts: Int, now: TimeInterval) -> String {
        let t = localTime(ts)
        let n = localTime(Int(now.rounded(.down)))
        if t.dayNumber == n.dayNumber {
            return "Сегодня"
        }
        if t.dayNumber == n.dayNumber - 1 {
            return "Вчера"
        }
        let base = dayMonth(ts)
        return t.year == n.year ? base : base + " \(t.year)"
    }

    /// Cosmetic display of a watcher text (proposed): `_direct` → «Напрямую (без VPN)», «->» → «→»,
    /// «41ms» → «41 мс». Only for display; search uses the same text.
    public static func eventDisplayText(_ text: String) -> String {
        var s = replaceDirect(text).replacingOccurrences(of: "->", with: "→")
        s = replaceRegex(s, pattern: "([0-9]+)ms\\b", template: "$1" + nbsp + "мс")
        return s
    }

    /// `/vds` memory: «35% из 1,9 ГБ».
    public static func vdsMem(total: Int, avail: Int) -> String {
        let pct = total > 0 ? jsRound(Double(total - avail) / Double(total) * 100) : 0
        return "\(pct)% из " + fixed1(Double(total) / 1048576) + nbsp + "ГБ"
    }

    /// «14 серверов», «2 подписки», «5 записей» (NBSP after the number).
    public static func count(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        return "\(n)" + nbsp + plural(n, one, few, many)
    }

    // MARK: - Internals

    static func isLetterOrNumber(_ u: Unicode.Scalar) -> Bool {
        switch u.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .letterNumber, .otherNumber:
            return true
        default:
            return false
        }
    }

    static func replaceRegex(_ s: String, pattern: String, template: String, caseInsensitive: Bool = false) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: caseInsensitive ? [.caseInsensitive] : []) else {
            return s
        }
        let range = NSRange(s.startIndex..<s.endIndex, in: s)
        return re.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: template)
    }
}
