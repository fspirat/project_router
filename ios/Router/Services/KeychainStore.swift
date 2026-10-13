import Foundation
import Security
import RouterCore

/// The device token in Keychain (contract §7.7):
/// `kSecClassGenericPassword`, service `xyz.fspirat.router`, account `device-token`,
/// `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` (not synchronizable: not in iCloud or backups).
///
/// Only a token that passes `Validation.isValidToken` is stored or returned, so a damaged item is
/// never sent (`token_invalid` counts toward fail2ban). Keychain outlives a delete + reinstall while
/// UserDefaults does not: on the first launch of an install `RouterStore.init` deletes a leftover token
/// and revokes it on the server (`AppSettings.installMarkerKey`).
struct KeychainStore {
    let service: String
    let account: String

    init(service: String = KeychainConfig.service, account: String = KeychainConfig.account) {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    func readToken() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        guard let token = String(data: data, encoding: .utf8), Validation.isValidToken(token) else {
            return nil
        }
        return token
    }

    var hasToken: Bool {
        return readToken() != nil
    }

    /// Saves (or replaces) the token. Returns false if Keychain refused it.
    @discardableResult
    func saveToken(_ token: String) -> Bool {
        guard Validation.isValidToken(token) else {
            return false
        }
        let data = Data(token.utf8)
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess {
            return true
        }
        if updateStatus != errSecItemNotFound {
            // Something odd about the old item: remove it and add a fresh one.
            deleteToken()
        }
        var add = baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(add as CFDictionary, nil)
        return addStatus == errSecSuccess
    }

    /// LOGOUT and 401 `token_*`.
    func deleteToken() {
        _ = SecItemDelete(baseQuery as CFDictionary)
    }
}
