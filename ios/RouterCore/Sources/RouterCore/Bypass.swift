import Foundation

// «Обход» tab (contract-stage4 §5.4): zapret, Telegram через Cloudflare, сервисы напрямую, MyDirect.
// Ported from app.js renderZap / renderTgws / renderMd and the svcdirect chips.

/// A label/value row with a tone (zapret «Подробнее»).
public struct StatusFact: Equatable, Sendable, Identifiable {
    public var label: String
    public var value: String
    public var tone: Tone

    public init(label: String, value: String, tone: Tone = .neutral) {
        self.label = label
        self.value = value
        self.tone = tone
    }

    public var id: String {
        return label
    }
}

// MARK: - zapret

public enum ZapretPhase: String, Equatable, Sendable {
    /// No successful read yet: «Загружаю…», controls hidden.
    case loading
    /// The script is missing on the router: controls hidden.
    case absent
    /// `!installed`: error box, controls disabled.
    case notInstalled
    case busy
    case working
    case partial
    case off
}

/// One result tile of «Проверить YouTube и Discord».
public struct ZapretResultTile: Equatable, Sendable, Identifiable {
    public var name: String
    /// «412 мс» or «нет».
    public var valueText: String
    public var tone: Tone
    /// «обработано zapret: 6 пак.», «без обработки zapret», «не открывается».
    public var footnote: String

    public var id: String {
        return name
    }
}

public struct ZapretStrategy: Equatable, Sendable, Identifiable {
    public var n: Int
    /// «1 · multisplit».
    public var title: String

    public var id: Int {
        return n
    }
}

/// zapret card presentation (contract-stage4 §5.4.1–5.4.3).
public struct ZapretInfo: Equatable, Sendable {
    public var phase: ZapretPhase
    /// Dot colour: ok (working), warn (busy / partial), neutral (off), err (not installed).
    public var tone: Tone
    /// «YouTube и Discord — напрямую, с IP провайдера» (plain text).
    public var summary: String
    /// The part of `summary` to show bold («напрямую»), if any.
    public var summaryBold: String?
    /// «18234 TCP · 5120 QUIC» (working only).
    public var counters: String?
    /// One error box (first match), or `nil`.
    public var errorText: String?
    /// «Подробнее» rows.
    public var details: [StatusFact]
    /// The toggle shows the **server** value.
    public var isOn: Bool
    public var showsControls: Bool
    public var toggleEnabled: Bool
    public var strategy: Int
    public var strategyEnabled: Bool
    public var checkEnabled: Bool
    /// «Проверить YouTube и Discord» / «Проверяю…».
    public var checkTitle: String
    public var results: [ZapretResultTile]
    /// «Проверено сегодня 14:06 · Discord видит IP провайдера», or the Xray failure text.
    public var checkCaption: String?
    /// Poll `/zapret` every 3 s (busy or checking).
    public var needsFastPoll: Bool

    /// Toggle action (428 high).
    public var toggleAction: RouterAction {
        return .zapretset(on: !isOn)
    }
}

/// Result of verifying `zapretstrat` on a re-read.
public enum StrategyCheck: Equatable, Sendable {
    /// `strategy == n && !busy` → toast «Стратегия N выбрана.».
    case applied(toast: String)
    /// Not yet; wait for the next scheduled read.
    case pending
    /// After the last read `strategy != n` → error toast (the control shows the real value).
    case failed(text: String)
}

public enum ZapretTexts {
    public static let title = "YouTube и Discord без VPN"
    public static let loading = "Загружаю…"
    /// (proposed)
    public static let absent = "zapret на роутере не установлен."
    public static let notInstalled = "zapret не установлен на роутере (нет nfqws, списков или модуля ядра)."
    /// (proposed)
    public static let toggleCaption = "Включение и выключение перезапускают VPN на несколько секунд."
    public static let checkButton = "Проверить YouTube и Discord"
    public static let checking = "Проверяю…"
    /// (proposed)
    public static let tileLabel = "время ответа"
    /// (proposed)
    public static let xrayFailed = "Проверка не удалась: VPN (Xray) не был запущен."
    /// (proposed)
    public static let strategyFailed = "Стратегия не применилась — роутер был занят. Попробуй ещё раз."
    public static let detailsTitle = "Подробнее"
    /// (proposed) Cold start offline, for the whole tab.
    public static let noStatus = "Роутер не на связи — настройки обхода появятся, когда он вернётся."
}

