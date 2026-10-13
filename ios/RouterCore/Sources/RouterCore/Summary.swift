import Foundation

// «Сводка» rules ported from web/app.js renderHero() and helpers (contract §4).

/// One verdict line: a dot in the level colour, `name` in `dim`, `text` in bold.
/// `name == nil` for the extra «в PassWall выбран не Split» item.
public struct VerdictItem: Equatable, Sendable {
    public var name: String?
    public var level: Tone
    public var text: String

    public init(name: String?, level: Tone, text: String) {
        self.name = name
        self.level = level
        self.text = text
    }
}

/// The verdict card («итог»).
public struct Verdict: Equatable, Sendable {
    /// `.ok`, `.warn`, `.err`, or `.neutral` for «Проверяю…».
    public var level: Tone
    /// «Всё работает» / «Требует внимания» / «Есть проблема» / «Проверяю…».
    public var title: String
    public var items: [VerdictItem]
    /// The warning box text when PassWall's global node is not Split.
    public var splitWarning: String?
    /// Hide the current-server block when false (offline / no status).
    public var showsCurrentServer: Bool

    public init(level: Tone, title: String, items: [VerdictItem], splitWarning: String?, showsCurrentServer: Bool) {
        self.level = level
        self.title = title
        self.items = items
        self.splitWarning = splitWarning
        self.showsCurrentServer = showsCurrentServer
    }
}

/// The subscription that matters for the Summary (expires first).
public struct SubscriptionPick: Equatable, Sendable {
    /// `nil` when taken from the `status.sub` fallback.
    public var name: String?
    public var title: String
    public var expire: Int
    public var up: Int
    public var down: Int
    public var total: Int

    public init(name: String?, title: String, expire: Int, up: Int, down: Int, total: Int) {
        self.name = name
        self.title = title
        self.expire = expire
        self.up = up
        self.down = down
        self.total = total
    }
}

/// «Подписка до 31 октября · осталось 17 дн. · израсходовано 39,2 ГБ из 200,0 ГБ» (NBSP before units).
public struct SubscriptionLine: Equatable, Sendable {
    /// «Подписка до » or ««nosok» до ».
    public var prefix: String
    /// «31 октября» (bold on the web).
    public var date: String
    public var daysLeft: Int
    /// `daysLeft <= 3` → the number in `err`.
    public var daysLeftIsCritical: Bool
    /// « · израсходовано … из …» / «…, без лимита», or `nil`.
    public var usage: String?
    /// The whole line as plain text.
    public var text: String
}

/// «Подключён сервер» block.
public struct CurrentServer: Equatable, Sendable {
    public static let label = "Подключён сервер"
    public var name: String
    /// «свой», «Подписка nosok», «без VPN» or `nil`.
    public var tag: String?
    public var isDirect: Bool
}

/// «Проверка через VPN» tile (the «через VPN 204» check). Stage 4 (contract-stage4 §9.4): the title is
/// «Проверка через VPN» on one line, the value below it, then `caption`; VoiceOver uses `accessibilityLabel(value:)`.
public struct LatencyTile: Equatable, Sendable {
    /// The tile title (one line).
    public static let title = "Проверка через VPN"
    /// Kept for VoiceOver.
    public static let label = "Задержка"
    public static let caption = "Задержка — как пинг: ответ сайта через VPN по уже открытому соединению. Раз в 5 минут."

    /// «Проверка через VPN, задержка 48 мс».
    public static func accessibilityLabel(value: String) -> String {
        return title + ", задержка " + value
    }
    /// «48 мс», «VPN не проходит» or «—».
    public var value: String
    public var tone: Tone
    /// «Проверено 6 мин назад» or `nil`.
    public var footer: String?
}

/// A service in the Summary list (name, kind, host).
public struct ServiceRef: Equatable, Sendable {
    public var name: String
    public var kind: String
    public var host: String

    public init(name: String, kind: String, host: String) {
        self.name = name
        self.kind = kind
        self.host = host
    }
}

/// A service tile (YouTube, Discord, Telegram, …).
public struct ServiceTile: Equatable, Sendable {
    public var name: String
    public var kind: String
    public var host: String
    /// SF Symbol.
    public var icon: String
    /// ms via the current server; 0 = no answer; `nil` = not measured.
    public var value: Int?
    /// «61 мс», «нет ответа» or «—».
    public var valueText: String
    public var tone: Tone
}

