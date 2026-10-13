import Foundation
import RouterCore

/// A read the app polls (contract §7.1, contract-stage4 §4.2). `/data` is one kind per range.
enum ReadKind: Hashable {
    case status
    case net
    case data(DataRange)
    case led
    case me
    case zapret
    case tgws
    case mydirect
    case vds
    /// `GET /devices` (who has access).
    case devices

    static let allCases: [ReadKind] = [
        .status, .net, .data(.day), .data(.week), .data(.month), .led, .me, .zapret, .tgws, .mydirect, .vds, .devices
    ]

    /// The RouterCore name (aftermath re-reads, offline rules).
    var target: ReadTarget {
        switch self {
        case .status:
            return .status
        case .net:
            return .net
        case .data:
            return .data
        case .led:
            return .led
        case .me:
            return .me
        case .zapret:
            return .zapret
        case .tgws:
            return .tgws
        case .mydirect:
            return .mydirect
        case .vds:
            return .vds
        case .devices:
            return .devices
        }
    }

    /// Seconds between timer reads while a visible screen needs the kind; `nil` = no timer (read when the
    /// screen appears, on pull-to-refresh and after actions). `/zapret` drops to 3 s while busy/checking.
    var interval: TimeInterval? {
        switch self {
        case .me:
            // Stage 3: `/me` first on launch/unlock, then every 30 min.
            return 1800
        default:
            return target.defaultInterval
        }
    }

    /// Reaches the router: paused in offline mode (except `/status`, which keeps polling every 30 s).
    var needsRouter: Bool {
        return target.needsRouter
    }
}

/// Polling (contract §7.1, contract-stage4 §4.1).
///
/// - Screens declare what they need with `.pollingScope(_:)` (PollingScope.swift). The store polls the
///   union of the visible scopes, each kind on its own interval, plus `/me` every 30 min.
/// - `runPolling()` runs while the app is active, unlocked and logged in (started by `MainTabView`).
///   Nothing polls in the background (no BGTask).
/// - When a scope appears, its kinds that are due (never read, or older than their interval; kinds without
///   a timer: not read in the last 10 s) are read at once. On return to `.active` every visible kind is read.
extension RouterStore {
    /// Granularity of the scheduler.
    nonisolated static let pollTick: TimeInterval = 1
    /// Kinds without a timer (`/mydirect`, `/devices`) are re-read on appear only if older than this.
    nonisolated static let onAppearMinGap: TimeInterval = 10

    /// Every kind any visible screen needs, plus `/me`.
    var activeKinds: Set<ReadKind> {
        var kinds: Set<ReadKind> = [.me]
        for scope in scopes.values {
            kinds.formUnion(scope)
        }
        return kinds
    }

    /// Register (or update) a visible scope. Due kinds are read at once while polling runs.
    func setScope(_ id: UUID, kinds: Set<ReadKind>) {
        let previous = scopes[id] ?? []
        scopes[id] = kinds
        guard pollingActive else {
            return
        }
        let now = Date()
        for kind in kinds where !inFlight.contains(kind) && shouldPoll(kind) {
            let last = lastAttemptAt[kind]
            var due = last == nil
            if let l = last {
                let age = now.timeIntervalSince(l)
                if let interval = effectiveInterval(kind) {
                    due = age >= interval
                } else {
                    // On-appear kinds: a fresh appearance (not a mere update of the same scope).
                    due = !previous.contains(kind) && age >= RouterStore.onAppearMinGap
                }
            }
            if due {
                Task {
                    await self.read(kind)
                }
            }
        }
    }

    func removeScope(_ id: UUID) {
        scopes[id] = nil
    }

    /// The interval in effect now (`/zapret` 3 s during fast polling).
    func effectiveInterval(_ kind: ReadKind) -> TimeInterval? {
        if kind == .zapret, let since = zapretFastSince {
            let fast = FastPoll(condition: .zapretBusy)
            if Date().timeIntervalSince(since) < fast.maxDuration {
                return fast.every
            }
        }
        return kind.interval
    }