public enum Zapret {
    /// Strategies (index.html:148-150).
    public static let strategies: [ZapretStrategy] = [
        ZapretStrategy(n: 1, title: "1 · multisplit"),
        ZapretStrategy(n: 2, title: "2 · fake + fakedsplit"),
        ZapretStrategy(n: 3, title: "3 · hostfakesplit")
    ]

    /// Re-reads after `zapretstrat`: +2, +4, +7 s (stop early on success).
    public static let strategyCheckDelays: [TimeInterval] = [2, 4, 7]

    /// `/zapret` polling: 3 s while busy or checking (≤ 2 min per trigger), else 30 s.
    public static func pollInterval(_ z: ZapretState?) -> TimeInterval {
        guard let s = z else {
            return 30
        }
        return (s.busy || s.checking) ? 3 : 30
    }

    public static func info(_ state: ZapretState?, now: TimeInterval) -> ZapretInfo {
        guard let z = state else {
            return ZapretInfo(
                phase: .loading, tone: .neutral, summary: ZapretTexts.loading, summaryBold: nil, counters: nil,
                errorText: nil, details: [], isOn: false, showsControls: false, toggleEnabled: false, strategy: 3,
                strategyEnabled: false, checkEnabled: false, checkTitle: ZapretTexts.checkButton, results: [],
                checkCaption: nil, needsFastPoll: false
            )
        }
        if z.absent {
            return ZapretInfo(
                phase: .absent, tone: .neutral, summary: ZapretTexts.absent, summaryBold: nil, counters: nil,
                errorText: nil, details: [], isOn: false, showsControls: false, toggleEnabled: false, strategy: z.strategy,
                strategyEnabled: false, checkEnabled: false, checkTitle: ZapretTexts.checkButton, results: [],
                checkCaption: nil, needsFastPoll: false
            )
        }
        let on = z.enabled
        let work = z.isWorking
        var phase: ZapretPhase
        var tone: Tone
        var summary: String
        var bold: String? = nil
        var counters: String? = nil
        if !z.installed {
            phase = .notInstalled
            tone = .err
            summary = on ? "Включён, но работает не полностью" : "YouTube и Discord — через VPN, как всё остальное"
        } else if z.busy {
            phase = .busy
            tone = .warn
            summary = "Применяю… PassWall перезапускается"
        } else if on && work {
            phase = .working
            tone = .ok
            summary = "YouTube и Discord — напрямую, с IP провайдера"
            bold = "напрямую"
            if z.nft {
                counters = "\(z.pktsTCP)" + Fmt.nbsp + "TCP · \(z.pktsUDP)" + Fmt.nbsp + "QUIC"
            }
        } else if on {
            phase = .partial
            tone = .warn
            summary = "Включён, но работает не полностью"
        } else {
            phase = .off
            tone = .neutral
            summary = "YouTube и Discord — через VPN, как всё остальное"
        }

        var err: String? = nil
        if !z.installed {
            err = ZapretTexts.notInstalled
        } else if !z.error.isEmpty {
            err = z.error
        } else if !z.busy && on && !work {
            var parts: [String] = []
            if !z.engine {
                parts.append("служба не работает")
            }
            if !z.nft {
                parts.append("нет правил nftables")
            }
            if !z.routeLive {
                parts.append("маршрут PassWall не применён")
            }
            err = "Расхождение: режим включён, но " + parts.joined(separator: ", ") + ". Сторож попробует исправить в течение минуты."
        } else if !z.busy && !on && (z.engine || z.nft || z.routeCfg) {
            err = "Расхождение: режим выключен, но часть правил ещё активна. Сторож уберёт их в течение минуты."
        }

        var details: [StatusFact] = [
            StatusFact(label: "Выбрано", value: on ? "включить" : "выключить"),
            StatusFact(label: "Служба nfqws", value: z.engine ? "работает" : (on ? "не работает" : "остановлена"), tone: z.engine ? .ok : .err),
            StatusFact(label: "Правила nftables", value: z.nft ? "есть" : "нет", tone: z.nft ? .ok : .err),
            StatusFact(label: "Маршрут", value: z.routeLive ? "напрямую (IP провайдера)" : "через VPN", tone: z.routeLive ? .ok : .neutral)
        ]
        if z.nft {
            details.append(StatusFact(label: "Обработано пакетов", value: "\(z.pktsTCP)" + Fmt.nbsp + "TCP · \(z.pktsUDP)" + Fmt.nbsp + "QUIC"))
        }
        if !z.version.isEmpty {
            details.append(StatusFact(label: "Версия", value: z.version))
        }

        var results: [ZapretResultTile] = []
        var caption: String? = nil
        if let c = z.check {
            if c.error == "xray" {
                caption = ZapretTexts.xrayFailed
            } else if !c.list.isEmpty {
                results = c.list.map { x in
                    let note: String
                    if x.ok {
                        note = x.queued > 0 ? "обработано zapret: \(x.queued)" + Fmt.nbsp + "пак." : "без обработки zapret"
                    } else {
                        note = "не открывается"
                    }
                    return ZapretResultTile(name: x.name, valueText: x.ok ? Fmt.ms(x.ms) : "нет", tone: x.ok ? .ok : .err, footnote: note)
                }
                var cap = "Проверено " + Fmt.when(c.ts, now: now)
                if c.via == "isp" {
                    cap += " · Discord видит IP провайдера"
                } else if c.via == "vpn" {
                    cap += " · Discord видит IP VPN"
                }
                caption = cap
            }
        }

        return ZapretInfo(
            phase: phase,
            tone: tone,
            summary: summary,
            summaryBold: bold,
            counters: counters,
            errorText: err,
            details: details,
            isOn: on,
            showsControls: true,
            toggleEnabled: z.installed && !z.busy,
            strategy: z.strategy,
            strategyEnabled: z.installed && !z.busy,
            checkEnabled: z.installed && !z.checking,
            checkTitle: z.checking ? ZapretTexts.checking : ZapretTexts.checkButton,
            results: results,
            checkCaption: caption,
            needsFastPoll: z.busy || z.checking
        )
    }