/// A meter row of the router block (bar 6 pt).
public struct Meter: Equatable, Sendable {
    public var title: String
    /// 0–100.
    public var percent: Int
    public var caption: String
    /// Bar colour: ok (acc) < 65 %, warn ≥ 65 %, err ≥ 85 %.
    public var tone: Tone
}

/// A label/value pair («Температура» → «51 °C»).
public struct Fact: Equatable, Sendable {
    public var label: String
    public var value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

/// Traffic of all home devices today (bytes, Samara day).
public struct TrafficToday: Equatable, Sendable {
    public var down: Int
    public var up: Int
    /// Show «Сегодня ↓» only when true (down > 0).
    public var isVisible: Bool {
        return down > 0
    }
    /// «1.5 ГБ».
    public var downText: String {
        return Fmt.bytes(down)
    }
    /// «51 МБ».
    public var upText: String {
        return Fmt.bytes(up)
    }
}

/// A row of «Последние события».
public struct EventRow: Equatable, Sendable {
    public var ts: Int
    /// «сегодня 14:10».
    public var time: String
    public var kind: String
    /// `.err`, `.warn`, `.ok` or `.info`.
    public var level: Tone
    /// «Ошибка», «Внимание», «Успех», «Действие».
    public var chip: String
    /// `_direct` already replaced.
    public var text: String
}

/// An online device for the optional top list.
public struct DeviceRow: Equatable, Sendable {
    public var name: String
    public var mac: String
    public var ip: String
    /// Bytes downloaded today (`data.traffic[mac].d[1]`).
    public var todayDown: Int
}

/// A point of the mini chart.
public struct ChartSample: Equatable, Sendable {
    public var ts: Int
    public var ms: Int

    public init(ts: Int, ms: Int) {
        self.ts = ts
        self.ms = ms
    }
}

/// The 24 h mini chart (contract §4.9).
public struct MiniChart: Equatable, Sendable {
    /// Width of an offline band, seconds (centred on the point).
    public static let bandWidth = 300
    /// A gap longer than this breaks the line, seconds.
    public static let gapBreak = 750

    /// x from `from` to `to` (unix seconds).
    public var from: Int
    public var to: Int
    /// y from 0 to `yMax` (ms).
    public var yMax: Double
    /// Line segments in `acc` with an area fill; a one-point segment is drawn as a dot.
    public var segments: [[ChartSample]]
    /// Short red bars at the bottom (VPN check failed).
    public var failMarks: [Int]
    /// Full-height bands in the `offline` token (router offline), centred on the ts.
    public var offlineBands: [Int]
    /// No points in the window → «данных за этот период пока нет».
    public var isEmpty: Bool
}

/// Offline banner texts (contract §4.12).
public enum OfflineBanner {
    public static let heading = "Роутер не на связи"
    public static let whyTitle = "Почему так бывает"
    public static let why = [
        "дома пропал интернет или свет;",
        "роутер перезагружается (1–2 минуты);",
        "оборвался туннель от роутера до сервера."
    ]
    public static let whatTitle = "Что сделать"
    public static let what = [
        "подождать 2–3 минуты: туннель поднимается сам;",
        "проверить, есть ли дома интернет без VPN;",
        "если не помогло — выключить роутер из розетки на 10 секунд."
    ]
    public static let note = "Кнопки не работают, пока роутер не на связи. История и журнал — с сервера."
    public static let noData = "Сервер не получает ответа от роутера"

