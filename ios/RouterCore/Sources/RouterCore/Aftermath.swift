import Foundation

// What happens after an action (contract §7.2, contract-stage4 §3.2, §3.7, §6): quiet windows, banners, toasts,
// disabled controls, scheduled re-reads and fast polling, local state changes, and error handling per action.

/// A read the app polls or re-reads. Default intervals per contract-stage4 §4.2.
public enum ReadTarget: String, CaseIterable, Equatable, Sendable {
    case status
    case net
    case data
    case led
    case me
    case zapret
    case tgws
    case mydirect
    case vds
    /// `GET /devices` (who has access).
    case devices

    /// Timer interval while the screen that needs it is visible; `nil` = no timer (on appear / after actions only).
    public var defaultInterval: TimeInterval? {
        switch self {
        case .status, .zapret:
            return 30
        case .net:
            return 3
        case .data, .tgws:
            return 60
        case .led, .vds:
            return 300
        case .me, .mydirect, .devices:
            return nil
        }
    }

    /// A 502/504 on this read switches offline mode on (only `/status`).
    public var entersOfflineMode: Bool {
        return self == .status
    }

    /// Reaches the router (paused in offline mode, except `status` which keeps polling).
    public var needsRouter: Bool {
        switch self {
        case .status, .net, .led, .zapret, .tgws, .mydirect:
            return true
        case .data, .me, .vds, .devices:
            return false
        }
    }
}

/// «Read `target` again `after` seconds after the 200».
public struct ScheduledRead: Equatable, Sendable {
    public var target: ReadTarget
    public var after: TimeInterval

    public init(_ target: ReadTarget, after: TimeInterval) {
        self.target = target
        self.after = after
    }
}

/// Poll `/zapret` every `every` seconds while the condition holds, at most `maxDuration` per trigger.
public struct FastPoll: Equatable, Sendable {
    public enum Condition: String, Equatable, Sendable {
        /// `zapret.busy` (after `zapretset`).
        case zapretBusy
        /// `zapret.checking` (after `zapretcheck`).
        case zapretChecking
    }

    public var target: ReadTarget
    public var every: TimeInterval
    public var maxDuration: TimeInterval
    public var condition: Condition

    public init(target: ReadTarget = .zapret, every: TimeInterval = 3, maxDuration: TimeInterval = 120, condition: Condition) {
        self.target = target
        self.every = every
        self.maxDuration = maxDuration
        self.condition = condition
    }

    /// Keep polling? `false` when the condition is over or `elapsed >= maxDuration` (then back to 30 s).
    public func shouldContinue(_ state: ZapretState?, elapsed: TimeInterval) -> Bool {
        guard elapsed < maxDuration, let z = state else {
            return false
        }
        switch condition {
        case .zapretBusy:
            return z.busy
        case .zapretChecking:
            return z.checking
        }
    }
}

/// A check the app runs on the scheduled re-reads (the router may silently drop these actions).
public enum Verification: Equatable, Sendable {
    /// `zapretstrat`: see `Zapret.verifyStrategy`.
    case zapretStrategy(Int)
    /// `tgwsset`: see `Tgws.verifySwitch`.
    case tgws(on: Bool)
}

/// What to do after a 200 (contract §7.2, contract-stage4 §3.7).
public struct ActionAftermath: Equatable, Sendable {
    /// During it: `/status` errors are suppressed (no offline mode), `/net` is paused, the banner shows.
    public var quietWindow: TimeInterval
    /// Re-read `/status` after this many seconds (`nil` = no extra read). Same as the first `.status` in `rereads`.
    public var rereadStatusAfter: TimeInterval?
    /// «Сводка» buttons disabled for `disabledFor` seconds.
    public var disabledButtons: [SummaryButton]
    public var disabledFor: TimeInterval
    public var banner: String?
    /// Success toast; `nil` = none (or shown later, after a verification).
    public var toast: String?
    /// Every re-read to schedule (all screens).
    public var rereads: [ScheduledRead]
    /// Fast polling to start (zapret busy/checking).
    public var fastPoll: FastPoll?
    /// Action names (`RouterAction.name`) whose controls are disabled for `lockedFor` seconds everywhere in the app.
    /// PW actions lock every PW action for `max(quiet, 15)` s (the server pause).
    public var lockedActions: Set<String>
    public var lockedFor: TimeInterval
    /// Run on the scheduled re-reads.
    public var verification: Verification?
    /// `revoke-all`: this phone's key is revoked too → LOGOUT at once and show `toast` as the login banner.
    public var logsOut: Bool