    /// Verify a `zapretstrat {n}` on a re-read (contract-stage4 §5.4.2).
    public static func verifyStrategy(requested n: Int, state: ZapretState?, isLastCheck: Bool) -> StrategyCheck {
        if let z = state, z.strategy == n && !z.busy {
            return .applied(toast: "Стратегия \(n) выбрана.")
        }
        return isLastCheck ? .failed(text: ZapretTexts.strategyFailed) : .pending
    }
}

// MARK: - Telegram через Cloudflare

public enum TgwsPhase: String, Equatable, Sendable {
    case loading
    /// `absent` or `!installed`: text, no toggle.
    case notInstalled
    case off
    /// Running, listening and redirecting.
    case working
    /// Running and listening, the redirect is not on yet.
    case waitingRedirect
    /// Enabled but not running/listening yet.
    case starting
}

public struct TgwsInfo: Equatable, Sendable {
    public var phase: TgwsPhase
    public var tone: Tone
    public var summary: String
    public var summaryBold: String?
    /// «3412 подкл.» (working).
    public var counter: String?
    /// The toggle shows the server value.
    public var isOn: Bool
    public var showsToggle: Bool

    public var toggleAction: RouterAction {
        return .tgwsset(on: !isOn)
    }
}

public enum TgwsCheck: Equatable, Sendable {
    case applied
    case pending
    case failed(text: String)
}

public enum TgwsTexts {
    public static let title = "Telegram через Cloudflare"
    public static let tag = "экспериментально"
    /// (proposed)
    public static let notInstalled = "Telegram-прокси на роутере не установлен."
    /// (proposed)
    public static let notSwitched = "Роутер не переключил прокси Telegram — попробуй ещё раз."
}

public enum Tgws {
    /// One-off re-reads after `tgwsset`: +3 s and +8 s.
    public static let verifyDelays: [TimeInterval] = [3, 8]