    /// «Не на связи с 14:04 · уже 12 мин · последний ответ 14:03».
    public static func line(data: DataResponse?, now: TimeInterval) -> String {
        guard let d = data else {
            return noData
        }
        guard let since = d.offlineSince ?? d.lastOK else {
            return noData
        }
        let m = max(1, Fmt.jsRound((now - Double(since)) / 60))
        var text = "Не на связи с \(Fmt.whenShort(since, now: now)) · уже \(Fmt.minutes(m))"
        if let last = d.lastOK, last != since {
            text += " · последний ответ \(Fmt.whenShort(last, now: now))"
        }
        return text
    }
}

public enum Summary {
    public static let directName = "Напрямую (без VPN)"
    public static let checkingTitle = "Проверяю…"
    public static let splitWarningText = "В PassWall выбран не узел Split: правило прямых сайтов не работает, а смена сервера здесь ни на что не повлияет. Выбери Split в Basic Settings → Node."
    public static let emptyEvents = "Событий пока нет. Здесь появятся смены сервера, перезагрузки, сбои VPN и новые устройства."
    public static let emptyChart = "данных за этот период пока нет"
    public static let todayCaption = "Все устройства дома, с полуночи"
    public static let noName = "Без имени"

    public static func title(for level: Tone) -> String {
        switch level {
        case .ok:
            return "Всё работает"
        case .warn:
            return "Требует внимания"
        case .err:
            return "Есть проблема"
        case .info, .neutral:
            return checkingTitle
        }
    }

    // MARK: - Verdict (§4.2)

    /// - Parameters:
    ///   - status: the last successful `/status` (or ping job result), `nil` if none yet.
    ///   - isOffline: offline mode (§7.5).
    ///   - firstLoadFinished: the first `/status` attempt has finished (success or error).
    public static func verdict(status: RouterStatus?, isOffline: Bool, firstLoadFinished: Bool, now: TimeInterval) -> Verdict {
        if status == nil && !isOffline && !firstLoadFinished {
            return Verdict(level: .neutral, title: checkingTitle, items: [], splitWarning: nil, showsCurrentServer: false)
        }
        guard let s = status, !isOffline else {
            return Verdict(
                level: .err,
                title: title(for: .err),
                items: [VerdictItem(name: "Роутер", level: .err, text: "не на связи")],
                splitWarning: nil,
                showsCurrentServer: false
            )
        }

        var items: [VerdictItem] = []

        // 1. Роутер
        let y = s.sys
        let ram: Double = y.memTotal > 0 ? 1 - Double(y.memAvail) / Double(y.memTotal) : 0
        let disk: Double = y.diskTotal > 0 ? Double(y.diskUsed) / Double(y.diskTotal) : 0
        var hotText: String? = nil
        if let t = y.temp, t >= 85 {
            hotText = "\(t)°C"
        }
        let routerWarn = ram > 0.9 || disk > 0.9 || hotText != nil
        let routerText: String
        if let h = hotText {
            routerText = h
        } else if ram > 0.9 {
            routerText = "мало памяти"
        } else if disk > 0.9 {
            routerText = "флеш почти полон"
        } else {
            routerText = "в сети"
        }
        items.append(VerdictItem(name: "Роутер", level: routerWarn ? .warn : .ok, text: routerText))

        // 2. VPN
        let p = s.ping
        let socks = p?.socks == true
        let real = p?.real ?? 0
        let vpnOk = s.running && (!socks || real > 0)
        if s.current == "_direct" {
            items.append(VerdictItem(name: "VPN", level: .warn, text: "выключен — всё напрямую"))
        } else if !s.running {
            items.append(VerdictItem(name: "VPN", level: .err, text: "остановлен"))
        } else if !vpnOk {
            items.append(VerdictItem(name: "VPN", level: .err, text: "не проходит"))
        } else if real > 250 {
            items.append(VerdictItem(name: "VPN", level: .warn, text: "работает"))
        } else {
            items.append(VerdictItem(name: "VPN", level: .ok, text: "работает"))
        }

        // 3. Интернет
        let base = s.svc["direct"]?.base ?? 0
        let net = vpnOk || base > 0
        items.append(VerdictItem(name: "Интернет", level: net ? .ok : .err, text: net ? "есть" : "нет"))

        // 4. Серверы
        if let ping = p {
            let alive = ping.nodes.filter { $0.ms > 0 }.count
            let level: Tone = alive >= 2 ? .ok : (alive == 1 ? .warn : .err)
            items.append(VerdictItem(name: "Серверы", level: level, text: "\(alive)" + Fmt.nbsp + "из" + Fmt.nbsp + "\(ping.nodes.count)"))
        } else {
            items.append(VerdictItem(name: "Серверы", level: .warn, text: "ещё не проверены"))
        }

        // 5. Сервисы
        let t = s.targets?.list ?? []
        if !t.isEmpty {
            let bad = t.filter { !(($0.vpn ?? 0) > 0) }
            if bad.isEmpty {
                items.append(VerdictItem(name: "Сервисы", level: .ok, text: "отвечают"))
            } else {
                let names = bad.map { $0.name }.joined(separator: ", ")
                items.append(VerdictItem(name: "Сервисы", level: .warn, text: "нет ответа: " + names))
            }
        }

        // 6. Подписка
        if let sub = pickSubscription(s), let left = daysLeft(sub, now: now), left <= 3 {
            if left < 1 {
                items.append(VerdictItem(name: "Подписка", level: .err, text: "закончилась"))
            } else {
                items.append(VerdictItem(name: "Подписка", level: .warn, text: "осталось \(left)" + Fmt.nbsp + "дн."))
            }
        }

        // 7. why
        var splitWarning: String? = nil
        if !s.splitActive {
            items.append(VerdictItem(name: nil, level: .warn, text: "в PassWall выбран не Split"))
            splitWarning = splitWarningText
        }

        let worst: Tone
        if items.contains(where: { $0.level == .err }) {
            worst = .err
        } else if items.contains(where: { $0.level == .warn }) {
            worst = .warn
        } else {
            worst = .ok
        }
        return Verdict(level: worst, title: title(for: worst), items: items, splitWarning: splitWarning, showsCurrentServer: true)
    }