    /// Whether a kind may be read on the timer now.
    func shouldPoll(_ kind: ReadKind) -> Bool {
        guard isLoggedIn, !appDisabled else {
            return false
        }
        if kind.needsRouter && kind != .status && offline {
            return false
        }
        if kind == .net {
            // Paused during a quiet window and under any sheet (a sheet does not fire the card's onDisappear).
            return !isQuiet && !isSheetPresented && pendingConfirm == nil
        }
        return true
    }

    /// Kinds to read on this tick.
    func dueKinds(force: Bool) -> [ReadKind] {
        let now = Date()
        var out: [ReadKind] = []
        for kind in activeKinds where kind != .me || !force {
            if inFlight.contains(kind) || !shouldPoll(kind) {
                continue
            }
            let last = lastAttemptAt[kind]
            if force {
                // Return to `.active`: refresh every visible kind at once (unless just read).
                if let l = last, now.timeIntervalSince(l) < 2 {
                    continue
                }
                out.append(kind)
                continue
            }
            guard let interval = effectiveInterval(kind) else {
                continue
            }
            if let l = last, now.timeIntervalSince(l) < interval {
                continue
            }
            out.append(kind)
        }
        return out
    }

    /// Runs until the calling task is cancelled (app inactive, locked, logged out).
    func runPolling() async {
        guard isLoggedIn else {
            return
        }
        pollingCount += 1
        defer {
            pollingCount -= 1
        }
        // `/me` first and alone (contract §2.5, §7.1): it validates the token before the parallel reads,
        // so a stale token costs one `401 token_*` instead of several (`token_invalid` counts toward fail2ban),
        // and it re-reads `/me` on launch and unlock. Not again within a minute: Control Center or the
        // Face ID sheet also flip the scene inactive → active.
        if lastReadAt[.me].map({ Date().timeIntervalSince($0) > RouterStore.meRecheckAfter }) ?? true {
            await read(.me)
            guard isLoggedIn, !Task.isCancelled else {
                return
            }
        }
        await withDiscardingTaskGroup { group in
            var force = true
            while !Task.isCancelled {
                let kinds = self.dueKinds(force: force)
                force = false
                for kind in kinds {
                    group.addTask {
                        await self.read(kind)
                    }
                }
                do {
                    try await Task.sleep(nanoseconds: RouterStore.nanoseconds(RouterStore.pollTick))
                } catch {
                    break
                }
            }
        }
    }

    /// Pull-to-refresh of a screen: `/me` first (token check), then `kinds` in parallel. Never runs actions.
    func refresh(_ kinds: Set<ReadKind>) async {
        guard isLoggedIn else {
            return
        }
        appDisabled = false
        await read(.me)
        guard isLoggedIn else {
            return
        }
        let list = Array(kinds.subtracting([.me]))
        await withTaskGroup(of: Void.self) { group in
            for kind in list {
                group.addTask {
                    await self.read(kind)
                }
            }
        }
    }

    /// Stage 3 name: Summary pull-to-refresh.
    func refreshAll() async {
        await refresh(SummaryKinds.all)
    }

    /// Kinds for a RouterCore re-read target: `/data` → every range a visible screen uses (day if none).
    func kinds(for target: ReadTarget) -> [ReadKind] {
        switch target {
        case .status:
            return [.status]
        case .net:
            return [.net]
        case .data:
            var out: [ReadKind] = []
            for kind in activeKinds {
                if case .data = kind {
                    out.append(kind)
                }
            }
            return out.isEmpty ? [.data(.day)] : out
        case .led:
            return [.led]
        case .me:
            return [.me]
        case .zapret:
            return [.zapret]
        case .tgws:
            return [.tgws]
        case .mydirect:
            return [.mydirect]
        case .vds:
            return [.vds]
        case .devices:
            return [.devices]
        }
    }

    /// Read now (not waiting for the timer), e.g. after an error that says the list is stale.
    func rereadNow(_ target: ReadTarget) {
        for kind in kinds(for: target) {
            Task {
                await self.read(kind)
            }
        }
    }
}

/// The reads of «Сводка» (stage 3 §7.1); `/net` is added by the «Интернет сейчас» card itself.
enum SummaryKinds {
    static let all: Set<ReadKind> = [.status, .data(.day), .led]
}