    public static func info(_ state: TgwsState?) -> TgwsInfo {
        guard let t = state else {
            return TgwsInfo(phase: .loading, tone: .neutral, summary: ZapretTexts.loading, summaryBold: nil, counter: nil, isOn: false, showsToggle: false)
        }
        if t.absent || !t.installed {
            return TgwsInfo(phase: .notInstalled, tone: .neutral, summary: TgwsTexts.notInstalled, summaryBold: nil, counter: nil, isOn: false, showsToggle: false)
        }
        let ok = t.running && t.listening
        if !t.enabled {
            return TgwsInfo(phase: .off, tone: .neutral, summary: "Выключен — Telegram идёт как обычно (через VPN)", summaryBold: nil, counter: nil, isOn: false, showsToggle: true)
        }
        if ok && t.auto {
            return TgwsInfo(
                phase: .working, tone: .ok,
                summary: "Telegram на всех устройствах дома — через Cloudflare, мимо VPN, без настройки",
                summaryBold: "через Cloudflare, мимо VPN",
                counter: "\(t.redirected)" + Fmt.nbsp + "подкл.",
                isOn: true, showsToggle: true
            )
        }
        if ok {
            return TgwsInfo(phase: .waitingRedirect, tone: .warn, summary: "Прокси работает, перехват ещё не включён (сторож включит в течение минуты)", summaryBold: nil, counter: nil, isOn: true, showsToggle: true)
        }
        return TgwsInfo(phase: .starting, tone: .warn, summary: "Запускается… Пока прокси не работает, Telegram идёт через VPN", summaryBold: nil, counter: nil, isOn: true, showsToggle: true)
    }

    /// After `tgwsset {on}`: `enabled == on` → applied; else pending, or failed after the last (+8 s) read.
    public static func verifySwitch(requested on: Bool, state: TgwsState?, isLastCheck: Bool) -> TgwsCheck {
        if let t = state, t.enabled == on {
            return .applied
        }
        return isLastCheck ? .failed(text: TgwsTexts.notSwitched) : .pending
    }
}

// MARK: - Сервисы напрямую

public struct SvcDirectRow: Equatable, Sendable, Identifiable {
    public var name: String
    public var kind: String
    public var host: String
    public var icon: String
    /// `svc_direct` contains the name (server value; never flip before 200).
    public var isOn: Bool
    /// «Домен www.youtube.com добавится в MyDirect.» / the mc text.
    public var caption: String
    /// The name passes the server check; else the toggle is disabled with `editCaption`.
    public var isEditable: Bool
    public var editCaption: String?

    public var id: String {
        return name
    }

    /// Toggle action (428 high), `nil` when not editable.
    public var toggleAction: RouterAction? {
        return isEditable ? .svcdirect(name: name, on: !isOn) : nil
    }
}

public enum SvcDirect {
    public static let title = "Сервисы напрямую"
    /// (proposed)
    public static let empty = "Список сервисов пустой — его можно задать в веб-панели."

    public static func rows(_ s: RouterStatus) -> [SvcDirectRow] {
        return Summary.serviceList(s).map { x in
            let caption = x.kind == "mc"
                ? "IP сервера добавится в MyDirect — игра пойдёт без VPN, пинг станет как «Напрямую»."
                : "Домен \(x.host) добавится в MyDirect."
            let editable = Validation.isValidServiceName(x.name)
            return SvcDirectRow(
                name: x.name, kind: x.kind, host: x.host,
                icon: Summary.serviceIcon(name: x.name, host: x.host, kind: x.kind),
                isOn: s.svcDirect.contains(x.name),
                caption: caption,
                isEditable: editable,
                editCaption: editable ? nil : Validation.serviceNameHint
            )
        }
    }
}

// MARK: - MyDirect

public enum DomainCheck: Equatable, Sendable {
    /// Normalized and valid: send `diradd {"d": domain}`.
    case ok(String)
    /// «Нужен домен вида site.ru».
    case invalid(String)
    /// «Этот сайт уже в списке.» — no request.
    case alreadyListed(String)
}

public struct MyDirectRow: Equatable, Sendable, Identifiable {
    public var domain: String
    /// In `added` → tag «добавлен» and «Убрать».
    public var isAdded: Bool
    /// Only `added` items are removable (never prefixed entries).
    public var isRemovable: Bool