    // MARK: - Subscription (§4.2 step 6, §4.8)

    /// From `subs` keep items with a non-zero `expire`, take the earliest; else `status.sub`.
    public static func pickSubscription(_ s: RouterStatus) -> SubscriptionPick? {
        var best: SubscriptionItem? = nil
        for item in s.subs ?? [] {
            let e = item.expire ?? 0
            if e == 0 {
                continue
            }
            if let b = best, (b.expire ?? 0) <= e {
                continue
            }
            best = item
        }
        if let b = best {
            return SubscriptionPick(name: b.name, title: b.name, expire: b.expire ?? 0, up: b.up ?? 0, down: b.down ?? 0, total: b.total ?? 0)
        }
        if let sub = s.sub {
            return SubscriptionPick(name: nil, title: sub.title, expire: sub.expire, up: sub.up, down: sub.down, total: sub.total)
        }
        return nil
    }

    /// `floor((expire - now) / 86400)` when `expire > 0`, else `nil`.
    public static func daysLeft(_ sub: SubscriptionPick, now: TimeInterval) -> Int? {
        guard sub.expire > 0 else {
            return nil
        }
        let d = ((Double(sub.expire) - now) / 86400).rounded(.down)
        guard d.isFinite, abs(d) < 1.0e15 else {
            return nil
        }
        return Int(d)
    }

    /// The subscription line, or `nil` when there is no expiry.
    public static func subscriptionLine(_ s: RouterStatus, now: TimeInterval) -> SubscriptionLine? {
        guard let sub = pickSubscription(s), let left = daysLeft(sub, now: now) else {
            return nil
        }
        let many = (s.subs ?? []).count > 1
        let prefix: String
        if many {
            var display = sub.name ?? sub.title
            if display.isEmpty {
                display = "Подписка"
            }
            prefix = "«\(display)» до "
        } else {
            prefix = "Подписка до "
        }
        let date = Fmt.dayMonth(sub.expire)
        var usage: String? = nil
        if sub.down > 0 {
            var u = " · израсходовано \(Fmt.bytes(sub.down + sub.up))"
            if sub.total > 0 {
                u += " из \(Fmt.bytes(sub.total))"
            } else {
                u += ", без лимита"
            }
            usage = u
        }
        let text = prefix + date + " · осталось \(left)" + Fmt.nbsp + "дн." + (usage ?? "")
        return SubscriptionLine(prefix: prefix, date: date, daysLeft: left, daysLeftIsCritical: left <= 3, usage: usage, text: text)
    }

    // MARK: - Current server (§4.3)

