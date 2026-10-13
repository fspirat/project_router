import Foundation

// «VPN» tab rules (contract-stage4 §5.1), ported from web/app.js renderServers / subsList / renderSpeedCard /
// renderSpeedHist / renderChart and tgbot.php cmd_vds.

// MARK: - Sorting

public enum ServerSortKey: Hashable, Sendable {
    case ping
    case name
    /// A service column (by its name).
    case service(String)
}

/// Server list sort (app.js:244-249). Store `storageValue` in `@AppStorage("vpnSort")`.
public struct ServerSort: Equatable, Sendable {
    public var key: ServerSortKey
    public var ascending: Bool

    public static let `default` = ServerSort(key: .ping, ascending: true)

    public init(key: ServerSortKey, ascending: Bool = true) {
        self.key = key
        self.ascending = ascending
    }

    /// `"ping"`, `"name"`, `"svc:YouTube"`; a leading `-` = descending. Unknown → default.
    public init(storage: String) {
        var s = Substring(storage)
        var asc = true
        if s.hasPrefix("-") {
            asc = false
            s = s.dropFirst()
        }
        if s == "ping" {
            self.init(key: .ping, ascending: asc)
        } else if s == "name" {
            self.init(key: .name, ascending: asc)
        } else if s.hasPrefix("svc:") && s.count > 4 {
            self.init(key: .service(String(s.dropFirst(4))), ascending: asc)
        } else {
            self = .default
        }
    }

    public var storageValue: String {
        let base: String
        switch key {
        case .ping:
            base = "ping"
        case .name:
            base = "name"
        case .service(let n):
            base = "svc:" + n
        }
        return (ascending ? "" : "-") + base
    }

    /// Tapping the active key flips the direction; another key starts ascending.
    public func tapped(_ k: ServerSortKey) -> ServerSort {
        if k == key {
            return ServerSort(key: k, ascending: !ascending)
        }
        return ServerSort(key: k, ascending: true)
    }

    /// Menu label: «пинг», «имя» or the service name.
    public var label: String {
        switch key {
        case .ping:
            return "пинг"
        case .name:
            return "имя"
        case .service(let n):
            return n
        }
    }
}

// MARK: - Rows

/// One service value in a server row.
public struct ServiceCell: Equatable, Sendable {
    public var service: String
    /// ms; 0 = no answer; `nil` = not measured.
    public var value: Int?
    /// «61», «—» (no answer), «·» (not measured), «блок» (direct row, web site without VPN).
    public var text: String
    public var tone: Tone
    /// The best value of the column (bold / accent).
    public var isBest: Bool
    public var isBlocked: Bool
    /// «ещё не мерили» / «Без VPN этот сайт в России не открывается».
    public var hint: String?
}

/// A row of the server list (a node, or the «Напрямую» row).
public struct VPNServerRow: Equatable, Sendable, Identifiable {
    /// Node id, or `"direct"` for the direct row.
    public var id: String
    /// Trimmed node name; «Напрямую» for the direct row.
    public var name: String
    /// «свой», «без VPN» or `nil`.
    public var tag: String?
    public var isOwn: Bool
    public var isCurrent: Bool
    public var isDirect: Bool
    /// `ms == 0` (no answer); shown dimmed, no service values.
    public var isDead: Bool
    /// Ping ms (direct row: `svc.direct.base`, TCP to ya.ru); 0 = no answer.
    public var ms: Int
    /// «41 мс» or «—».
    public var pingText: String
    public var pingTone: Tone
    /// `cellularbars` level 0–5.
    public var pingLevel: Int
    public var pingIsBest: Bool
    /// One cell per `services()`; empty for dead nodes.
    public var cells: [ServiceCell]
    /// «YouTube 61 · Discord — · Telegram 74»; "" when `cells` is empty.
    public var servicesLine: String
}

public struct VPNServerGroup: Equatable, Sendable, Identifiable {
    public enum Kind: Equatable, Sendable {
        /// «Свои серверы».
        case own
        /// A subscription group (`group` as in PassWall, may be "").
        case subscription(String)
    }

    public var kind: Kind
    /// `nil` = one untitled section (only one subscription group and no own servers).
    public var title: String?
    public var rows: [VPNServerRow]

    public var id: String {
        switch kind {
        case .own:
            return "own"
        case .subscription(let g):
            return "sub:" + g
        }
    }
}

/// The whole server list (contract-stage4 §5.1.3).
public struct VPNServerList: Equatable, Sendable {
    public var services: [ServiceRef]
    /// The effective sort (reset to ping ↑ when the sorted service is gone).
    public var sort: ServerSort
    /// «Свои серверы», then subscription groups.
    public var groups: [VPNServerGroup]
    /// «Не отвечают: N» (collapsed); never own servers.
    public var dead: [VPNServerRow]
    /// «Не отвечают: 2»; "" when `dead` is empty.
    public var deadTitle: String
    /// The «Напрямую» row, if `svc.direct` exists or direct is current.
    public var direct: VPNServerRow?
    /// «Ни один сервер не ответил. Нажми «Проверить».» when there are no own and no alive nodes.
    public var emptyText: String?
    /// «Сервисы через другие серверы меряются раз в 30 минут. Проверено 6 мин назад».
    public var footer: String
}

