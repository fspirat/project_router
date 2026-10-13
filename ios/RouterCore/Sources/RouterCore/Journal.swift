import Foundation

// «Журнал» tab (contract-stage4 §5.5), port of app.js events() / renderLog() with day grouping in Europe/Samara.

public enum JournalFilter: String, CaseIterable, Equatable, Sendable {
    case all
    case errors
    case warnings
    /// info **and** ok events (app.js:410).
    case actions

    /// «Все», «Ошибки», «Внимание», «Действия».
    public var title: String {
        switch self {
        case .all:
            return "Все"
        case .errors:
            return "Ошибки"
        case .warnings:
            return "Внимание"
        case .actions:
            return "Действия"
        }
    }

    public func matches(_ level: Tone) -> Bool {
        switch self {
        case .all:
            return true
        case .errors:
            return level == .err
        case .warnings:
            return level == .warn
        case .actions:
            return level == .info || level == .ok || level == .neutral
        }
    }
}

public struct JournalRow: Equatable, Sendable, Identifiable {
    public var id: String
    public var ts: Int
    /// «14:10» (Samara).
    public var time: String
    public var kind: String
    public var level: Tone
    /// «Ошибка», «Внимание», «Успех», «Действие».
    public var chip: String
    /// Display text (`_direct` replaced, «→», «41 мс», optional names after MACs).
    public var text: String
    /// SF Symbol for the kind (proposed).
    public var symbol: String
}

public struct JournalDay: Equatable, Sendable, Identifiable {
    /// Samara day number.
    public var day: Int
    /// «Сегодня», «Вчера», «11 октября», «11 октября 2025».
    public var title: String
    public var rows: [JournalRow]

    public var id: Int {
        return day
    }
}

public struct JournalInfo: Equatable, Sendable {
    public var days: [JournalDay]
    /// «7 записей» or «найдено 1 из 7»; "" when there are no events.
    public var countText: String
    /// Empty state, `nil` when there are rows.
    public var emptyText: String?
    /// Footer notices (100-event limit, 30-day incompleteness).
    public var notices: [String]
    public var total: Int
    public var shown: Int
}

public enum JournalTexts {
    public static let title = "Журнал"
    public static let timeNote = "Время роутера (Самара, UTC+4)"
    /// (proposed)
    public static let searchPrompt = "Поиск в журнале"
    public static let empty = Summary.emptyEvents
    public static let emptyFiltered = "Таких записей нет."
    /// (proposed)
    public static let limitNotice = "Сервер отдаёт не больше 100 последних событий за период — более ранние сюда не попали."
    /// (proposed)
    public static let monthNotice = "За 30 дней список может быть неполным."
}

public enum Journal {
    /// The server never sends more than this many events per range.
    public static let serverLimit = 100

    /// SF Symbol per kind (proposed).
    public static func symbol(kind: String) -> String {
        switch kind {
        case "offline":
            return "wifi.slash"
        case "online":
            return "wifi"
        case "vpn_down":
            return "xmark.shield"
        case "vpn_up":
            return "checkmark.shield"
        case "auto":
            return "arrow.triangle.2.circlepath"
        case "manual":
            return "hand.tap"
        case "restart":
            return "arrow.counterclockwise"
        case "update":
            return "arrow.down.circle"
        case "reboot":
            return "power"
        case "newdev":
            return "plus.circle"
        case "xraymem":
            return "memorychip"
        case "router":
            return "gearshape"
        default:
            return "circle"
        }
    }

    /// (proposed) For `router`/`newdev` texts: « (<name>)» after every MAC with an own name. The MAC stays.
    public static func annotateMACs(_ text: String, names: [String: String]) -> String {
        guard !names.isEmpty, let re = try? NSRegularExpression(pattern: "([0-9a-f]{2}:){5}[0-9a-f]{2}", options: [.caseInsensitive]) else {
            return text
        }
        let ns = text as NSString
        var out = ""
        var last = 0
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let end = m.range.location + m.range.length
            out += ns.substring(with: NSRange(location: last, length: end - last))
            let mac = ns.substring(with: m.range).lowercased()
            if let n = names[mac], !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                out += " (\(n))"
            }
            last = end
        }
        out += ns.substring(from: last)
        return out
    }

    /// The display text of an event.
    public static func displayText(_ e: DataEvent, names: [String: String] = [:]) -> String {
        var t = Fmt.eventDisplayText(e.text)
        if e.kind == "router" || e.kind == "newdev" {
            t = annotateMACs(t, names: names)
        }
        return t
    }

    /// Filter, search and group `events` (newest first) by Samara day.
    public static func build(_ events: [DataEvent], names: [String: String] = [:], range: DataRange, filter: JournalFilter = .all, query: String = "", now: TimeInterval) -> JournalInfo {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var rows: [(Int, JournalRow)] = []
        for (i, e) in events.enumerated() {
            let level = Summary.eventLevel(kind: e.kind)
            guard filter.matches(level) else {
                continue
            }
            let text = displayText(e, names: names)
            if !q.isEmpty && !text.lowercased().contains(q) && !Fmt.when(e.ts, now: now).lowercased().contains(q) {
                continue
            }
            let row = JournalRow(
                id: "\(e.ts)-\(i)",
                ts: e.ts,
                time: Fmt.hourMinute(e.ts),
                kind: e.kind,
                level: level,
                chip: Summary.chipLabel(level),
                text: text,
                symbol: symbol(kind: e.kind)
            )
            rows.append((Fmt.localTime(e.ts).dayNumber, row))
        }
        var days: [JournalDay] = []
        for (day, row) in rows {
            if let lastIndex = days.indices.last, days[lastIndex].day == day {
                days[lastIndex].rows.append(row)
            } else {
                days.append(JournalDay(day: day, title: Fmt.dayLabel(row.ts, now: now), rows: [row]))
            }
        }
        let total = events.count
        let shown = rows.count
        let filtered = filter != .all || !q.isEmpty
        var countText = ""
        if total > 0 {
            countText = filtered && shown != total
                ? "найдено \(shown) из \(total)"
                : Fmt.count(total, "запись", "записи", "записей")
        }
        var empty: String? = nil
        if shown == 0 {
            empty = total == 0 ? JournalTexts.empty : JournalTexts.emptyFiltered
        }
        var notices: [String] = []
        if total >= serverLimit {
            notices.append(JournalTexts.limitNotice)
        }
        if range == .month {
            notices.append(JournalTexts.monthNotice)
        }
        return JournalInfo(days: days, countText: countText, emptyText: empty, notices: notices, total: total, shown: shown)
    }
}
