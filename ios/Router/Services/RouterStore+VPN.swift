import Foundation
import RouterCore

/// «VPN» tab helpers on the shared store (contract-stage4 §5.1). Computed properties and methods only:
/// per-screen UI state (chart range, sort, opened server) lives in the VPN views.
extension RouterStore {
    /// Reads of the VPN tab (contract-stage4 §4.2): `/status` 30 s, `/data` of the chart range 60 s, `/vds` 300 s.
    static func vpnKinds(range: DataRange) -> Set<ReadKind> {
        return [.status, .data(range), .vds]
    }

    /// Extra warning line in the switch confirm when Split is not the global node (contract-stage4 §3.3).
    var vpnSwitchNote: String? {
        guard let s = status, !s.splitActive else {
            return nil
        }
        return VPNTexts.splitSwitchWarning
    }

    /// Router data is the last known copy (offline with a cached status): dim it and say so.
    var vpnShowsStaleData: Bool {
        return offline && status != nil
    }

    /// «Подключить» a node: `switch {"id"}` → 428 high (the server adds the «не отвечает» warning itself
    /// when the node's ping is 0) → the identical resend.
    @discardableResult
    func vpnConnect(id: String, name: String, completion: ActionCompletion? = nil) -> Bool {
        return perform(
            .switchServer(id: id),
            label: name,
            note: vpnSwitchNote,
            symbol: "bolt.horizontal.circle",
            completion: completion
        )
    }

    /// «Напрямую, без VPN»: `switch {"id":"direct"}` → 428 critical → Face ID → resend.
    @discardableResult
    func vpnGoDirect(completion: ActionCompletion? = nil) -> Bool {
        return perform(
            .switchDirect,
            label: Summary.directName,
            note: vpnSwitchNote,
            symbol: "exclamationmark.shield",
            completion: completion
        )
    }

    /// This exact action is being sent or waits in its 428 sheet (spinner on its control).
    func vpnIsBusy(_ action: RouterAction) -> Bool {
        return isRunning(action) || isConfirming(action)
    }

    /// «Проверить все серверы» = the Summary «Проверить» (ping job, ~20 s). When VPN does not pass right now
    /// `tap` asks the stage 3 pre-dialog first; the topmost presentation host shows it on this tab.
    func vpnCheckAll() {
        guard isEnabled(.check) else {
            return
        }
        tap(.check)
    }
}