/// «Лучший сервер для …» chip (app.js:269-275).
public struct BestServerChip: Equatable, Sendable, Identifiable {
    public var service: String
    /// SF Symbol of the service.
    public var icon: String
    public var nodeID: String
    public var nodeName: String
    public var ms: Int
    /// Selected style + checkmark, disabled («Уже подключён»).
    public var isCurrent: Bool
    /// «YouTube: 🇳🇱 Нидерланды 38 мс».
    public var text: String

    public var id: String {
        return service
    }

    /// The action for a tap (nil when current).
    public var action: RouterAction? {
        return isCurrent ? nil : .switchServer(id: nodeID)
    }
}

/// A service line in the server card.
public struct ServiceDetailRow: Equatable, Sendable, Identifiable {
    public var name: String
    public var icon: String
    /// «61 мс», «нет ответа», «ещё не мерили».
    public var valueText: String
    public var tone: Tone

    public var id: String {
        return name
    }
}

/// The server card sheet (contract-stage4 §5.1.4).
public struct VPNServerDetail: Equatable, Sendable {
    public var id: String
    public var name: String
    /// «свой», «Подписка nosok», «без VPN».
    public var tag: String?
    public var isCurrent: Bool
    public var isDirect: Bool
    /// «Подключён сейчас» or `nil`.
    public var currentText: String?
    /// «41 мс» or «нет ответа».
    public var pingText: String
    public var pingTone: Tone
    public var pingLevel: Int
    /// «Проверено 6 мин назад» or «Проверено только что» (after pingone).
    public var checkedText: String?
    public var services: [ServiceDetailRow]
    /// «Замер 30 мин назад».
    public var measuredText: String?
    /// «Проверить сейчас» (`pingone`): not for the direct row.
    public var canPingOne: Bool
    /// «Подключить»: hidden for the current node and the direct row.
    public var canConnect: Bool
    /// «Напрямую, без VPN» (destructive): direct row while not direct.
    public var showsDirectButton: Bool

    /// `pingone` for this server (`nil` for the direct row).
    public var pingAction: RouterAction? {
        return canPingOne ? .pingone(id: id) : nil
    }

    /// The connect action (`switch`), `nil` when hidden.
    public var connectAction: RouterAction? {
        if showsDirectButton {
            return .switchDirect
        }
        return canConnect ? .switchServer(id: id) : nil
    }
}

/// A switch history row (contract-stage4 §5.1.5).
public struct SwitchHistoryRow: Equatable, Sendable, Identifiable {
    /// `nil` for a `status.log` fallback line.
    public var ts: Int?
    /// «сегодня 14:10» or the raw «13.10 13:20» of a log line.
    public var time: String
    public var level: Tone
    /// «Внимание» (auto) / «Действие» (manual).
    public var chip: String
    /// «Автопереключение: fspiratDE → fspiratNL 41 мс».
    public var text: String
    public var id: String
}

/// A subscription in the «Подписки» card (contract-stage4 §5.1.7).
public struct SubscriptionRow: Equatable, Sendable, Identifiable {
    /// `sid`; "" for the synthetic item built from `status.sub`.
    public var id: String
    public var name: String
    public var hwid: Bool
    /// «сервер отсюда подключён».
    public var isCurrentSource: Bool
    /// Host (digits mono), may be "".
    public var host: String
    /// «sub.example.net · 14 серверов · обновлено 16 мин назад».
    public var info: String
    public var daysLeft: Int?
    /// «осталось 17 дн.» / «закончилась».
    public var daysLeftText: String?
    /// `daysLeft <= 3` → err.
    public var daysLeftIsCritical: Bool
    /// «до 31 октября».
    public var expiryText: String?
    /// «израсходовано 39,2 ГБ из 200,0 ГБ» / «израсходовано 1,0 ГБ · без лимита».
    public var usageText: String?
    /// Progress (when `total > 0`): 0–100.
    public var percent: Int?
    /// acc / warn ≥ 65 / err ≥ 85.
    public var barTone: Tone
    /// «Обновить»: `subupdate {sid}` or `{all:true}` for the synthetic item.
    public var updateAction: RouterAction
}

/// A router speed test card (contract-stage4 §5.1.8).
public struct SpeedCardInfo: Equatable, Sendable {
    public var via: SpeedVia
    /// «С роутера, через VPN» / «С роутера, без VPN».
    public var title: String
    /// No result yet → `emptyText` «Ещё не запускали.».
    public var isEmpty: Bool
    public var emptyText: String
    /// «91,2 Мбит/с».
    public var downText: String
    /// «40,1 Мбит/с», «позже» or «—».
    public var upText: String
    /// «38 мс» or «—».
    public var latencyText: String
    public var meta: String
}

public struct SpeedPoint: Equatable, Sendable {
    public var ts: Int
    /// bits/s.
    public var value: Int
    /// «через VPN: 91,2 Мбит/с, сегодня 12:00».
    public var tooltip: String
}