    public static func currentServer(_ s: RouterStatus) -> CurrentServer {
        let id = s.current
        if id == "_direct" || id == "direct" {
            return CurrentServer(name: directName, tag: "без VPN", isDirect: true)
        }
        if id.isEmpty {
            return CurrentServer(name: "—", tag: nil, isDirect: false)
        }
        if let node = s.ping?.nodes.first(where: { $0.id == id }) {
            var tag: String? = nil
            if node.own {
                tag = "свой"
            } else if !node.group.isEmpty {
                tag = "Подписка \(node.group)"
            }
            let name = node.name.isEmpty ? id : node.name
            return CurrentServer(name: name, tag: tag, isDirect: false)
        }
        return CurrentServer(name: id, tag: nil, isDirect: false)
    }

    // MARK: - VPN check (§4.4)

    public static func latency(_ s: RouterStatus?, now: TimeInterval) -> LatencyTile {
        guard let p = s?.ping else {
            return LatencyTile(value: "—", tone: .neutral, footer: nil)
        }
        var value = "—"
        var tone = Tone.neutral
        if p.socks == true {
            let real = p.real ?? 0
            if real > 0 {
                value = Fmt.ms(real)
                tone = Fmt.msTone(real)
            } else {
                value = "VPN не проходит"
                tone = .err
            }
        }
        var footer: String? = nil
        if let u = p.updated, u > 0 {
            footer = "Проверено " + Fmt.ago(u, now: now)
        }
        return LatencyTile(value: value, tone: tone, footer: footer)
    }

    // MARK: - Services (§4.5)

    /// From `targets.list` if non-empty, else parsed from `target_list` ("kind|name|addr").
    public static func serviceList(_ s: RouterStatus) -> [ServiceRef] {
        let t = s.targets?.list ?? []
        if !t.isEmpty {
            return t.map { ServiceRef(name: $0.name, kind: $0.kind, host: $0.host) }
        }
        var out: [ServiceRef] = []
        for line in s.targetList {
            let parts = line.components(separatedBy: "|")
            let kind = parts.count > 0 ? parts[0] : ""
            let name = parts.count > 1 ? parts[1] : ""
            let addr = parts.count > 2 ? parts[2] : ""
            out.append(ServiceRef(name: name, kind: kind, host: Fmt.hostOf(addr)))
        }
        return out
    }

    /// Results for the current server: `targets`, else `svc[current]` (`svc["direct"]` for `_direct`).
    public static func currentResults(_ s: RouterStatus) -> Targets? {
        if let t = s.targets {
            return t
        }
        let key = (s.current == "_direct" || s.current == "direct") ? "direct" : s.current
        return s.svc[key]
    }

    /// Service tiles. Empty → hide the tiles.
    public static func services(_ s: RouterStatus) -> [ServiceTile] {
        let r = currentResults(s)
        return serviceList(s).map { (ref: ServiceRef) -> ServiceTile in
            var value: Int? = nil
            if let res = r?.list.first(where: { $0.name == ref.name }) {
                value = res.vpn
            }
            let text: String
            let tone: Tone
            if let v = value {
                if v > 0 {
                    text = Fmt.ms(v)
                    tone = Fmt.msTone(v)
                } else {
                    text = "нет ответа"
                    tone = .err
                }
            } else {
                text = "—"
                tone = .neutral
            }
            return ServiceTile(
                name: ref.name,
                kind: ref.kind,
                host: ref.host,
                icon: serviceIcon(name: ref.name, host: ref.host, kind: ref.kind),
                value: value,
                valueText: text,
                tone: tone
            )
        }
    }

    /// SF Symbol for a service (`app.js` `svcIcon`).
    public static func serviceIcon(name: String, host: String, kind: String) -> String {
        let h = host.lowercased()
        let n = name.lowercased()
        if hostMatches(h, ["youtube.com", "youtu.be", "googlevideo.com"]) || n == "youtube" {
            return "play.rectangle"
        }
        if hostMatches(h, ["discord.com", "discord.gg", "discordapp.com"]) || n == "discord" {
            return "bubble.left.and.bubble.right"
        }
        if hostMatches(h, ["telegram.org", "t.me", "telegram.me"]) || n == "telegram" {
            return "paperplane"
        }
        if hostMatches(h, ["instagram.com", "cdninstagram.com"]) || n == "instagram" {
            return "camera"
        }
        return kind == "mc" ? "cube" : "globe"
    }

