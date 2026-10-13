import Foundation

// «Устройства» tab and the device card (contract-stage4 §5.2, §5.3), port of app.js renderDevices / devRow.

public enum DeviceFilter: String, CaseIterable, Equatable, Sendable {
    case all
    case online
    case offline
    /// blocked, sblocked, a schedule or «мимо VPN».
    case limited

    /// «Все», «В сети», «Не в сети», «Ограничены».
    public var title: String {
        switch self {
        case .all:
            return "Все"
        case .online:
            return "В сети"
        case .offline:
            return "Не в сети"
        case .limited:
            return "Ограничены"
        }
    }
}

public enum DeviceSectionKind: String, CaseIterable, Equatable, Sendable {
    case wifi5
    case wifi24
    case wired
    case offline

    /// «Wi-Fi 5 ГГц», «Wi-Fi 2,4 ГГц», «По кабелю», «Не в сети».
    public var title: String {
        switch self {
        case .wifi5:
            return "Wi-Fi 5" + Fmt.nbsp + "ГГц"
        case .wifi24:
            return "Wi-Fi 2,4" + Fmt.nbsp + "ГГц"
        case .wired:
            return "По кабелю"
        case .offline:
            return "Не в сети"
        }
    }

    /// SF Symbol.
    public var symbol: String {
        switch self {
        case .wifi5, .wifi24:
            return "wifi"
        case .wired:
            return "cable.connector"
        case .offline:
            return "wifi.slash"
        }
    }
}

/// A capsule on a device row.
public struct DeviceLabel: Equatable, Sendable {
    /// «без интернета», «по расписанию», «мимо VPN», «23:00–07:00».
    public var text: String
    /// err / info / neutral.
    public var tone: Tone
    /// `timer` for the schedule label.
    public var symbol: String?
}

public struct DeviceRowInfo: Equatable, Sendable, Identifiable {
    public var mac: String
    /// Own name, DHCP name or «Без имени».
    public var title: String
    /// Has an own or DHCP name.
    public var hasName: Bool
    public var isOnline: Bool
    public var labels: [DeviceLabel]
    /// «192.168.1.23 · 866 Мбит/с», «192.168.1.90 · скрытый MAC».
    public var subtitle: String
    /// 1–4 for the `wifi` symbol (`variableValue: level / 4`); `nil` = no signal icon (offline or wired).
    public var signalLevel: Int?
    /// «Сигнал −51 dBm».
    public var signalAccessibility: String?
    /// «↓ 1,5 ГБ» (with a small «сегодня»), `nil` when there is no traffic entry.
    public var todayText: String?

    public var id: String {
        return mac
    }
}

public struct DeviceSection: Equatable, Sendable, Identifiable {
    public var kind: DeviceSectionKind
    public var title: String
    public var symbol: String
    public var rows: [DeviceRowInfo]
    /// Only «Не в сети»: a collapsed `DisclosureGroup` titled `header` («Не в сети: 2»).
    public var isCollapsed: Bool
    /// «Не в сети: 2» for the collapsed group, else the title.
    public var header: String

    public var id: String {
        return kind.rawValue
    }

    public var count: Int {
        return rows.count
    }
}

public struct DeviceListInfo: Equatable, Sendable {
    /// «4 в сети из 6» / «найдено 2 из 6».
    public var summary: String
    public var sections: [DeviceSection]
    /// Empty state text, `nil` when there are rows.
    public var emptyText: String?
    public var total: Int
    public var online: Int
}

/// «Новые за неделю» row.
public struct NewDeviceRow: Equatable, Sendable, Identifiable {
    public var mac: String
    public var ts: Int
    /// Name, or «Без имени»; the MAC when the lease is gone and there is no own name.
    public var title: String
    /// «вчера 21:44».
    public var whenText: String
    /// The MAC is in `status.devices` (else the card shows only MAC, traffic and rename).
    public var isKnown: Bool

    public var id: String {
        return mac
    }
}

/// A label/value row of the device card.
public struct DetailRow: Equatable, Sendable, Identifiable {
    public var label: String
    public var value: String
    public var tone: Tone
    /// Small text under the value.
    public var caption: String?

    public init(label: String, value: String, tone: Tone = .neutral, caption: String? = nil) {
        self.label = label
        self.value = value
        self.tone = tone
        self.caption = caption
    }

    public var id: String {
        return label
    }
}