public struct SpeedSeries: Equatable, Sendable, Identifiable {
    public var via: SpeedVia
    /// «через VPN» / «напрямую».
    public var label: String
    /// Oldest first; one line + square points.
    public var points: [SpeedPoint]

    public var id: String {
        return via.rawValue
    }
}

/// «История загрузки, Мбит/с» (app.js:588-601).
public struct SpeedHistoryChart: Equatable, Sendable {
    public var from: Int
    public var to: Int
    /// bits/s.
    public var yMax: Double
    public var series: [SpeedSeries]
    public var isEmpty: Bool
    /// «11.10 08:00 · до 286 Мбит/с» or «История появится после первых тестов».
    public var caption: String
}

/// A row of «Свои серверы» (`/vds`, read-only).
public struct OwnServerRow: Equatable, Sendable, Identifiable {
    public var id: String
    public var name: String
    /// «Здесь же панель».
    public var caption: String?
    public var isReachable: Bool
    /// ok (Xray active) / err.
    public var tone: Tone
    /// «VPN (Xray) работает · соединений 14» or «не отвечает по SSH».
    public var statusLine: String
    /// «Нагрузка 0,08 0,05 0,01 на 2 ядр. · память 35% из 1,9 ГБ · диск 37%».
    public var loadLine: String?
    /// «Без перезагрузки 14 д 0 ч · трафик с запуска ↓855,2 ГБ ↑843,0 ГБ».
    public var uptimeLine: String?
}

public struct OwnServersInfo: Equatable, Sendable {
    public var rows: [OwnServerRow]
    /// «Данные свежие.» / «Данные 2 мин назад.» / «Данных о серверах пока нет — они собираются раз в 5 минут.».
    public var footer: String
}

public enum VPNMode: Equatable, Sendable {
    case vpn
    case direct
}

public enum VPNTexts {
    public static let title = "VPN"
    public static let modeVPN = "Через VPN"
    public static let modeDirect = "Напрямую"
    /// (proposed) Tap «Через VPN» while direct.
    public static let chooseServerHint = "Выбери сервер ниже — VPN включится, когда подключишь его."
    /// (proposed) Extra line in the switch dialog when `split_active == false`.
    public static let splitSwitchWarning = "В PassWall выбран не узел Split — смена сервера ни на что не повлияет."
    public static let bestTitle = "Лучший сервер для"
    public static let ownGroup = "Свои серверы"
    public static let emptyServers = "Ни один сервер не ответил. Нажми «Проверить»."
    public static let directCaption = "Пинг — до ya.ru"
    public static let measuredEvery = "Сервисы через другие серверы меряются раз в 30 минут."
    /// (proposed)
    public static let svcRunning = "Сервисы перемеряются…"
    public static let connect = "Подключить"
    public static let pingNow = "Проверить сейчас"
    public static let pingBusy = "Проверяю…"
    public static let directButton = "Напрямую, без VPN"
    public static let currentNow = "Подключён сейчас"
    /// (proposed)
    public static let lastKnown = "Последние известные данные роутера"
    /// (proposed) Cold start offline.
    public static let noStatus = "Роутер не на связи — список серверов появится, когда он вернётся."
    /// (proposed)
    public static let noSwitches = "Смен сервера за этот период не было."
    /// (proposed)
    public static let allInJournal = "Все в журнале"
    public static let subscriptionsTitle = "Подписки"
    /// (proposed)
    public static let updateAll = "Обновить все"
    public static let update = "Обновить"
    /// (proposed)
    public static let subscriptionsFooter = "Добавить или удалить подписку можно в веб-панели."
    /// (proposed)
    public static let noSubscriptions = "Подписок нет. Добавить подписку можно в веб-панели."
    public static let hwidHint = "Подписка получает HWID — идентификатор роутера как устройства"
    public static let speedRun = "Запустить"
    public static let speedBusy = "Идёт тест, ~35 сек…"
    public static let speedCaption = "Тест займёт интернет дома примерно на 35 секунд. Тест через VPN тратит трафик подписки. Загрузка «напрямую» — с Selectel (Россия), «через VPN» — с Hetzner (Германия), отдача — на Cloudflare."
    public static let speedHistoryTitle = "История загрузки, Мбит/с"
    public static let speedHistoryEmpty = "История появится после первых тестов"
    /// (proposed)
    public static let ownServersTitle = "Свои серверы"
    public static let connectionTitle = "Связь"
}

public enum VPN {
    // MARK: Basics (app.js:143-158)

    /// `services()`: from `targets.list` if non-empty, else parsed from `target_list`.
    public static func services(_ s: RouterStatus) -> [ServiceRef] {
        return Summary.serviceList(s)
    }

    /// `svcOf(id)`: `direct` → `_direct`; `targets` for the current node (when present), else `svc[id]`
    /// (`svc.direct` for `_direct`); `nil` unless it has a list.
    public static func svcOf(_ s: RouterStatus, _ id: String) -> Targets? {
        let key = id == "direct" ? "_direct" : id
        let r: Targets?
        if key == s.current, let t = s.targets {
            r = t
        } else {
            r = s.svc[key == "_direct" ? "direct" : key]
        }
        guard let res = r, !res.list.isEmpty else {
            return nil
        }
        return res
    }