    public init(
        quietWindow: TimeInterval,
        rereadStatusAfter: TimeInterval?,
        disabledButtons: [SummaryButton],
        disabledFor: TimeInterval,
        banner: String?,
        toast: String?,
        rereads: [ScheduledRead] = [],
        fastPoll: FastPoll? = nil,
        lockedActions: Set<String> = [],
        lockedFor: TimeInterval = 0,
        verification: Verification? = nil,
        logsOut: Bool = false
    ) {
        self.quietWindow = quietWindow
        self.rereadStatusAfter = rereadStatusAfter
        self.disabledButtons = disabledButtons
        self.disabledFor = disabledFor
        self.banner = banner
        self.toast = toast
        self.rereads = rereads
        self.fastPoll = fastPoll
        self.lockedActions = lockedActions
        self.lockedFor = lockedFor
        self.verification = verification
        self.logsOut = logsOut
    }

    /// The server pause after a PW action, seconds.
    public static let passWallPause: TimeInterval = 15

    /// Names of every PW action (`RouterAction.isPassWall`).
    public static let passWallActionNames: Set<String> = ["switch", "restart", "update", "subupdate", "direct", "diradd", "dirdel", "svcdirect", "zapretset"]

    /// `true` while this aftermath (started `elapsed` seconds ago) keeps `action` disabled.
    public func locks(_ action: RouterAction, elapsed: TimeInterval) -> Bool {
        return elapsed < lockedFor && lockedActions.contains(action.name)
    }

