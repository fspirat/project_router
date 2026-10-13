import Foundation

/// Client-side checks and sanitizers (contract §1.2, §2.1, §7.9).
public enum Validation {
    public static let deviceNameMaxLength = 40
    public static let asciiFieldMaxLength = 32
    public static let passwordMaxBytes = 200

    /// `^fsr1_[A-Za-z0-9_-]{43}$` (48 characters).
    public static func isValidToken(_ token: String) -> Bool {
        let scalars = Array(token.unicodeScalars)
        guard scalars.count == 48, token.hasPrefix("fsr1_") else {
            return false
        }
        var i = 5
        while i < scalars.count {
            let v = scalars[i].value
            let ok = isAlnum(v) || v == 0x5F || v == 0x2D
            if !ok {
                return false
            }
            i += 1
        }
        return true
    }

    /// 64 lowercase hex.
    public static func isValidLoginID(_ id: String) -> Bool {
        return isLowerHex(id, length: 64)
    }

    /// 16 lowercase hex.
    public static func isValidJobID(_ id: String) -> Bool {
        return isLowerHex(id, length: 16)
    }

    /// Confirm token from a 428: 1–64 lowercase hex (the server sends 32).
    public static func isValidConfirm(_ confirm: String) -> Bool {
        let n = confirm.unicodeScalars.count
        guard n >= 1 && n <= 64 else {
            return false
        }
        return isLowerHex(confirm, length: n)
    }