    /// `svcVal(r, name)`: ms (0 = no answer), `nil` = not measured.
    public static func svcVal(_ r: Targets?, _ name: String) -> Int? {
        return r?.list.first(where: { $0.name == name })?.vpn
    }

    /// `nodeName(id)`: «Напрямую (без VPN)» for `_direct`/`direct`, else the trimmed node name, else the id.
    public static func nodeName(_ s: RouterStatus?, _ id: String) -> String {
        if id == "_direct" || id == "direct" {
            return Summary.directName
        }
        if let n = s?.ping?.nodes.first(where: { $0.id == id }) {
            let name = Fmt.nodeDisplayName(n.name)
            return name.isEmpty ? id : name
        }
        return id
    }

    /// Segmented control value.
    public static func mode(_ s: RouterStatus) -> VPNMode {
        return s.current == "_direct" ? .direct : .vpn
    }

    /// «Подключён: <name>» + tag (Summary rules).
    public static func connected(_ s: RouterStatus) -> CurrentServer {
        return Summary.currentServer(s)
    }

    /// The Split warning box text, or `nil` when Split is active.
    public static func splitWarning(_ s: RouterStatus) -> String? {
        return s.splitActive ? nil : Summary.splitWarningText
    }

    // MARK: Server list

    public static func serverList(_ s: RouterStatus, sort requested: ServerSort = .default, now: TimeInterval) -> VPNServerList {
        let nodes = s.ping?.nodes ?? []
        let sv = services(s)
        var sort = requested
        if case .service(let name) = sort.key, !sv.contains(where: { $0.name == name }) {
            sort = .default
        }
        let alive = stableSorted(nodes.filter { $0.ms > 0 }) { $0.ms < $1.ms }
        let dead = nodes.filter { $0.ms <= 0 && !$0.own }

        // Best per column among alive VPN servers.
        let bestPing = alive.map { $0.ms }.min() ?? 0
        var best: [String: Int] = [:]
        for x in sv {
            let values = alive.compactMap { svcVal(svcOf(s, $0.id), x.name) }.filter { $0 > 0 }
            best[x.name] = values.min() ?? 0
        }

        func row(_ n: PingNode) -> VPNServerRow {
            let off = !(n.ms > 0)
            let r = off ? nil : svcOf(s, n.id)
            var cells: [ServiceCell] = []
            if !off {
                for x in sv {
                    let v = r.flatMap { svcVal($0, x.name) }
                    let b = best[x.name] ?? 0
                    cells.append(cell(service: x.name, value: v, isBest: v != nil && v == b && b > 0, blocked: false))
                }
            }
            let name = Fmt.nodeDisplayName(n.name)
            return VPNServerRow(
                id: n.id,
                name: name.isEmpty ? n.id : name,
                tag: n.own ? "свой" : nil,
                isOwn: n.own,
                isCurrent: n.id == s.current,
                isDirect: false,
                isDead: off,
                ms: n.ms,
                pingText: n.ms > 0 ? Fmt.ms(n.ms) : "—",
                pingTone: n.ms > 0 ? Fmt.msTone(n.ms) : .err,
                pingLevel: Fmt.pingLevel(n.ms),
                pingIsBest: n.ms > 0 && n.ms == bestPing,
                cells: cells,
                servicesLine: servicesLine(cells)
            )
        }

        let cmp = comparator(s, sort)
        let own = stableSorted(nodes.filter { $0.own }, cmp)
        let sub = alive.filter { !$0.own }
        var groupNames: [String] = []
        for n in sub where !groupNames.contains(n.group) {
            groupNames.append(n.group)
        }
        let titled = !own.isEmpty || groupNames.count > 1
        var groups: [VPNServerGroup] = []
        if !own.isEmpty {
            groups.append(VPNServerGroup(kind: .own, title: VPNTexts.ownGroup, rows: own.map(row)))
        }
        for g in groupNames {
            let members = stableSorted(sub.filter { $0.group == g }, cmp)
            groups.append(VPNServerGroup(
                kind: .subscription(g),
                title: titled ? (g.isEmpty ? "Подписка" : "Подписка " + g) : nil,
                rows: members.map(row)
            ))
        }

        // «Напрямую» row (app.js:256-259).
        var directRow: VPNServerRow? = nil
        let dir = s.svc["direct"]
        let dcur = s.current == "_direct"
        if dir != nil || dcur {
            let src: Targets? = (dcur && s.targets != nil) ? s.targets : dir
            var cells: [ServiceCell] = []
            for x in sv {
                let v: Int? = dir != nil ? svcVal(src, x.name) : nil
                let blocked = x.kind == "web" && !dcur && v == 0
                cells.append(cell(service: x.name, value: v, isBest: false, blocked: blocked))
            }
            let base = dir?.base ?? 0
            directRow = VPNServerRow(
                id: "direct",
                name: "Напрямую",
                tag: "без VPN",
                isOwn: false,
                isCurrent: dcur,
                isDirect: true,
                isDead: false,
                ms: base,
                pingText: base > 0 ? Fmt.ms(base) : "—",
                pingTone: base > 0 ? Fmt.msTone(base) : .err,
                pingLevel: Fmt.pingLevel(base),
                pingIsBest: false,
                cells: cells,
                servicesLine: servicesLine(cells)
            )
        }

        let deadRows = dead.map(row)
        return VPNServerList(
            services: sv,
            sort: sort,
            groups: groups,
            dead: deadRows,
            deadTitle: deadRows.isEmpty ? "" : "Не отвечают: \(deadRows.count)",
            direct: directRow,
            emptyText: groups.isEmpty ? VPNTexts.emptyServers : nil,
            footer: serverFooter(s, now: now)
        )
    }

