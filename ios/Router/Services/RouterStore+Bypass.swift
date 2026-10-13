import Foundation
import RouterCore

// «Обход» tab (contract-stage4 §5.4): read-only views of the shared caches (`/zapret`, `/tgws`, `/mydirect`,
// `/status` for the services toggles). Computed only — extensions cannot hold state; per-screen UI state
// (search text, the domain field, expanded sections) lives in the views.

/// What the Bypass screen reads (contract-stage4 §4.2): `/zapret` 30 s (3 s while busy/checking),
/// `/tgws` 60 s, `/mydirect` on appear and after actions, `/status` 30 s.
enum BypassKinds {
    static let all: Set<ReadKind> = [.status, .zapret, .tgws, .mydirect]
}

extension RouterStore {
    // MARK: - Whole screen

    /// Cold start while the router is offline: nothing to show yet (contract-stage4 §4.3).
    var bypassHasNoRouterData: Bool {
        return offline && status == nil && zapret == nil && tgws == nil && mydirect == nil
    }

    /// Last known router data is on screen while the router is offline → dim it, show the caption.
    var bypassShowsStaleData: Bool {
        return offline && (status != nil || zapret != nil || tgws != nil || mydirect != nil)
    }

    /// A card whose data never arrived while the router is offline (proposed text, contract-stage4 §4.3).
    static let bypassOfflineEmpty = "Роутер не на связи — появится, когда он вернётся."

    // MARK: - zapret

    /// zapret card presentation (RouterCore `Zapret.info`).
    func zapretInfo(now: Date = Date()) -> ZapretInfo {
        return Zapret.info(zapret, now: now.timeIntervalSince1970)
    }

    /// The strategy being verified after `zapretstrat` (spinner next to the segmented control).
    var verifyingStrategy: Int? {
        if case .zapretStrategy(let n)? = verification {
            return n
        }
        return nil
    }

    /// The toggle action is enabled now (RouterCore state + the app-wide action rules).
    func canToggleZapret(_ info: ZapretInfo) -> Bool {
        return info.showsControls && info.toggleEnabled && canPerform(info.toggleAction)
    }

    func canChangeStrategy(_ info: ZapretInfo) -> Bool {
        return info.showsControls && info.strategyEnabled && verifyingStrategy == nil
            && canPerform(.zapretstrat(n: info.strategy))
    }

    func canCheckZapret(_ info: ZapretInfo) -> Bool {
        return info.showsControls && info.checkEnabled && canPerform(.zapretcheck)
    }

    /// Segmented «1 / 2 / 3»: no dialog (plan §2); the store verifies it applied (+2, +4, +7 s).
    func selectZapretStrategy(_ n: Int) {
        let info = zapretInfo()
        guard n != info.strategy, Zapret.strategies.contains(where: { $0.n == n }), canChangeStrategy(info) else {
            return
        }
        perform(.zapretstrat(n: n), symbol: "slider.horizontal.3")
    }

    // MARK: - Telegram через Cloudflare

    var tgwsInfo: TgwsInfo {
        return Tgws.info(tgws)
    }

    /// `tgwsset` is being verified on the +3 s / +8 s re-reads.
    var verifyingTgws: Bool {
        if case .tgws? = verification {
            return true
        }
        return false
    }

    func canToggleTgws(_ info: TgwsInfo) -> Bool {
        return info.showsToggle && !verifyingTgws && canPerform(info.toggleAction)
    }

    // MARK: - Сервисы напрямую

    /// Rows for the services toggles (empty before the first `/status`).
    var svcDirectRows: [SvcDirectRow] {
        guard let s = status else {
            return []
        }
        return SvcDirect.rows(s)
    }

    func canToggleService(_ row: SvcDirectRow) -> Bool {
        guard let action = row.toggleAction else {
            return false
        }
        return canPerform(action)
    }

    // MARK: - MyDirect

    /// Lists for the search text, or nil before the first successful `/mydirect`.
    func myDirectInfo(query: String) -> MyDirectInfo? {
        guard let list = mydirect else {
            return nil
        }
        return MyDirect.info(list, query: query)
    }

    /// `/mydirect` answered `500 no rule` (or never loaded and failed): the card shows the message instead of
    /// the lists; add/remove are disabled (contract-stage4 §5.4.6).
    var myDirectRuleMissing: Bool {
        guard let message = readError(.mydirect) else {
            return false
        }
        return message.contains("MyDirect")
    }

    /// Add/remove may be offered at all (the list is known and the rule exists).
    var myDirectEditable: Bool {
        return mydirect != nil && !myDirectRuleMissing
    }
}