    /// - Parameters:
    ///   - action: the action that got a 200 (for a job: the finished job).
    ///   - name: display name used in texts: the node name (switch), the subscription name (subupdate),
    ///     the device name (block, unblock, direct, schedule, revokeApp). Falls back to the id / MAC.
    ///   - result: the 200 body (`same` of diradd/dirdel) or the speedtest job result.
    public static func after(_ action: RouterAction, name: String? = nil, result: JSONValue? = nil) -> ActionAftermath {
        let ok = result.map { ActionOK(json: $0) }
        let same = ok?.same ?? false
        let all4: [SummaryButton] = [.check, .restartVPN, .updateSubs, .reboot]
        func pw(quiet: TimeInterval, banner: String?, toast: String?, rereads: [ScheduledRead]) -> ActionAftermath {
            let lock = max(quiet, passWallPause)
            return ActionAftermath(
                quietWindow: quiet,
                rereadStatusAfter: rereads.first(where: { $0.target == .status })?.after,
                disabledButtons: quiet > 0 ? all4 : [.restartVPN, .updateSubs],
                disabledFor: lock,
                banner: quiet > 0 ? banner : nil,
                toast: toast,
                rereads: rereads,
                lockedActions: passWallActionNames,
                lockedFor: lock
            )
        }
        func plain(toast: String?, rereads: [ScheduledRead], locked: Set<String> = [], lockedFor: TimeInterval = 0, verification: Verification? = nil) -> ActionAftermath {
            return ActionAftermath(
                quietWindow: 0,
                rereadStatusAfter: rereads.first(where: { $0.target == .status })?.after,
                disabledButtons: [],
                disabledFor: 0,
                banner: nil,
                toast: toast,
                rereads: rereads,
                lockedActions: locked,
                lockedFor: lockedFor,
                verification: verification
            )
        }

        switch action {
        case .restart:
            var a = pw(quiet: 15, banner: "VPN перезапускается…", toast: "VPN перезапускается.", rereads: [ScheduledRead(.status, after: 15)])
            a.disabledFor = 15
            return a
        case .update:
            return pw(
                quiet: 0, banner: nil,
                toast: subscriptionsUpdatingToast,
                rereads: [ScheduledRead(.status, after: 60)]
            )
        case .reboot:
            return ActionAftermath(
                quietWindow: 150, rereadStatusAfter: 150,
                disabledButtons: [.check, .restartVPN, .updateSubs, .reboot, .led], disabledFor: 150,
                banner: "Роутер перезагружается…",
                toast: "Роутер перезагружается. Приложение само обновится, когда он вернётся.",
                rereads: [ScheduledRead(.status, after: 150)],
                lockedActions: allRouterActionNames, lockedFor: 150
            )
        case .ping:
            return plain(toast: ActionTexts.pingDone, rereads: [])
        case .ledset(let on):
            return plain(toast: on ? "Подсветка роутера включена." : "Подсветка роутера выключена.", rereads: [])
        case .pingone:
            return plain(toast: nil, rereads: [])
        case .switchServer(let id):
            if id == "direct" {
                return pw(
                    quiet: 15, banner: "VPN выключается — всё пойдёт напрямую…",
                    toast: "Подключаю «\(Summary.directName)». Статус обновится через 10 секунд.",
                    rereads: [ScheduledRead(.status, after: 10)]
                )
            }
            let nm = nonEmpty(name) ?? id
            return pw(
                quiet: 15, banner: "VPN переключается на «\(nm)»…",
                toast: "Подключаю «\(nm)». Статус обновится через 10 секунд.",
                rereads: [ScheduledRead(.status, after: 10)]
            )
        case .subupdate(let sid):
            let nm = nonEmpty(name) ?? sid
            return pw(
                quiet: 0, banner: nil,
                toast: "«\(nm)»: список серверов обновляется, около минуты.",
                rereads: [ScheduledRead(.status, after: 45), ScheduledRead(.status, after: 90)]
            )
        case .subupdateAll:
            return pw(
                quiet: 0, banner: nil,
                toast: subscriptionsUpdatingToast,
                rereads: [ScheduledRead(.status, after: 45), ScheduledRead(.status, after: 90)]
            )
        case .speedtest(let via):
            var toast: String? = nil
            if let r = result, r.isObject {
                let s = SpeedResult(json: r)
                let head = via == .vpn ? "Тест через VPN: " : "Тест напрямую: "
                if s.up > 0 {
                    toast = head + "\(Fmt.speed(s.down)) загрузка, \(Fmt.speed(s.up)) отдача."
                } else {
                    toast = head + "\(Fmt.speed(s.down)) загрузка."
                }
            }
            return plain(toast: toast, rereads: [ScheduledRead(.data, after: 5)])
        case .block(let mac):
            let nm = nonEmpty(name) ?? mac.lowercased()
            return plain(toast: "Интернет для «\(nm)» выключен.", rereads: [ScheduledRead(.status, after: 3)])
        case .unblock(let mac):
            let nm = nonEmpty(name) ?? mac.lowercased()
            return plain(toast: "Интернет для «\(nm)» снова включён.", rereads: [ScheduledRead(.status, after: 3)])
        case .direct(let mac, let on):
            let nm = nonEmpty(name) ?? mac.lowercased()
            return pw(
                quiet: 12, banner: "VPN перезапускается…",
                toast: on ? "«\(nm)» теперь мимо VPN." : "«\(nm)» снова через VPN.",
                rereads: [ScheduledRead(.status, after: 12)]
            )
        case .schedule(let mac, let off, let on):
            let nm = nonEmpty(name) ?? mac.lowercased()
            let w = ScheduleWindow(off: off, on: on)
            return plain(toast: "«\(nm)»: без интернета с \(w.offText) до \(w.onText).", rereads: [ScheduledRead(.status, after: 3)])
        case .scheduleClear(let mac):
            let nm = nonEmpty(name) ?? mac.lowercased()
            return plain(toast: "Расписание «\(nm)» убрано.", rereads: [ScheduledRead(.status, after: 3)])
        case .diradd(let d):
            return pw(
                quiet: same ? 0 : 12, banner: "VPN перезапускается…",
                toast: same ? "\(d) уже был в списке." : "\(d) теперь напрямую.",
                rereads: [ScheduledRead(.mydirect, after: 0)]
            )
        case .dirdel(let d):
            return pw(
                quiet: same ? 0 : 12, banner: "VPN перезапускается…",
                toast: same ? "\(d) уже не было в списке." : "\(d) снова через VPN.",
                rereads: [ScheduledRead(.mydirect, after: 0)]
            )
        case .svcdirect(let svc, let on):
            return pw(
                quiet: 12, banner: "VPN перезапускается…",
                toast: on ? "\(svc) теперь напрямую." : "\(svc) снова через VPN.",
                rereads: [ScheduledRead(.mydirect, after: 0), ScheduledRead(.status, after: 12)]
            )
        case .zapretset(let on):
            var a = pw(
                quiet: 15, banner: "Применяю… VPN перезапускается",
                toast: on ? "Включаю zapret — около 10 секунд." : "Выключаю zapret — около 10 секунд.",
                rereads: [ScheduledRead(.zapret, after: 1.5)]
            )
            a.fastPoll = FastPoll(condition: .zapretBusy)
            return a
        case .zapretstrat(let n):
            return plain(
                toast: nil,
                rereads: Zapret.strategyCheckDelays.map { ScheduledRead(.zapret, after: $0) },
                locked: ["zapretstrat", "zapretset"], lockedFor: Zapret.strategyCheckDelays.last ?? 7,
                verification: .zapretStrategy(n)
            )
        case .zapretcheck:
            var a = plain(toast: nil, rereads: [ScheduledRead(.zapret, after: 3)])
            a.fastPoll = FastPoll(condition: .zapretChecking)
            return a
        case .tgwsset(let on):
            return plain(
                toast: on ? "Прокси Telegram включается…" : "Прокси Telegram выключен.",
                rereads: Tgws.verifyDelays.map { ScheduledRead(.tgws, after: $0) },
                locked: ["tgwsset"], lockedFor: Tgws.verifyDelays.last ?? 8,
                verification: .tgws(on: on)
            )
        case .rename:
            return plain(toast: "Имя сохранено.", rereads: [])
        case .revokeApp:
            let nm = nonEmpty(name) ?? "телефон"
            return plain(toast: "Доступ «\(nm)» отозван: приложение на телефоне вышло.", rereads: [ScheduledRead(.devices, after: 0)])
        case .revokeWeb:
            return plain(toast: "Сессия веб-панели закрыта.", rereads: [ScheduledRead(.devices, after: 0)])
        case .revokeAll:
            var a = plain(toast: AccessTexts.revokedAllBanner, rereads: [])
            a.logsOut = true
            return a
        }
    }