    /// «Сервисы через другие серверы меряются раз в 30 минут. Проверено 6 мин назад» (+ «Сервисы перемеряются…»).
    public static func serverFooter(_ s: RouterStatus, now: TimeInterval) -> String {
        var parts: [String] = [VPNTexts.measuredEvery]
        if let u = s.ping?.updated, u > 0 {
            parts.append("Проверено " + Fmt.ago(u, now: now))
        }
        var text = parts.joined(separator: " ")
        if s.svcRunning {
            text += " " + VPNTexts.svcRunning
        }
        return text
    }

    /// «Лучший сервер для …» chips (no chip for a service without an alive measured node).
    public static func bestChips(_ s: RouterStatus) -> [BestServerChip] {
        let nodes = s.ping?.nodes ?? []
        let alive = nodes.filter { $0.ms > 0 }
        var out: [BestServerChip] = []
        for x in services(s) {
            var bestNode: PingNode? = nil
            var bestValue = 0
            for n in alive {
                guard let v = svcVal(svcOf(s, n.id), x.name), v > 0 else {
                    continue
                }
                if bestNode == nil || v < bestValue {
                    bestNode = n
                    bestValue = v
                }
            }
            guard let b = bestNode else {
                continue
            }
            let name = Fmt.nodeDisplayName(b.name)
            out.append(BestServerChip(
                service: x.name,
                icon: Summary.serviceIcon(name: x.name, host: x.host, kind: x.kind),
                nodeID: b.id,
                nodeName: name,
                ms: bestValue,
                isCurrent: b.id == s.current,
                text: "\(x.name): \(name) \(Fmt.ms(bestValue))"
            ))
        }
        return out
    }

    /// The server card for a node id or `"direct"`; `nil` when the node is unknown.
    /// - Parameter pingedAt: when this app last ran `pingone` for it (→ «Проверено только что»).
    public static func serverDetail(_ s: RouterStatus, id: String, now: TimeInterval, pingedAt: TimeInterval? = nil) -> VPNServerDetail? {
        let sv = services(s)
        if id == "direct" || id == "_direct" {
            let dcur = s.current == "_direct"
            let dir = s.svc["direct"]
            let src: Targets? = (dcur && s.targets != nil) ? s.targets : dir
            let base = dir?.base ?? 0
            let rows = sv.map { x -> ServiceDetailRow in
                let v = svcVal(src, x.name)
                if x.kind == "web" && !dcur && v == 0 {
                    return ServiceDetailRow(name: x.name, icon: Summary.serviceIcon(name: x.name, host: x.host, kind: x.kind), valueText: "не открывается без VPN", tone: .neutral)
                }
                return detailRow(x, v)
            }
            return VPNServerDetail(
                id: "direct",
                name: Summary.directName,
                tag: "без VPN",
                isCurrent: dcur,
                isDirect: true,
                currentText: dcur ? VPNTexts.currentNow : nil,
                pingText: base > 0 ? Fmt.ms(base) : "нет ответа",
                pingTone: base > 0 ? Fmt.msTone(base) : .err,
                pingLevel: Fmt.pingLevel(base),
                checkedText: (dir?.ts).map { "Проверено " + Fmt.ago($0, now: now) },
                services: rows,
                measuredText: (src?.ts).map { "Замер " + Fmt.ago($0, now: now) },
                canPingOne: false,
                canConnect: false,
                showsDirectButton: !dcur
            )
        }
        guard let n = s.ping?.nodes.first(where: { $0.id == id }) else {
            return nil
        }
        let off = !(n.ms > 0)
        let r = svcOf(s, n.id)
        let rows = sv.map { x -> ServiceDetailRow in
            if off {
                return ServiceDetailRow(name: x.name, icon: Summary.serviceIcon(name: x.name, host: x.host, kind: x.kind), valueText: "сервер не отвечает", tone: .neutral)
            }
            return detailRow(x, svcVal(r, x.name))
        }
        var tag: String? = nil
        if n.own {
            tag = "свой"
        } else if !n.group.isEmpty {
            tag = "Подписка " + n.group
        }
        var checked: String? = nil
        if let p = pingedAt, now - p < 60 {
            checked = "Проверено только что"
        } else if let u = s.ping?.updated, u > 0 {
            checked = "Проверено " + Fmt.ago(u, now: now)
        }
        let isCur = n.id == s.current
        let name = Fmt.nodeDisplayName(n.name)
        return VPNServerDetail(
            id: n.id,
            name: name.isEmpty ? n.id : name,
            tag: tag,
            isCurrent: isCur,
            isDirect: false,
            currentText: isCur ? VPNTexts.currentNow : nil,
            pingText: n.ms > 0 ? Fmt.ms(n.ms) : "нет ответа",
            pingTone: n.ms > 0 ? Fmt.msTone(n.ms) : .err,
            pingLevel: Fmt.pingLevel(n.ms),
            checkedText: checked,
            services: rows,
            measuredText: off ? nil : (r?.ts).map { "Замер " + Fmt.ago($0, now: now) },
            canPingOne: Validation.isValidNodeID(n.id) && n.id != "direct",
            canConnect: !isCur,
            showsDirectButton: false
        )
    }