/// The device card (contract-stage4 §5.3).
public struct DeviceDetail: Equatable, Sendable {
    public var mac: String
    /// Own name, DHCP name or «Без имени».
    public var title: String
    /// «Имя в сети: tv-living» when an own name differs from the DHCP name.
    public var networkNameCaption: String?
    /// The device is in `status.devices` (else only MAC, traffic and rename).
    public var isKnown: Bool
    public var isOnline: Bool
    public var rows: [DetailRow]
    public var footer: String
    /// Prefill of the rename field (`names[mac] ?? d.name`) and its placeholder (`d.name` or «Имя устройства»).
    public var renamePrefill: String
    public var renamePlaceholder: String
    public var blocked: Bool
    public var sblocked: Bool
    public var direct: Bool
    public var sched: String?
    /// «Расписание…» / «Расписание: 23:00–07:00».
    public var scheduleButtonTitle: String

    /// «Выключить интернет» (428 high, red) when not blocked, else `nil`.
    public var blockAction: RouterAction? {
        return isKnown && !blocked ? .block(mac: mac) : nil
    }

    /// «Включить интернет» (no dialog) when blocked.
    public var unblockAction: RouterAction? {
        return isKnown && blocked ? .unblock(mac: mac) : nil
    }

    /// «Пускать мимо VPN» / «Снова через VPN» (428 high).
    public var directAction: RouterAction? {
        return isKnown ? .direct(mac: mac, on: !direct) : nil
    }

    /// «Пускать мимо VPN» or «Снова через VPN».
    public var directButtonTitle: String {
        return direct ? "Снова через VPN" : "Пускать мимо VPN"
    }

    /// «Убрать расписание» (no dialog), when a schedule exists.
    public var clearScheduleAction: RouterAction? {
        return isKnown && sched != nil ? .scheduleClear(mac: mac) : nil
    }

    /// The rename action for the typed text (`""` removes the own name).
    public func renameAction(_ text: String) -> RouterAction {
        return .rename(mac: mac, name: Validation.renameValue(text))
    }
}

public enum DeviceTexts {
    public static let title = "Устройства"
    /// (proposed)
    public static let searchPrompt = "Имя, IP или MAC"
    public static let noName = Summary.noName
    public static let emptyFiltered = "Ничего не найдено — измени поиск или фильтр."
    public static let emptyNone = "Устройства не найдены: роутер пока никому не выдал адрес."
    /// (proposed) Cold start offline.
    public static let noStatus = "Роутер не на связи — список устройств появится, когда он вернётся."
    public static let newTitle = "Новые за неделю"
    public static let open = "Открыть"
    public static let today = "сегодня"
    public static let rename = "Переименовать"
    public static let renamePlaceholder = "Имя устройства"
    public static let renameFooter = "Пустое имя — как называет себя устройство."
    public static let save = "Сохранить"
    public static let block = "Выключить интернет"
    public static let unblock = "Включить интернет"
    public static let footer = "Трафик считает сервер раз в минуту. Учитывается только обычный интернет устройства: Telegram через Cloudflare в нём не виден."
    /// (proposed)
    public static let hiddenMACCaption = "Скрытый MAC: телефон сам придумал этот адрес для приватности. Он может измениться."
}