    /// Device name for login: strip `\x00-\x1f` and `\x7f`, trim, keep at most 40
    /// Unicode code points without cutting a character in half, trim again.
    /// An empty result means «Войти» must stay disabled.
    public static func sanitizeDeviceName(_ name: String) -> String {
        var cleaned = String.UnicodeScalarView()
        for u in name.unicodeScalars {
            if u.value < 0x20 || u.value == 0x7F {
                continue
            }
            cleaned.append(u)
        }
        let trimmed = String(cleaned).trimmingCharacters(in: .whitespacesAndNewlines)
        return clampScalars(trimmed, max: deviceNameMaxLength).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// For a text field while typing: removes control characters and limits to 40 code points (no trimming).
    public static func limitDeviceNameInput(_ name: String) -> String {
        var cleaned = String.UnicodeScalarView()
        for u in name.unicodeScalars {
            if u.value < 0x20 || u.value == 0x7F {
                continue
            }
            cleaned.append(u)
        }
        return clampScalars(String(cleaned), max: deviceNameMaxLength)
    }

    public static func isValidDeviceName(_ name: String) -> Bool {
        return !sanitizeDeviceName(name).isEmpty
    }

    /// `model`, `os`, `app`: keep only printable ASCII (`\x20-\x7e`), at most 32 characters.
    public static func sanitizeASCII(_ value: String, maxLength: Int = 32) -> String {
        var out = String.UnicodeScalarView()
        var count = 0
        for u in value.unicodeScalars {
            if count >= maxLength {
                break
            }
            if u.value >= 0x20 && u.value <= 0x7E {
                out.append(u)
                count += 1
            }
        }
        return String(out)
    }

    /// Non-empty (an empty password is a real failed attempt) and at most 200 UTF-8 bytes.
    public static func isValidPassword(_ password: String) -> Bool {
        let n = password.utf8.count
        return n >= 1 && n <= passwordMaxBytes
    }

    /// LuCI link: `^https://[\w.-]+(:\d+)?/?$`.
    public static func isValidLuciURL(_ s: String) -> Bool {
        guard s.hasPrefix("https://") else {
            return false
        }
        let rest = Array(s.unicodeScalars.dropFirst(8))
        var i = 0
        var hostLen = 0
        while i < rest.count {
            let v = rest[i].value
            if isAlnum(v) || v == 0x5F || v == 0x2E || v == 0x2D {
                hostLen += 1
                i += 1
            } else {
                break
            }
        }
        if hostLen == 0 {
            return false
        }
        if i < rest.count && rest[i].value == 0x3A {
            i += 1
            var digits = 0
            while i < rest.count && rest[i].value >= 0x30 && rest[i].value <= 0x39 {
                digits += 1
                i += 1
            }
            if digits == 0 {
                return false
            }
        }
        if i < rest.count && rest[i].value == 0x2F {
            i += 1
        }
        return i == rest.count
    }

    /// Bot username: `^[A-Za-z0-9_]{5,32}$`.
    public static func isValidBotName(_ s: String) -> Bool {
        let scalars = Array(s.unicodeScalars)
        guard scalars.count >= 5 && scalars.count <= 32 else {
            return false
        }
        for u in scalars {
            if !(isAlnum(u.value) || u.value == 0x5F) {
                return false
            }
        }
        return true
    }

    /// Locally administered ("hidden", randomized) MAC: second hex digit is 2, 6, a or e.
    public static func isRandomizedMAC(_ mac: String) -> Bool {
        let chars = Array(mac.lowercased())
        guard chars.count >= 2 else {
            return false
        }
        let c = chars[1]
        return c == "2" || c == "6" || c == "a" || c == "e"
    }

    // MARK: - Stage 4 action parameters (mirror `app_action_spec`, server/auth/app.php)

    /// Own device name limit (`mb_strlen` after trim on the server → code points).
    public static let renameMaxLength = 40
    /// MyDirect domain limit, bytes.
    public static let domainMaxBytes = 100
    /// svcdirect service name limit, UTF-8 bytes.
    public static let serviceNameMaxBytes = 40

    /// Texts for refused parameters (inline under the field).
    public static let domainHint = "Нужен домен вида site.ru"
    public static let sameTimeHint = "Укажи разное время выключения и включения."
    public static let badTimeHint = "Неверное время."
    public static let serviceNameHint = "Это имя нельзя изменить из приложения."

    /// `^([0-9a-f]{2}:){5}[0-9a-f]{2}$` — lowercase only (uppercase → 400 on the server).
    public static func isValidMAC(_ mac: String) -> Bool {
        let s = Array(mac.unicodeScalars)
        guard s.count == 17 else {
            return false
        }
        for (i, u) in s.enumerated() {
            if i % 3 == 2 {
                if u.value != 0x3A {
                    return false
                }
            } else {
                let v = u.value
                if !((v >= 0x30 && v <= 0x39) || (v >= 0x61 && v <= 0x66)) {
                    return false
                }
            }
        }
        return true
    }

    /// Node id for `pingone`/`switch`: `^[A-Za-z0-9]{1,32}$` (so `_direct` never passes; `direct` passes the regex
    /// but is meaningful only for `switch`).
    public static func isValidNodeID(_ id: String) -> Bool {
        let s = Array(id.unicodeScalars)
        guard s.count >= 1 && s.count <= 32 else {
            return false
        }
        return s.allSatisfy { isAlnum($0.value) }
    }

    /// Subscription id for `subupdate`: `^[A-Za-z0-9_]{1,32}$`.
    public static func isValidSubscriptionID(_ sid: String) -> Bool {
        let s = Array(sid.unicodeScalars)
        guard s.count >= 1 && s.count <= 32 else {
            return false
        }
        return s.allSatisfy { isAlnum($0.value) || $0.value == 0x5F }
    }

    /// `^([01][0-9]|2[0-3])[0-5][0-9]$` («2300», «0700»).
    public static func isValidHHMM(_ t: String) -> Bool {
        let s = Array(t.unicodeScalars).map { Int($0.value) - 0x30 }
        guard s.count == 4, s.allSatisfy({ $0 >= 0 && $0 <= 9 }) else {
            return false
        }
        let hour = s[0] * 10 + s[1]
        return hour <= 23 && s[2] <= 5
    }

    /// The server domain regex `^([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z][a-z0-9-]{0,61}[a-z0-9]$`
    /// and ≤ 100 bytes. Cyrillic (`.рф`) and uppercase fail.
    public static func isValidDomain(_ d: String) -> Bool {
        guard !d.isEmpty, d.utf8.count <= domainMaxBytes else {
            return false
        }
        let labels = d.split(separator: ".", omittingEmptySubsequences: false).map { Array($0.unicodeScalars) }
        guard labels.count >= 2 else {
            return false
        }
        func lowerAlnum(_ u: Unicode.Scalar) -> Bool {
            let v = u.value
            return (v >= 0x30 && v <= 0x39) || (v >= 0x61 && v <= 0x7A)
        }
        for (i, label) in labels.enumerated() {
            let last = i == labels.count - 1
            if last {
                // [a-z][a-z0-9-]{0,61}[a-z0-9]: 2…63 characters
                guard label.count >= 2 && label.count <= 63 else {
                    return false
                }
                let f = label[0].value
                guard f >= 0x61 && f <= 0x7A else {
                    return false
                }
            } else {
                // [a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?: 1…63 characters
                guard label.count >= 1 && label.count <= 63, lowerAlnum(label[0]) else {
                    return false
                }
            }
            guard lowerAlnum(label[label.count - 1]) else {
                return false
            }
            for u in label where !(lowerAlnum(u) || u.value == 0x2D) {
                return false
            }
        }
        return true
    }

    /// svcdirect name: 1…40 UTF-8 bytes, none of `\x00-\x1f \x7f ~ ! " < > & \ |`.
    public static func isValidServiceName(_ name: String) -> Bool {
        let n = name.utf8.count
        guard n >= 1 && n <= serviceNameMaxBytes else {
            return false
        }
        for u in name.unicodeScalars {
            let v = u.value
            if v < 0x20 || v == 0x7F {
                return false
            }
            if "~!\"<>&\\|".unicodeScalars.contains(u) {
                return false
            }
        }
        return true
    }

    /// 16 lowercase hex (app key id, web session ref).
    public static func isValidHex16(_ s: String) -> Bool {
        return isLowerHex(s, length: 16)
    }

    /// The `rename` value that is sent: trimmed (the server trims too). `""` removes the own name.
    public static func renameValue(_ name: String) -> String {
        return name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// For the rename text field while typing: removes control characters and limits to 40 code points.
    public static func limitRenameInput(_ name: String) -> String {
        var cleaned = String.UnicodeScalarView()
        for u in name.unicodeScalars where !(u.value < 0x20 || u.value == 0x7F) {
            cleaned.append(u)
        }
        return clampScalars(String(cleaned), max: renameMaxLength)
    }

    /// `nil` when the server would accept the parameters; else a local error that `APIClient.perform` throws
    /// without sending (`bad_param`, or `too_long` for a long name). `message` is ready to show.
    public static func actionError(_ action: RouterAction) -> APIError? {
        let generic = APIError.client(code: "bad_param", message: APIError.fallbackTexts["bad_param"])
        switch action {
        case .ping, .restart, .update, .reboot, .ledset, .subupdateAll, .speedtest, .zapretset, .zapretcheck, .tgwsset, .revokeAll:
            return nil
        case .pingone(let id):
            return isValidNodeID(id) && id != "direct" ? nil : generic
        case .switchServer(let id):
            return isValidNodeID(id) ? nil : generic
        case .subupdate(let sid):
            return isValidSubscriptionID(sid) ? nil : generic
        case .block(let mac), .unblock(let mac), .direct(let mac, _), .scheduleClear(let mac):
            return isValidMAC(mac.lowercased()) ? nil : generic
        case .schedule(let mac, let off, let on):
            guard isValidMAC(mac.lowercased()) else {
                return generic
            }
            guard isValidHHMM(off) && isValidHHMM(on) else {
                return APIError.client(code: "bad_param", message: badTimeHint)
            }
            return off == on ? APIError.client(code: "bad_param", message: sameTimeHint) : nil
        case .diradd(let d), .dirdel(let d):
            return isValidDomain(d) ? nil : APIError.client(code: "bad_param", message: domainHint)
        case .svcdirect(let name, _):
            return isValidServiceName(name) ? nil : APIError.client(code: "bad_param", message: serviceNameHint)
        case .zapretstrat(let n):
            return (1...3).contains(n) ? nil : generic
        case .rename(let mac, let name):
            guard isValidMAC(mac.lowercased()) else {
                return generic
            }
            for u in name.unicodeScalars where u.value < 0x20 || u.value == 0x7F {
                return generic
            }
            if renameValue(name).unicodeScalars.count > renameMaxLength {
                return APIError.client(code: "too_long", message: APIError.fallbackTexts["too_long"])
            }
            return nil
        case .revokeApp(let id):
            return isValidHex16(id) ? nil : generic
        case .revokeWeb(let ref):
            return isValidHex16(ref) ? nil : generic
        }
    }

    // MARK: - Internals

    static func isAlnum(_ v: UInt32) -> Bool {
        return (v >= 0x30 && v <= 0x39) || (v >= 0x41 && v <= 0x5A) || (v >= 0x61 && v <= 0x7A)
    }

    static func isLowerHex(_ s: String, length: Int) -> Bool {
        let scalars = Array(s.unicodeScalars)
        guard scalars.count == length else {
            return false
        }
        for u in scalars {
            let v = u.value
            if !((v >= 0x30 && v <= 0x39) || (v >= 0x61 && v <= 0x66)) {
                return false
            }
        }
        return true
    }

    /// Keeps whole characters while the total number of code points stays ≤ `max`.
    static func clampScalars(_ s: String, max limit: Int) -> String {
        var out = ""
        var count = 0
        for ch in s {
            let n = ch.unicodeScalars.count
            if count + n > limit {
                break
            }
            out.append(ch)
            count += n
        }
        return out
    }
}