    // MARK: Switch history (§5.1.5)

    /// `auto`/`manual` events of `data` (newest first, at most `limit`); without data — `status.log` lines.
    public static func switchHistory(data: DataResponse?, status: RouterStatus?, now: TimeInterval, limit: Int = 5) -> [SwitchHistoryRow] {
        if let d = data {
            var out: [SwitchHistoryRow] = []
            for (i, e) in d.events.enumerated() where e.kind == "auto" || e.kind == "manual" {
                if out.count >= limit {
                    break
                }
                let level: Tone = e.kind == "auto" ? .warn : .info
                out.append(SwitchHistoryRow(
                    ts: e.ts,
                    time: Fmt.when(e.ts, now: now),
                    level: level,
                    chip: Summary.chipLabel(level),
                    text: Fmt.eventDisplayText(e.text),
                    id: "\(e.ts)-\(i)"
                ))
            }
            return out
        }
        return switchHistoryFromLog(status, limit: limit)
    }

    /// Fallback (app.js:397-400): `status.log` lines «ДД.ММ ЧЧ:ММ текст» whose text starts with «авто» or «вручную»,
    /// newest first; 8-character ids → node names, `_direct` → «Напрямую (без VPN)».
    public static func switchHistoryFromLog(_ status: RouterStatus?, limit: Int = 5) -> [SwitchHistoryRow] {
        guard let s = status else {
            return []
        }
        var out: [SwitchHistoryRow] = []
        for (i, line) in s.log.enumerated().reversed() {
            let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 3, out.count < limit else {
                continue
            }
            let text = parts[2]
            let lower = text.lowercased()
            guard lower.hasPrefix("авто") || lower.hasPrefix("вручную") else {
                continue
            }
            let level: Tone = lower.hasPrefix("авто") ? .warn : .info
            out.append(SwitchHistoryRow(
                ts: nil,
                time: parts[0] + " " + parts[1],
                level: level,
                chip: Summary.chipLabel(level),
                text: Fmt.eventDisplayText(replaceNodeIDs(text, s)),
                id: "log-\(i)"
            ))
        }
        return out
    }

    /// `\b[A-Za-z0-9]{8}\b` → node name (when known).
    public static func replaceNodeIDs(_ text: String, _ s: RouterStatus) -> String {
        var byID: [String: String] = [:]
        for n in s.ping?.nodes ?? [] {
            byID[n.id] = Fmt.nodeDisplayName(n.name)
        }
        guard let re = try? NSRegularExpression(pattern: "\\b[A-Za-z0-9]{8}\\b") else {
            return text
        }
        let ns = text as NSString
        var out = ""
        var last = 0
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            let id = ns.substring(with: m.range)
            out += byID[id].flatMap { $0.isEmpty ? nil : $0 } ?? id
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }

    // MARK: Subscriptions (§5.1.7)

    /// `subsList()` (app.js:766-770) with presentation.
    public static func subscriptions(_ s: RouterStatus, now: TimeInterval) -> [SubscriptionRow] {
        let nodes = s.ping?.nodes ?? []
        let cur = nodes.first(where: { $0.id == s.current })
        var items: [SubscriptionItem] = []
        if let subs = s.subs {
            items = subs
        } else if let sub = s.sub {
            var it = SubscriptionItem(json: .object([:]))
            it.id = ""
            it.name = sub.title.isEmpty ? "Подписка" : sub.title
            it.nodes = nodes.filter { !$0.own }.count
            it.ts = sub.ts
            it.up = sub.up
            it.down = sub.down
            it.total = sub.total
            it.expire = sub.expire
            items = [it]
        }
        return items.map { x -> SubscriptionRow in
            var left: Int? = nil
            if let e = x.expire, e > 0 {
                left = Summary.daysLeft(SubscriptionPick(name: x.name, title: x.name, expire: e, up: 0, down: 0, total: 0), now: now)
            }
            let used = (x.down ?? 0) + (x.up ?? 0)
            let total = x.total ?? 0
            var pct: Int? = nil
            if total > 0 {
                pct = min(100, Fmt.jsRound(Double(used) / Double(total) * 100))
            }
            var info: [String] = []
            if !x.host.isEmpty {
                info.append(x.host)
            }
            info.append(Fmt.count(x.nodes, "сервер", "сервера", "серверов"))
            if let ts = x.ts, ts > 0 {
                info.append("обновлено " + Fmt.ago(ts, now: now))
            }
            var usage: String? = nil
            if used > 0 {
                usage = "израсходовано " + Fmt.bytes(used) + (total > 0 ? " из " + Fmt.bytes(total) : " · без лимита")
            }
            var leftText: String? = nil
            if let l = left {
                leftText = l < 1 ? "закончилась" : "осталось \(l)" + Fmt.nbsp + "дн."
            }
            let isCur = cur.map { !$0.own && $0.group == x.name } ?? false
            return SubscriptionRow(
                id: x.id,
                name: x.name,
                hwid: x.hwid,
                isCurrentSource: isCur,
                host: x.host,
                info: info.joined(separator: " · "),
                daysLeft: left,
                daysLeftText: leftText,
                daysLeftIsCritical: (left ?? 99) <= 3,
                expiryText: (x.expire ?? 0) > 0 ? "до " + Fmt.dayMonth(x.expire ?? 0) : nil,
                usageText: usage,
                percent: pct,
                barTone: Summary.meterTone(percent: pct ?? 0),
                updateAction: x.id.isEmpty ? .subupdateAll : .subupdate(sid: x.id)
            )
        }
    }

