import Foundation
import RouterCore

// «Настройки» (contract-stage4 §5.6): computed views of `/devices` (who has access, login journal) and the
// three access actions. No stored state here — dialogs and toggles live in the Settings views.
// `/me` and `/devices` come from the server, so all of Settings works while the router is offline.

extension RouterStore {
    /// What the Settings sheet reads (contract-stage4 §4.2): `/me` and `/devices` (no timer: on open,
    /// after a revoke — the store re-reads — and on pull-to-refresh).
    var settingsKinds: Set<ReadKind> {
        return [.me, .devices]
    }

    /// This phone's key id (from login / `/me`), or nil.
    private var ownDeviceID: String? {
        if let id = sessionInfo?.deviceID, !id.isEmpty {
            return id
        }
        if let id = me?.device.id, !id.isEmpty {
            return id
        }
        return nil
    }

    /// Phones with the app (`apps`), this one marked; nil until `/devices` is loaded.
    /// A row whose id is our own key is treated as this phone even if the server did not flag it,
    /// so «Отозвать» is never offered for it (that is «Выйти на этом iPhone»).
    func accessPhones(now: Date) -> [PhoneRow]? {
        guard let list = accessList else {
            return nil
        }
        let own = ownDeviceID
        return Access.phones(list, now: now.timeIntervalSince1970).map { row in
            var r = row
            if let own = own, r.id == own, !r.isCurrent {
                r.isCurrent = true
                r.tag = AccessTexts.thisPhone
            }
            return r
        }
    }

    /// Live web-panel sessions (`web`); nil until `/devices` is loaded.
    func accessBrowsers(now: Date) -> [BrowserRow]? {
        guard let list = accessList else {
            return nil
        }
        return Access.browsers(list, now: now.timeIntervalSince1970)
    }

    /// «Входы в приложение» (`logins`, newest first); nil until loaded.
    func accessAppLogins(now: Date) -> [AccessLogRow]? {
        guard let list = accessList else {
            return nil
        }
        return Access.logins(list, now: now.timeIntervalSince1970)
    }

    /// «Все входы и выходы» (`auth_log`, newest first); nil until loaded.
    func accessAuthLog(now: Date) -> [AccessLogRow]? {
        guard let list = accessList else {
            return nil
        }
        return Access.authLog(list, now: now.timeIntervalSince1970)
    }

    // MARK: - Actions (all server-only: allowed while the router is offline)

    /// «Отозвать» a phone, after the app dialog (no server confirm, no Face ID). Never for this phone.
    /// 200 → toast + `/devices` re-read; 404 → «Этого входа уже нет — список обновлён.» + re-read (store).
    @discardableResult
    func revokePhone(_ row: PhoneRow, completion: ActionCompletion? = nil) -> Bool {
        guard let action = row.revokeAction, row.id != ownDeviceID else {
            completion?(.cancelled)
            return false
        }
        return perform(action, label: row.name, destructive: true, symbol: "iphone.slash", completion: completion)
    }

    /// «Закрыть» a web-panel session, after the app dialog.
    @discardableResult
    func closeWebSession(_ row: BrowserRow, completion: ActionCompletion? = nil) -> Bool {
        return perform(row.revokeAction, label: row.title, destructive: true, symbol: "xmark.circle", completion: completion)
    }

    /// «Выйти везде»: `POST /devices/revoke-all {"web"}` → 428 critical (red, Face ID) → 200 → LOGOUT with
    /// the banner (all done by the action runner).
    @discardableResult
    func revokeEverywhere(includeWeb: Bool, completion: ActionCompletion? = nil) -> Bool {
        return perform(
            .revokeAll(web: includeWeb),
            destructive: true,
            symbol: "rectangle.portrait.and.arrow.right",
            completion: completion
        )
    }

    /// A revoke of this phone / web session is running (spinner on its row).
    func isRevoking(phone id: String) -> Bool {
        return isRunning(.revokeApp(id: id))
    }

    func isRevoking(web ref: String) -> Bool {
        return isRunning(.revokeWeb(ref: ref))
    }

    /// «Выйти везде» is being sent or waits in its 428 dialog.
    var isRevokeAllBusy: Bool {
        if isRunning(named: "revoke-all") {
            return true
        }
        return pendingConfirm?.action.name == "revoke-all"
    }
}
