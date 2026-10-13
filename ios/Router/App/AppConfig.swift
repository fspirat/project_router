import Foundation
import RouterCore

/// Build-time configuration from Info.plist (written by XcodeGen from ios/project.yml).
enum AppConfig {
    /// `FSRBaseURL` (build setting `FSR_BASE_URL`). Must be https; otherwise the built-in default.
    static var baseURL: URL {
        return resolveBaseURL(infoString("FSRBaseURL"))
    }

    static func resolveBaseURL(_ raw: String?) -> URL {
        guard let raw = raw else {
            return APIClient.defaultBaseURL
        }
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.lowercased().hasPrefix("https://"),
              let comps = URLComponents(string: s),
              let host = comps.host, !host.isEmpty,
              let url = comps.url else {
            return APIClient.defaultBaseURL
        }
        return url
    }

    static var version: String {
        return infoString("CFBundleShortVersionString") ?? "1.0"
    }

    static var build: String {
        return infoString("CFBundleVersion") ?? "1"
    }

    /// "1.0 (42)" — login `device.app` and Settings «О приложении».
    static var appString: String {
        return "\(version) (\(build))"
    }

    /// `FSRBuildDate` ("YYYY-MM-DD", UTC; written by CI) as unix seconds; `nil` for local builds.
    static var buildDate: Int? {
        return parseBuildDate(infoString("FSRBuildDate"))
    }

    /// TestFlight builds live 90 days.
    static var testFlightExpiry: Int? {
        guard let date = buildDate else {
            return nil
        }
        return date + Int(ExpiryNotice.buildLifetime)
    }

    static func parseBuildDate(_ raw: String?) -> Int? {
        guard let raw = raw else {
            return nil
        }
        let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              year >= 2020, year <= 2200, month >= 1, month <= 12, day >= 1, day <= 31 else {
            return nil
        }
        var calendar = Calendar(identifier: .gregorian)
        guard let utc = TimeZone(secondsFromGMT: 0) else {
            return nil
        }
        calendar.timeZone = utc
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        guard let date = calendar.date(from: comps) else {
            return nil
        }
        return Int(date.timeIntervalSince1970)
    }

    private static func infoString(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// App-side formatting that RouterCore does not have (Europe/Samara like everything else).
enum AppFormat {
    /// «11.01.2027».
    static func dateDMY(_ ts: Int) -> String {
        let t = Fmt.localTime(ts)
        return "\(twoDigits(t.day)).\(twoDigits(t.month)).\(t.year)"
    }

    static func twoDigits(_ n: Int) -> String {
        return n < 10 ? "0\(n)" : "\(n)"
    }
}