    /// «2 подписки»; "" for none.
    public static func subscriptionsHeader(_ count: Int) -> String {
        return count > 0 ? Fmt.count(count, "подписка", "подписки", "подписок") : ""
    }

    // MARK: Speed (§5.1.8)

    public static func speedCard(via: SpeedVia, result: SpeedResult?, now: TimeInterval) -> SpeedCardInfo {
        let title = via == .vpn ? "С роутера, через VPN" : "С роутера, без VPN"
        guard let r = result else {
            return SpeedCardInfo(via: via, title: title, isEmpty: true, emptyText: "Ещё не запускали.", downText: "—", upText: "—", latencyText: "—", meta: "")
        }
        var meta = ""
        if !r.ip.isEmpty {
            meta += "Выход: " + Fmt.flag(r.country) + r.ip + ", "
        }
        meta += "проверено " + Fmt.ago(r.ts, now: now)
        if !r.server.isEmpty {
            meta += " · \(r.server), \(r.streams > 0 ? r.streams : 1) потока"
        }
        if r.up == 0 && r.upLimited {
            meta += " · Cloudflare ограничил частые замеры отдачи, повтори через пару минут"
        }
        return SpeedCardInfo(
            via: via,
            title: title,
            isEmpty: false,
            emptyText: "Ещё не запускали.",
            downText: Fmt.speed(r.down),
            upText: r.up > 0 ? Fmt.speed(r.up) : (r.upLimited ? "позже" : "—"),
            latencyText: r.latency > 0 ? Fmt.ms(r.latency) : "—",
            meta: meta
        )
    }

    /// `renderSpeedHist`: x from the oldest row over `max(now − oldest, 86 400)`; y `0…max × 1.15`.
    /// - Parameter upload: chart the upload instead (proposed toggle «Отдача»).
    public static func speedHistory(_ rows: [SpeedHistoryEntry], now: TimeInterval, upload: Bool = false) -> SpeedHistoryChart {
        let valid = rows.filter { $0.via == "vpn" || $0.via == "direct" }
        guard let from = valid.map({ $0.ts }).min() else {
            return SpeedHistoryChart(from: 0, to: 0, yMax: 1, series: [], isEmpty: true, caption: VPNTexts.speedHistoryEmpty)
        }
        let to = Int(now.rounded(.down))
        let span = max(to - from, 86400)
        let values = valid.map { upload ? $0.up : $0.down }
        let maxV = values.max() ?? 0
        let yMax = maxV > 0 ? Double(maxV) * 1.15 : 1
        var series: [SpeedSeries] = []
        for via in SpeedVia.allCases {
            let label = via == .vpn ? "через VPN" : "напрямую"
            let pts = valid.filter { $0.via == via.rawValue }.sorted { $0.ts < $1.ts }.map { r -> SpeedPoint in
                let v = upload ? r.up : r.down
                return SpeedPoint(ts: r.ts, value: v, tooltip: "\(label): \(Fmt.speed(v)), \(Fmt.when(r.ts, now: now))")
            }
            if !pts.isEmpty {
                series.append(SpeedSeries(via: via, label: label, points: pts))
            }
        }
        let caption = Fmt.when(from, now: now) + " · до " + "\(Fmt.jsRound(Double(maxV) / 1e6))" + Fmt.nbsp + "Мбит/с"
        return SpeedHistoryChart(from: from, to: from + span, yMax: yMax, series: series, isEmpty: false, caption: caption)
    }

    // MARK: Own servers (§5.1.9)