public enum Devices {
    /// `devName(d)` (app.js:418): own name if non-empty, else the DHCP name, else "".
    public static func displayName(_ d: RouterDevice, names: [String: String]) -> String {
        if let n = names[d.mac.lowercased()], !n.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return n
        }
        return d.name
    }

    /// `hiddenMac` (app.js:419): `^.[26ae]` — a locally administered MAC.
    public static func isHiddenMAC(_ mac: String) -> Bool {
        return Validation.isRandomizedMAC(mac)
    }

    /// `sig` (app.js:420): 0 unknown; > −55 → 4; > −65 → 3; > −75 → 2; else 1.
    public static func signalLevel(_ dbm: Int?) -> Int {
        guard let d = dbm, d != 0 else {
            return 0
        }
        if d > -55 {
            return 4
        }
        if d > -65 {
            return 3
        }
        if d > -75 {
            return 2
        }
        return 1
    }

    /// «Ограничены»: `blocked || sblocked || sched != nil || direct`.
    public static func isLimited(_ d: RouterDevice) -> Bool {
        return d.blocked || d.sblocked || d.sched != nil || d.direct
    }

    public static func matches(_ d: RouterDevice, filter: DeviceFilter) -> Bool {
        switch filter {
        case .all:
            return true
        case .online:
            return d.online
        case .offline:
            return !d.online
        case .limited:
            return isLimited(d)
        }
    }

    /// Case-insensitive substring of the display name, the DHCP name, IP or MAC.
    public static func matches(_ d: RouterDevice, query: String, names: [String: String]) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty {
            return true
        }
        return [displayName(d, names: names), d.name, d.ip, d.mac].contains { $0.lowercased().contains(q) }
    }

    /// Labels in order: «без интернета» (blocked) or «по расписанию» (sblocked); «мимо VPN»; the schedule
    /// (`timer`, «23:00–07:00») unless sblocked.
    public static func labels(_ d: RouterDevice) -> [DeviceLabel] {
        var out: [DeviceLabel] = []
        if d.blocked {
            out.append(DeviceLabel(text: "без интернета", tone: .err, symbol: nil))
        } else if d.sblocked {
            out.append(DeviceLabel(text: "по расписанию", tone: .err, symbol: nil))
        }
        if d.direct {
            out.append(DeviceLabel(text: "мимо VPN", tone: .info, symbol: nil))
        }
        if let s = d.sched, !d.sblocked {
            out.append(DeviceLabel(text: Fmt.schedText(s), tone: .neutral, symbol: "timer"))
        }
        return out
    }

    public static func row(_ d: RouterDevice, names: [String: String], traffic: [String: TrafficEntry]) -> DeviceRowInfo {
        let name = displayName(d, names: names)
        var sub: [String] = []
        if !d.ip.isEmpty {
            sub.append(d.ip)
        }
        if isHiddenMAC(d.mac) && name.isEmpty {
            sub.append("скрытый MAC")
        }
        if let r = d.rate, r > 0 {
            sub.append("\(r)" + Fmt.nbsp + "Мбит/с")
        }
        let wifi = d.online && d.band != nil && d.band != "wired"
        let level = signalLevel(d.signal)
        var today: String? = nil
        if let t = traffic[d.mac.lowercased()] {
            today = "↓" + Fmt.nbsp + Fmt.bytes(t.dayDown)
        }
        return DeviceRowInfo(
            mac: d.mac,
            title: name.isEmpty ? Summary.noName : name,
            hasName: !name.isEmpty,
            isOnline: d.online,
            labels: labels(d),
            subtitle: sub.joined(separator: " · "),
            signalLevel: wifi ? level : nil,
            signalAccessibility: wifi ? "Сигнал " + Fmt.signalText(d.signal) : nil,
            todayText: today
        )
    }

    /// The grouped list (online first; «Не в сети» collapsed unless the filter is «Не в сети» or the search is not empty).
    public static func list(_ devices: [RouterDevice], names: [String: String], traffic: [String: TrafficEntry], query: String = "", filter: DeviceFilter = .all) -> DeviceListInfo {
        let all = devices
        let onlineAll = all.filter { $0.online }.count
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let list = all.filter { matches($0, filter: filter) && matches($0, query: q, names: names) }
        let sorted = sortedByName(list, names: names)
        var sections: [DeviceSection] = []
        let groups: [(DeviceSectionKind, [RouterDevice])] = [
            (.wifi5, sorted.filter { $0.online && ($0.band == "5g" || $0.band == "6g") }),
            (.wifi24, sorted.filter { $0.online && $0.band == "2g" }),
            (.wired, sorted.filter { $0.online && !["5g", "6g", "2g"].contains($0.band ?? "") }),
            (.offline, sorted.filter { !$0.online })
        ]
        for (kind, items) in groups where !items.isEmpty {
            let collapsed = kind == .offline && filter != .offline && q.isEmpty
            sections.append(DeviceSection(
                kind: kind,
                title: kind.title,
                symbol: kind.symbol,
                rows: items.map { row($0, names: names, traffic: traffic) },
                isCollapsed: collapsed,
                header: collapsed ? "Не в сети: \(items.count)" : kind.title
            ))
        }
        let summary = list.count == all.count
            ? "\(onlineAll)" + Fmt.nbsp + "в сети из \(all.count)"
            : "найдено \(list.count) из \(all.count)"
        var empty: String? = nil
        if list.isEmpty {
            empty = all.isEmpty ? DeviceTexts.emptyNone : DeviceTexts.emptyFiltered
        }
        return DeviceListInfo(summary: summary, sections: sections, emptyText: empty, total: all.count, online: onlineAll)
    }

    /// By display name, unnamed last, `localizedStandardCompare`; stable.
    public static func sortedByName(_ list: [RouterDevice], names: [String: String]) -> [RouterDevice] {
        return VPN.stableSorted(list) { a, b in
            let x = displayName(a, names: names)
            let y = displayName(b, names: names)
            if x.isEmpty != y.isEmpty {
                return !x.isEmpty
            }
            return x.localizedStandardCompare(y) == .orderedAscending
        }
    }

    /// «Новые за неделю»: `newdevs` (newest first) deduplicated by MAC, keeping the newest.
    public static func newThisWeek(_ newdevs: [NewDevice], devices: [RouterDevice], names: [String: String], now: TimeInterval) -> [NewDeviceRow] {
        var seen = Set<String>()
        var out: [NewDeviceRow] = []
        for n in newdevs.sorted(by: { $0.ts > $1.ts }) {
            let mac = n.mac.lowercased()
            if mac.isEmpty || seen.contains(mac) {
                continue
            }
            seen.insert(mac)
            let d = devices.first(where: { $0.mac == mac })
            var title = ""
            if let dev = d {
                title = displayName(dev, names: names)
            } else if let own = names[mac], !own.isEmpty {
                title = own
            }
            if title.isEmpty {
                title = d == nil ? mac : Summary.noName
            }
            out.append(NewDeviceRow(mac: mac, ts: n.ts, title: title, whenText: Fmt.when(n.ts, now: now), isKnown: d != nil))
        }
        return out
    }

    /// Tab badge: new devices after the last time the user opened the tab (`@AppStorage("devicesSeenAt")`).
    public static func unseenCount(_ newdevs: [NewDevice], seenAt: Int) -> Int {
        var macs = Set<String>()
        for n in newdevs where n.ts > seenAt {
            macs.insert(n.mac.lowercased())
        }
        return macs.count
    }

    /// The device card for a MAC (`device == nil` when the lease is gone: MAC, traffic, rename only).
    public static func detail(mac rawMAC: String, device: RouterDevice?, names: [String: String], traffic: [String: TrafficEntry]) -> DeviceDetail {
        let mac = rawMAC.lowercased()
        let own = names[mac] ?? ""
        let dhcp = device?.name ?? ""
        var name = own.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? dhcp : own
        if name.isEmpty {
            name = ""
        }
        var caption: String? = nil
        if !own.isEmpty && !dhcp.isEmpty && dhcp != own {
            caption = "Имя в сети: " + dhcp
        }
        var rows: [DetailRow] = []
        if let d = device {
            if d.online {
                let band = Fmt.bandText(d.band) ?? "кабель"
                rows.append(DetailRow(label: "Статус", value: "В сети · " + band, tone: .ok))
            } else {
                rows.append(DetailRow(label: "Статус", value: "Не в сети", tone: .neutral))
            }
            if !d.ip.isEmpty {
                rows.append(DetailRow(label: "IP", value: d.ip))
            }
        }
        rows.append(DetailRow(label: "MAC", value: mac, caption: isHiddenMAC(mac) ? DeviceTexts.hiddenMACCaption : nil))
        if let d = device, d.online, let b = d.band, b != "wired" {
            var v = Fmt.signalText(d.signal)
            if let r = d.rate, r > 0 {
                v += " · \(r)" + Fmt.nbsp + "Мбит/с"
            }
            rows.append(DetailRow(label: "Сигнал", value: v))
        }
        if let t = traffic[mac] {
            // NBSP after the arrows: an arrow never wraps away from its value (contract-stage4 §9.3).
            rows.append(DetailRow(label: "Сегодня", value: "↓" + Fmt.nbsp + Fmt.bytes(t.dayDown) + " · ↑" + Fmt.nbsp + Fmt.bytes(t.dayUp)))
            rows.append(DetailRow(label: "За месяц", value: "↓" + Fmt.nbsp + Fmt.bytes(t.monthDown) + " · ↑" + Fmt.nbsp + Fmt.bytes(t.monthUp)))
        }
        if let d = device {
            let internet: (String, Tone)
            if d.blocked {
                internet = ("Выключен", .err)
            } else if d.sblocked {
                internet = ("Выключен по расписанию", .err)
            } else {
                internet = ("Есть", .ok)
            }
            rows.append(DetailRow(label: "Интернет", value: internet.0, tone: internet.1))
            rows.append(DetailRow(label: "Через VPN", value: d.direct ? "Мимо VPN" : "Да", tone: d.direct ? .info : .neutral))
            rows.append(DetailRow(label: "Расписание", value: d.sched.map { Fmt.schedText($0) } ?? "Нет"))
        }
        return DeviceDetail(
            mac: mac,
            title: name.isEmpty ? Summary.noName : name,
            networkNameCaption: caption,
            isKnown: device != nil,
            isOnline: device?.online ?? false,
            rows: rows,
            footer: DeviceTexts.footer,
            renamePrefill: own.isEmpty ? dhcp : own,
            renamePlaceholder: dhcp.isEmpty ? DeviceTexts.renamePlaceholder : dhcp,
            blocked: device?.blocked ?? false,
            sblocked: device?.sblocked ?? false,
            direct: device?.direct ?? false,
            sched: device?.sched,
            scheduleButtonTitle: ScheduleTexts.buttonTitle(sched: device?.sched)
        )
    }
}