    static let subscriptionsUpdatingToast = "Подписки обновляются — список серверов обновится через 1–2 минуты, потом VPN перезапустится на несколько секунд."

    static let allRouterActionNames: Set<String> = [
        "ping", "restart", "update", "reboot", "ledset", "pingone", "switch", "subupdate", "speedtest", "block", "unblock",
        "direct", "schedule", "diradd", "dirdel", "svcdirect", "zapretset", "zapretstrat", "zapretcheck", "tgwsset"
    ]

    static func nonEmpty(_ s: String?) -> String? {
        guard let s = s, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return s
    }
}

// MARK: - Errors per action (contract-stage4 §6)

public enum ActionErrorPolicy {
    /// (proposed, as the web app.js:111) A speed test already runs on the router (job `http: 409`).
    public static let speedtestRunningText = "Тест скорости уже идёт — дождись результата."
    /// (proposed, inventory §9.1) `zapretset` → router 409.
    public static let zapretBusyText = "zapret сейчас занят другим действием — повтори через несколько секунд."
    /// (proposed) `revoke` → 404.
    public static let revokeGoneText = "Этого входа уже нет — список обновлён."
    /// (proposed, inventory §9.1) Added to `no rule` on Bypass.
    public static let noRuleHint = "Проверь правило MyDirect в LuCI."

    /// `zapretcheck` answered `409 busy` by the router: a check already runs → treat as started (poll, no error).
    public static func treatsAsStarted(_ action: RouterAction, error: APIError) -> Bool {
        if case .zapretcheck = action {
            return isRouterBusy(error)
        }
        return false
    }

    /// Text to show for a failed action (or a failed job), `nil` = show nothing (cancelled, or treated as started).
    public static func message(for action: RouterAction, error: APIError) -> String? {
        if error.isCancelled || treatsAsStarted(action, error: error) {
            return nil
        }
        switch action {
        case .speedtest:
            if isRouterBusy(error) {
                return speedtestRunningText
            }
        case .zapretset:
            if isRouterBusy(error) {
                return zapretBusyText
            }
        case .revokeApp, .revokeWeb:
            if error.kind == .http && error.status == 404 {
                return revokeGoneText
            }
        case .diradd, .dirdel, .svcdirect:
            if error.code == "no rule" {
                return error.userMessage + " " + noRuleHint
            }
        default:
            break
        }
        return error.actionMessage
    }

