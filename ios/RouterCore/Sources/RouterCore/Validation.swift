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
