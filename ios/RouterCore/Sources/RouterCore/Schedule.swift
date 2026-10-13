import Foundation

/// A device schedule «без интернета с `off` до `on`» in router time (Europe/Samara), contract-stage4 §5.3.3.
/// `off`/`on` are `"HHMM"`; `off > on` crosses midnight («23:00 → 07:00»).
public struct ScheduleWindow: Equatable, Sendable {
    public var off: String
    public var on: String

    /// Web defaults (app.js:529): 23:00 → 07:00.
    public static let defaultOff = "2300"
    public static let defaultOn = "0700"

    public init(off: String, on: String) {
        self.off = off
        self.on = on
    }

    /// Parses `status.devices[].sched` (`"HHMM-HHMM"`); `nil` when malformed.
    public init?(sched: String) {
        let parts = sched.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 2, Validation.isValidHHMM(parts[0]), Validation.isValidHHMM(parts[1]) else {
            return nil
        }
        off = parts[0]
        on = parts[1]
    }

    /// From hours and minutes (pickers), zero-padded.
    public init(offHour: Int, offMinute: Int, onHour: Int, onMinute: Int) {
        off = ScheduleWindow.hhmm(hour: offHour, minute: offMinute)
        on = ScheduleWindow.hhmm(hour: onHour, minute: onMinute)
    }

    /// The window to prefill the sheet with: the device's `sched`, else 23:00 → 07:00.
    public static func initial(for sched: String?) -> ScheduleWindow {
        if let s = sched, let w = ScheduleWindow(sched: s) {
            return w
        }
        return ScheduleWindow(off: defaultOff, on: defaultOn)
    }

    /// `"HHMM"`, clamped to 00:00…23:59.
    public static func hhmm(hour: Int, minute: Int) -> String {
        let h = min(max(hour, 0), 23)
        let m = min(max(minute, 0), 59)
        return Fmt.two(h) + Fmt.two(m)
    }

    /// Both times valid and different (the server refuses equal times).
    public var isValid: Bool {
        return Validation.isValidHHMM(off) && Validation.isValidHHMM(on) && off != on
    }

    /// `off == on`: «Сохранить» disabled with `ScheduleTexts.sameTime`.
    public var hasSameTimes: Bool {
        return off == on
    }

    public var crossesMidnight: Bool {
        return (Int(off) ?? 0) > (Int(on) ?? 0)
    }

    /// «23:00».
    public var offText: String {
        return ScheduleWindow.colon(off)
    }

    /// «07:00».
    public var onText: String {
        return ScheduleWindow.colon(on)
    }

    /// «23:00–07:00» (en dash).
    public var text: String {
        return offText + "–" + onText
    }

    /// `"2300-0700"` (the `sched` format).
    public var sched: String {
        return off + "-" + on
    }

    public var offHour: Int { return (Int(off) ?? 0) / 100 }
    public var offMinute: Int { return (Int(off) ?? 0) % 100 }
    public var onHour: Int { return (Int(on) ?? 0) / 100 }
    public var onMinute: Int { return (Int(on) ?? 0) % 100 }

    /// `fspirat-fw:284` at minute resolution: `n` = HHMM now as an int.
    /// Active = `(f < t && n >= f && n < t) || (f > t && (n >= f || n < t))`; `off` is in, `on` is out.
    public func isActive(hhmm n: Int) -> Bool {
        guard let f = Int(off), let t = Int(on) else {
            return false
        }
        if f < t {
            return n >= f && n < t
        }
        if f > t {
            return n >= f || n < t
        }
        return false
    }

    /// Is the window active at `now` in Samara time?
    public func isActive(now: TimeInterval) -> Bool {
        let t = Fmt.localTime(Int(now.rounded(.down)))
        return isActive(hhmm: t.hour * 100 + t.minute)
    }

    /// The `schedule` set action for a device.
    public func action(mac: String) -> RouterAction {
        return .schedule(mac: mac, off: off, on: on)
    }

    static func colon(_ s: String) -> String {
        let a = Array(s)
        guard a.count == 4 else {
            return s
        }
        return String(a[0..<2]) + ":" + String(a[2..<4])
    }
}

/// Texts of the schedule sheet (web `sched-dlg`, index.html:335-340; contract-stage4 §5.3.3).
public enum ScheduleTexts {
    public static let text = "В это время у устройства не будет интернета — каждый день. Можно через полночь, например 23:00 → 07:00."
    public static let caption = "Время роутера (Самара, UTC+4)."
    public static let offLabel = "Выключать в"
    public static let onLabel = "Включать в"
    public static let save = "Сохранить"
    public static let clear = "Убрать расписание"
    public static let cancel = "Отмена"
    public static let sameTime = Validation.sameTimeHint
    /// (proposed) Extra line above the server text in the 428 dialog when the window is active now (red button).
    public static let activeNowWarning = "Сейчас как раз время без интернета — интернет у устройства выключится сразу."
    /// (proposed) After `unblock` while `sblocked`.
    public static let unblockDuringWindow = "Сейчас идёт окно расписания — интернет вернётся после его конца или когда уберёшь расписание."

    /// «Расписание: <nm>».
    public static func title(_ name: String) -> String {
        return "Расписание: " + name
    }

    /// Device card button: «Расписание…» or «Расписание: 23:00–07:00».
    public static func buttonTitle(sched: String?) -> String {
        guard let s = sched, let w = ScheduleWindow(sched: s) else {
            return "Расписание…"
        }
        return "Расписание: " + w.text
    }
}