    /// Reads to repeat after the error (stale lists, changed state).
    public static func rereads(for action: RouterAction, error: APIError) -> [ReadTarget] {
        switch error.code {
        case "bad node", "no target", "bad sub":
            return [.status]
        case "no rule":
            return [.mydirect]
        case "not installed":
            if case .tgwsset = action {
                return [.tgws]
            }
            return [.zapret]
        case "not_found":
            switch action {
            case .revokeApp, .revokeWeb:
                return [.devices]
            default:
                return []
            }
        case "bad_param":
            if case .dirdel = action, error.kind == .http {
                return [.mydirect]
            }
            return []
        default:
            return []
        }
    }

    /// 409 `busy` that came from the router CGI (`source: "router"`; a job error carries it the same way).
    public static func isRouterBusy(_ error: APIError) -> Bool {
        return error.code == "busy" && error.status == 409 && error.source == "router"
    }
}

// MARK: - Local state changes right after a 200

extension RouterStatus {
    /// The status with the action's effect applied at once (contract-stage4 §3.7 «Local state change»):
    /// switch → `current`; pingone → node `ms` (from `result`); block/unblock → `blocked`; direct → `direct`;
    /// schedule → `sched`; svcdirect → `svcDirect`; speedtest → `speed[via]` (from the job result).
    public func applyingSuccess(of action: RouterAction, result: JSONValue? = nil) -> RouterStatus {
        var s = self
        func updateDevice(_ mac: String, _ change: (inout RouterDevice) -> Void) {
            let m = mac.lowercased()
            for i in s.devices.indices where s.devices[i].mac == m {
                change(&s.devices[i])
            }
        }
        switch action {
        case .switchServer(let id):
            s.current = id == "direct" ? "_direct" : id
        case .pingone(let id):
            if let r = result, r.isObject, s.ping != nil {
                let p = PingOneResult(json: r)
                let target = p.id.isEmpty ? id : p.id
                for i in s.ping!.nodes.indices where s.ping!.nodes[i].id == target {
                    s.ping!.nodes[i].ms = p.ms
                }
            }
        case .block(let mac):
            let blocked = result.flatMap { ActionOK(json: $0).blocked } ?? true
            updateDevice(mac) { $0.blocked = blocked }
        case .unblock(let mac):
            let blocked = result.flatMap { ActionOK(json: $0).blocked } ?? false
            updateDevice(mac) { $0.blocked = blocked }
        case .direct(let mac, let on):
            updateDevice(mac) { $0.direct = on }
        case .schedule(let mac, let off, let on):
            updateDevice(mac) { $0.sched = off + "-" + on }
        case .scheduleClear(let mac):
            updateDevice(mac) { $0.sched = nil }
        case .svcdirect(let name, let on):
            s.svcDirect.removeAll { $0 == name }
            if on {
                s.svcDirect.append(name)
            }
        case .speedtest(let via):
            if let r = result, r.isObject {
                let res = SpeedResult(json: r)
                switch via {
                case .vpn:
                    s.speed.vpn = res
                case .direct:
                    s.speed.direct = res
                }
            }
        default:
            break
        }
        return s
    }
}

extension MyDirectList {
    /// diradd → add to `added` and `domains` (if absent); dirdel → remove from both. Re-read `/mydirect` anyway.
    public func applyingSuccess(of action: RouterAction) -> MyDirectList {
        var m = self
        switch action {
        case .diradd(let d):
            if !m.added.contains(d) {
                m.added.append(d)
            }
            if !m.domains.contains(d) {
                m.domains.append(d)
            }
        case .dirdel(let d):
            m.added.removeAll { $0 == d }
            m.domains.removeAll { $0 == d }
        default:
            break
        }
        return m
    }
}

extension ZapretState {
    /// zapretset → `busy = true`; zapretcheck → `checking = true`.
    public func applyingSuccess(of action: RouterAction) -> ZapretState {
        var z = self
        switch action {
        case .zapretset:
            z.busy = true
        case .zapretcheck:
            z.checking = true
        default:
            break
        }
        return z
    }
}