    static func hostMatches(_ host: String, _ domains: [String]) -> Bool {
        for d in domains {
            if host == d || host.hasSuffix("." + d) {
                return true
            }
        }
        return false
    }

    // MARK: - Router block (§4.7)

    public static func meterTone(percent: Int) -> Tone {
        if percent >= 85 {
            return .err
        }
        if percent >= 65 {
            return .warn
        }
        return .ok
    }

    static func clampPercent(_ p: Int) -> Int {
        return min(100, max(0, p))
    }

    /// «Процессор», «Оперативная память», «Флеш-память».
    public static func meters(_ y: SystemInfo) -> [Meter] {
        let cpu = clampPercent(y.cpu)
        let ramUsed = max(0, y.memTotal - y.memAvail)
        let ramPct = clampPercent(y.memTotal > 0 ? Fmt.jsRound(Double(ramUsed) / Double(y.memTotal) * 100) : 0)
        let diskPct = clampPercent(y.diskTotal > 0 ? Fmt.jsRound(Double(y.diskUsed) / Double(y.diskTotal) * 100) : 0)
        return [
            Meter(title: "Процессор", percent: cpu, caption: "Средняя нагрузка \(Fmt.loadText(y.load)) · ядер: \(y.cores)", tone: meterTone(percent: cpu)),
            Meter(title: "Оперативная память", percent: ramPct, caption: "\(Fmt.mb(Double(ramUsed))) из \(Fmt.mb(Double(y.memTotal)))", tone: meterTone(percent: ramPct)),
            Meter(title: "Флеш-память", percent: diskPct, caption: "\(Fmt.mb(Double(y.diskUsed))) из \(Fmt.mb(Double(y.diskTotal))): пакеты и настройки", tone: meterTone(percent: diskPct))
        ]
    }

    /// Optional «Временные файлы» meter.
    public static func tmpMeter(_ y: SystemInfo) -> Meter {
        let pct = clampPercent(y.tmpTotal > 0 ? Fmt.jsRound(Double(y.tmpUsed) / Double(y.tmpTotal) * 100) : 0)
        return Meter(title: "Временные файлы", percent: pct, caption: "\(Fmt.mb(Double(y.tmpUsed))) из \(Fmt.mb(Double(y.tmpTotal)))", tone: meterTone(percent: pct))
    }

    /// «Температура» and «Работает без перезагрузки».
    public static func routerFacts(_ y: SystemInfo) -> [Fact] {
        return [
            Fact(label: "Температура", value: Fmt.temperature(y.temp)),
            Fact(label: "Работает без перезагрузки", value: Fmt.uptime(y.uptime))
        ]
    }

    /// Header: `sys.model` or «Роутер».
    public static func routerTitle(_ y: SystemInfo) -> String {
        let m = y.model.trimmingCharacters(in: .whitespacesAndNewlines)
        return m.isEmpty ? "Роутер" : m
    }

    // MARK: - Devices (§4.11)

    public static func onlineCount(_ s: RouterStatus) -> Int {
        return s.devices.filter { $0.online }.count
    }

    /// «3 в сети» (NBSP after the number).
    public static func onlineText(_ s: RouterStatus) -> String {
        return "\(onlineCount(s))" + Fmt.nbsp + "в сети"
    }