    public var id: String {
        return domain
    }

    public var removeAction: RouterAction? {
        return isRemovable ? .dirdel(domain: domain) : nil
    }
}

public struct MyDirectInfo: Equatable, Sendable {
    /// «5 записей».
    public var countText: String
    /// «Добавленные» rows.
    public var added: [MyDirectRow]
    /// «Пока ничего — добавь сайт ниже.» when `added` is empty.
    public var addedEmptyText: String?
    /// «Весь список (5)».
    public var allTitle: String
    /// First 60 matches.
    public var found: [MyDirectRow]
    /// «…и ещё N. Уточни поиск.».
    public var moreText: String?
    /// «Не найдено.».
    public var notFoundText: String?
}

public enum MyDirectTexts {
    public static let title = "Сайты без VPN"
    public static let addedTitle = "Добавленные"
    public static let addTitle = "Добавить сайт"
    public static let placeholder = "пример: gosuslugi.ru"
    public static let searchPlaceholder = "Найти домен…"
    public static let addedTag = "добавлен"
    public static let remove = "Убрать"
    public static let add = "Добавить"
    public static let invalid = Validation.domainHint
    /// (proposed)
    public static let alreadyListed = "Этот сайт уже в списке."
    public static let addedEmpty = "Пока ничего — добавь сайт ниже."
    public static let notFound = "Не найдено."
}

public enum MyDirect {
    /// Show at most this many rows of «Весь список».
    public static let pageSize = 60

    /// app.js:622: trim → lowercase → drop `^https?://` → drop `/.*$` → drop `^www\.`.
    public static func normalize(_ input: String) -> String {
        var d = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if d.hasPrefix("https://") {
            d = String(d.dropFirst(8))
        } else if d.hasPrefix("http://") {
            d = String(d.dropFirst(7))
        }
        if let slash = d.firstIndex(of: "/") {
            d = String(d[d.startIndex..<slash])
        }
        if d.hasPrefix("www.") {
            d = String(d.dropFirst(4))
        }
        return d
    }

    /// Normalize + the server regex (≤ 100 bytes) + «already listed» (in `domains`).
    public static func check(_ input: String, list: MyDirectList?) -> DomainCheck {
        let d = normalize(input)
        guard Validation.isValidDomain(d) else {
            return .invalid(MyDirectTexts.invalid)
        }
        if let l = list, l.domains.contains(d) {
            return .alreadyListed(MyDirectTexts.alreadyListed)
        }
        return .ok(d)
    }

    /// `geosite:…`, `domain:…`, `full:…`, `regexp:…` (`^[a-z]+:`).
    public static func isPrefixed(_ d: String) -> Bool {
        guard let colon = d.firstIndex(of: ":"), colon > d.startIndex else {
            return false
        }
        return d[d.startIndex..<colon].unicodeScalars.allSatisfy { $0.value >= 0x61 && $0.value <= 0x7A }
    }

    /// Only `added` items can be removed (the server re-checks).
    public static func isRemovable(_ d: String, list: MyDirectList) -> Bool {
        return !isPrefixed(d) && list.added.contains(d)
    }

    public static func info(_ list: MyDirectList, query: String = "") -> MyDirectInfo {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matches = q.isEmpty ? list.domains.filter { !isPrefixed($0) } : list.domains.filter { $0.lowercased().contains(q) }
        let rows = matches.prefix(pageSize).map { d in
            MyDirectRow(domain: d, isAdded: list.added.contains(d), isRemovable: isRemovable(d, list: list))
        }
        let added = list.added.map { MyDirectRow(domain: $0, isAdded: true, isRemovable: !isPrefixed($0)) }
        return MyDirectInfo(
            countText: Fmt.count(list.domains.count, "запись", "записи", "записей"),
            added: added,
            addedEmptyText: added.isEmpty ? MyDirectTexts.addedEmpty : nil,
            allTitle: "Весь список (\(list.domains.count))",
            found: Array(rows),
            moreText: matches.count > pageSize ? "…и ещё \(matches.count - pageSize). Уточни поиск." : nil,
            notFoundText: matches.isEmpty ? MyDirectTexts.notFound : nil
        )
    }
}