    public static func ownServers(_ v: VdsResponse?, now: TimeInterval) -> OwnServersInfo {
        guard let vds = v, let ts = vds.ts else {
            return OwnServersInfo(rows: [], footer: "Данных о серверах пока нет — они собираются раз в 5 минут.")
        }
        var rows: [OwnServerRow] = []
        for (i, srv) in vds.servers.enumerated() {
            guard let st = srv.stat else {
                rows.append(OwnServerRow(
                    id: "\(i)", name: srv.name, caption: srv.local ? "Здесь же панель" : nil,
                    isReachable: false, tone: .err, statusLine: "не отвечает по SSH", loadLine: nil, uptimeLine: nil
                ))
                continue
            }
            let active = st.xray == "active"
            let xray = active ? "VPN (Xray) работает" : "VPN (Xray): " + (st.xray.isEmpty ? "не запущен" : st.xray)
            rows.append(OwnServerRow(
                id: "\(i)",
                name: srv.name,
                caption: srv.local ? "Здесь же панель" : nil,
                isReachable: true,
                tone: active ? .ok : .err,
                statusLine: xray + " · соединений \(st.conns)",
                loadLine: "Нагрузка \(Fmt.loadText(st.load)) на \(st.cores)" + Fmt.nbsp + "ядр. · память " + Fmt.vdsMem(total: st.memTotal, avail: st.memAvail) + " · диск \(st.disk)",
                uptimeLine: "Без перезагрузки \(Fmt.uptime(st.up)) · трафик с запуска ↓\(Fmt.bytes(st.rx)) ↑\(Fmt.bytes(st.tx))"
            ))
        }
        let age = Int(now.rounded(.down)) - ts
        let footer = age < 90 ? "Данные свежие." : "Данные \(max(0, age) / 60)" + Fmt.nbsp + "мин назад."
        return OwnServersInfo(rows: rows, footer: footer)
    }

    // MARK: Internals

    static func cell(service: String, value: Int?, isBest: Bool, blocked: Bool) -> ServiceCell {
        guard let v = value else {
            return ServiceCell(service: service, value: nil, text: "·", tone: .neutral, isBest: false, isBlocked: false, hint: "ещё не мерили")
        }
        if v > 0 {
            return ServiceCell(service: service, value: v, text: "\(v)", tone: Fmt.msTone(v), isBest: isBest, isBlocked: false, hint: nil)
        }
        if blocked {
            return ServiceCell(service: service, value: v, text: "блок", tone: .neutral, isBest: false, isBlocked: true, hint: "Без VPN этот сайт в России не открывается")
        }
        return ServiceCell(service: service, value: v, text: "—", tone: .err, isBest: false, isBlocked: false, hint: nil)
    }

    static func servicesLine(_ cells: [ServiceCell]) -> String {
        return cells.map { $0.service + " " + $0.text }.joined(separator: " · ")
    }

    static func detailRow(_ x: ServiceRef, _ v: Int?) -> ServiceDetailRow {
        let icon = Summary.serviceIcon(name: x.name, host: x.host, kind: x.kind)
        guard let value = v else {
            return ServiceDetailRow(name: x.name, icon: icon, valueText: "ещё не мерили", tone: .neutral)
        }
        if value > 0 {
            return ServiceDetailRow(name: x.name, icon: icon, valueText: Fmt.ms(value), tone: Fmt.msTone(value))
        }
        return ServiceDetailRow(name: x.name, icon: icon, valueText: "нет ответа", tone: .err)
    }

    /// app.js:245-249.
    static func comparator(_ s: RouterStatus, _ sort: ServerSort) -> (PingNode, PingNode) -> Bool {
        let dir = sort.ascending ? 1 : -1
        switch sort.key {
        case .name:
            return { a, b in
                let x = Fmt.sortKeyName(a.name)
                let y = Fmt.sortKeyName(b.name)
                let r = x.compare(y, options: [.caseInsensitive, .numeric], range: nil, locale: Locale(identifier: "ru_RU"))
                if r == .orderedSame {
                    return false
                }
                return (r == .orderedAscending) == (dir > 0)
            }
        case .ping, .service:
            let key: (PingNode) -> Int? = { n in
                if case .service(let name) = sort.key {
                    return svcVal(svcOf(s, n.id), name)
                }
                return n.ms
            }
            return { a, b in
                let x = key(a)
                let y = key(b)
                let badX = !((x ?? 0) > 0)
                let badY = !((y ?? 0) > 0)
                if badX != badY {
                    return !badX
                }
                if badX {
                    return a.ms < b.ms
                }
                let d = ((x ?? 0) - (y ?? 0)) * dir
                if d != 0 {
                    return d < 0
                }
                return a.ms < b.ms
            }
        }
    }

    /// Stable sort (JS `Array.prototype.sort` is stable).
    static func stableSorted<T>(_ items: [T], _ less: (T, T) -> Bool) -> [T] {
        return items.enumerated().sorted { a, b in
            if less(a.element, b.element) {
                return true
            }
            if less(b.element, a.element) {
                return false
            }
            return a.offset < b.offset
        }.map { $0.element }
    }
}

extension OfflineBanner {
    /// (proposed, contract-stage4 §4.3) One-line banner for the tabs other than «Сводка»:
    /// «Роутер не на связи с 14:04 · уже 12 мин»; without data — «Роутер не на связи».
    public static func compactLine(data: DataResponse?, now: TimeInterval) -> String {
        guard let d = data, let since = d.offlineSince ?? d.lastOK else {
            return heading
        }
        let m = max(1, Fmt.jsRound((now - Double(since)) / 60))
        return heading + " с \(Fmt.whenShort(since, now: now)) · уже \(Fmt.minutes(m))"
    }
}