    /// Top online devices by today's ↓ traffic. Name: own name, else DHCP name, else «Без имени».
    public static func topOnlineDevices(_ s: RouterStatus, data: DataResponse?, limit: Int = 4) -> [DeviceRow] {
        var rows: [DeviceRow] = []
        for d in s.devices where d.online {
            let mac = d.mac.lowercased()
            var name = data?.names[mac] ?? ""
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                name = d.name
            }
            if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                name = noName
            }
            let down = data?.traffic[mac]?.dayDown ?? 0
            rows.append(DeviceRow(name: name, mac: mac, ip: d.ip, todayDown: down))
        }
        let indexed = Array(rows.enumerated())
        let sorted = indexed.sorted { a, b in
            if a.element.todayDown != b.element.todayDown {
                return a.element.todayDown > b.element.todayDown
            }
            return a.offset < b.offset
        }
        return Array(sorted.prefix(max(0, limit)).map { $0.element })
    }

    // MARK: - Traffic today (§4.6)

    public static func trafficToday(_ d: DataResponse) -> TrafficToday {
        var down = 0
        var up = 0
        for (_, entry) in d.traffic {
            down += entry.dayDown
            up += entry.dayUp
        }
        return TrafficToday(down: down, up: up)
    }

    // MARK: - Events (§4.10)

    /// `app.js` `LEVEL`.
    public static func eventLevel(kind: String) -> Tone {
        switch kind {
        case "offline", "vpn_down":
            return .err
        case "auto", "xraymem", "reboot", "newdev":
            return .warn
        case "online", "vpn_up":
            return .ok
        default:
            return .info
        }
    }

    public static func chipLabel(_ level: Tone) -> String {
        switch level {
        case .err:
            return "Ошибка"
        case .warn:
            return "Внимание"
        case .ok:
            return "Успех"
        case .info, .neutral:
            return "Действие"
        }
    }

    /// The first `limit` events (already newest first).
    public static func recentEvents(_ d: DataResponse, now: TimeInterval, limit: Int = 5) -> [EventRow] {
        return d.events.prefix(max(0, limit)).map { (e: DataEvent) -> EventRow in
            let level = eventLevel(kind: e.kind)
            return EventRow(
                ts: e.ts,
                time: Fmt.when(e.ts, now: now),
                kind: e.kind,
                level: level,
                chip: chipLabel(level),
                text: Fmt.replaceDirect(e.text)
            )
        }
    }

    // MARK: - Mini chart (§4.9)

    /// Builds the chart for the last 24 h from `data.points` (or `status.history` as a fallback).
    public static func chart(points: [DataPoint], now: TimeInterval) -> MiniChart {
        let to = Int(now.rounded(.down))
        let from = to - 86400
        let pts = points.filter { $0.ts >= from }
        var maxOk = 0
        for p in pts where p.ms > 0 && p.ms > maxOk {
            maxOk = p.ms
        }
        let yMax = Double(max(150, maxOk)) * 1.15
        var segments: [[ChartSample]] = []
        var seg: [ChartSample] = []
        var fails: [Int] = []
        var offline: [Int] = []
        var prevTs: Int? = nil
        for p in pts {
            if p.ms > 0 {
                if let prev = prevTs, p.ts - prev > MiniChart.gapBreak, !seg.isEmpty {
                    segments.append(seg)
                    seg = []
                }
                seg.append(ChartSample(ts: p.ts, ms: p.ms))
                if (p.fails ?? 0) > 0 {
                    fails.append(p.ts)
                }
            } else {
                if !seg.isEmpty {
                    segments.append(seg)
                    seg = []
                }
                if p.ms < 0 {
                    offline.append(p.ts)
                } else {
                    fails.append(p.ts)
                }
            }
            prevTs = p.ts
        }
        if !seg.isEmpty {
            segments.append(seg)
        }
        return MiniChart(from: from, to: to, yMax: yMax, segments: segments, failMarks: fails, offlineBands: offline, isEmpty: pts.isEmpty)
    }

    /// «Средняя», «Лучшая», «Худшая», «Сбоев», «Без связи».
    public static func statsFacts(_ st: DataStats) -> [Fact] {
        func msText(_ v: Int?) -> String {
            guard let v = v else {
                return "—"
            }
            return Fmt.ms(v)
        }
        return [
            Fact(label: "Средняя", value: msText(st.avg)),
            Fact(label: "Лучшая", value: msText(st.min)),
            Fact(label: "Худшая", value: msText(st.max)),
            Fact(label: "Сбоев", value: "\(st.fails)"),
            Fact(label: "Без связи", value: Fmt.minutes(st.offlineMin))
        ]
    }

    // MARK: - Misc

    /// «обновлено …» from the last successful `/status` (or ping job result).
    public static func updatedLabel(lastSuccess: TimeInterval?, now: TimeInterval) -> String? {
        guard let t = lastSuccess else {
            return nil
        }
        return Fmt.updatedLabel(secondsAgo: Fmt.jsRound(now - t))
    }

    /// Contract §7.4: `ping.socks == true && ping.real == 0`.
    public static func needsPingPreDialog(_ s: RouterStatus?) -> Bool {
        return PingPreDialog.isNeeded(s)
    }
}
