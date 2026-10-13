import Foundation

// Stage 4 reads (contract-stage4 §2) and action result bodies (§3, §10.9).
// Same lenient decoding as `Models.swift`: missing / wrong-typed fields fall back to defaults.

// MARK: - /zapret

/// `GET /zapret` (CGI `zapret`, contract-stage4 §2.3).
public struct ZapretState: Decodable, Equatable, Sendable {
    /// `{"installed":false,"absent":true}`: the script is not on the router.
    public var absent: Bool
    /// nfqws + lists + kernel module.
    public var installed: Bool
    /// The chosen mode.
    public var enabled: Bool
    /// 1, 2 or 3 (default 3).
    public var strategy: Int
    /// nfqws is running.
    public var engine: Bool
    /// nftables queue rules exist.
    public var nft: Bool
    /// Split has fsZapret → _direct in uci.
    public var routeCfg: Bool
    /// The rule is in the running Xray config.
    public var routeLive: Bool
    /// The engine failed: YouTube/Discord temporarily via VPN.
    public var fallback: Bool
    /// "" or a ready Russian text.
    public var error: String
    public var pktsTCP: Int
    public var pktsUDP: Int
    /// 0 or 1 (not a count).
    public var vpnExcluded: Int
    public var version: String
    /// The zapret lock is held (on/off/strategy or the 1-min «ensure»).
    public var busy: Bool
    /// A check is running.
    public var checking: Bool
    public var check: ZapretCheck?

    public init(json v: JSONValue) {
        absent = v.flag("absent") ?? false
        installed = v.flag("installed") ?? false
        enabled = v.flag("enabled") ?? false
        strategy = v.num("strategy") ?? 3
        engine = v.flag("engine") ?? false
        nft = v.flag("nft") ?? false
        routeCfg = v.flag("route_cfg") ?? false
        routeLive = v.flag("route_live") ?? false
        fallback = v.flag("fallback") ?? false
        error = v.str("error") ?? ""
        pktsTCP = v.num("pkts_tcp") ?? 0
        pktsUDP = v.num("pkts_udp") ?? 0
        vpnExcluded = v.num("vpn_excluded") ?? 0
        version = v.str("version") ?? ""
        busy = v.flag("busy") ?? false
        checking = v.flag("checking") ?? false
        if let c = v.obj("check") {
            check = ZapretCheck(json: c)
        } else {
            check = nil
        }
    }

    public init(from decoder: Decoder) throws {
        self.init(json: try JSONValue.decodeObject(from: decoder))
    }

    /// `engine && nft && routeLive`.
    public var isWorking: Bool {
        return engine && nft && routeLive
    }
}

/// `zapret.check`: `{"error":"xray"}` or `{ts, via, list}`.
public struct ZapretCheck: Decodable, Equatable, Sendable {
    /// "xray" when Xray was not running; else "".
    public var error: String
    public var ts: Int
    /// "isp", "vpn" or "unknown".
    public var via: String
    public var list: [ZapretCheckItem]

    public init(json v: JSONValue) {
        error = v.str("error") ?? ""
        ts = v.num("ts") ?? 0
        via = v.str("via") ?? ""
        list = v.objects("list").map { ZapretCheckItem(json: $0) }
    }

    public init(from decoder: Decoder) throws {
        self.init(json: try JSONValue.decodeObject(from: decoder))
    }
}

public struct ZapretCheckItem: Decodable, Equatable, Sendable {
    /// «YouTube», «YouTube видео», «Discord API», «Discord CDN».
    public var name: String
    public var ok: Bool
    /// HTTP code as text ("204", "000").
    public var code: String
    /// Full request time (connection + TLS + response), not a ping.
    public var ms: Int
    /// Packets handled by zapret.
    public var queued: Int

    public init(json v: JSONValue) {
        name = v.str("name") ?? ""
        ok = v.flag("ok") ?? false
        code = v.str("code") ?? ""
        ms = v.num("ms") ?? 0
        queued = v.num("queued") ?? 0
    }

    public init(from decoder: Decoder) throws {
        self.init(json: try JSONValue.decodeObject(from: decoder))
    }
}

// MARK: - /tgws

/// `GET /tgws` (contract-stage4 §2.4). `host`/`port` are informational: never build a proxy link.
public struct TgwsState: Decodable, Equatable, Sendable {
    public var absent: Bool
    public var installed: Bool
    /// The nft redirect table exists.
    public var auto: Bool
    /// Packets counted by the redirect rule (≈ connections).
    public var redirected: Int
    public var enabled: Bool
    /// The proxy process runs.
    public var running: Bool
    /// Port 1443 listens.
    public var listening: Bool
    public var host: String
    public var port: Int
    public var version: String

    public init(json v: JSONValue) {
        absent = v.flag("absent") ?? false
        installed = v.flag("installed") ?? false
        auto = v.flag("auto") ?? false
        redirected = v.num("redirected") ?? 0
        enabled = v.flag("enabled") ?? false
        running = v.flag("running") ?? false
        listening = v.flag("listening") ?? false
        host = v.str("host") ?? ""
        port = v.num("port") ?? 0
        version = v.str("version") ?? ""
    }

    public init(from decoder: Decoder) throws {
        self.init(json: try JSONValue.decodeObject(from: decoder))
    }
}

// MARK: - /mydirect

/// `GET /mydirect` (contract-stage4 §2.5).
public struct MyDirectList: Decodable, Equatable, Sendable {
    /// The whole MyDirect `domain_list` (plain domains, `geosite:`-style entries, svcdirect hosts).
    public var domains: [String]
    /// Added from the panel or the app: the only removable entries.
    public var added: [String]

    public init(domains: [String], added: [String]) {
        self.domains = domains
        self.added = added
    }

    public init(json v: JSONValue) {
        domains = v.strings("domains")
        added = v.strings("added")
    }

    public init(from decoder: Decoder) throws {
        self.init(json: try JSONValue.decodeObject(from: decoder))
    }
}

// MARK: - /vds

/// `GET /vds` (own servers, server file, works offline; contract-stage4 §2.6).
public struct VdsResponse: Decodable, Equatable, Sendable {
    /// When fspirat-watch wrote the file; `nil` = no data yet.
    public var ts: Int?
    public var servers: [VdsServer]

    public init(json v: JSONValue) {
        ts = v.num("ts")
        servers = v.objects("servers").map { VdsServer(json: $0) }
    }

    public init(from decoder: Decoder) throws {
        self.init(json: try JSONValue.decodeObject(from: decoder))
    }
}

public struct VdsServer: Decodable, Equatable, Sendable {
    public var name: String
    /// The panel server itself.
    public var local: Bool
    /// `nil` = not reachable over SSH.
    public var stat: VdsStat?

    public init(json v: JSONValue) {
        name = v.str("name") ?? ""
        local = v.flag("local") ?? false
        if let s = v.obj("stat") {
            stat = VdsStat(json: s)
        } else {
            stat = nil
        }
    }

    public init(from decoder: Decoder) throws {
        self.init(json: try JSONValue.decodeObject(from: decoder))
    }
}

public struct VdsStat: Decodable, Equatable, Sendable {
    /// Uptime, seconds.
    public var up: Int
    public var cores: Int
    /// KiB.
    public var memTotal: Int
    public var memAvail: Int
    /// Bytes since boot.
    public var rx: Int
    public var tx: Int
    /// Established TCP on :443/:10445.
    public var conns: Int
    /// «0.08 0.05 0.01».
    public var load: String
    /// «37%».
    public var disk: String
    /// `systemctl is-active xray`: "active", "inactive", "failed", "".
    public var xray: String

    public init(json v: JSONValue) {
        up = v.num("up") ?? 0
        cores = v.num("cores") ?? 0
        memTotal = v.num("mem_total") ?? 0
        memAvail = v.num("mem_avail") ?? 0
        rx = v.num("rx") ?? 0
        tx = v.num("tx") ?? 0
        conns = v.num("conns") ?? 0
        load = v.str("load") ?? ""
        disk = v.str("disk") ?? ""
        xray = v.str("xray") ?? ""
    }

    public init(from decoder: Decoder) throws {
        self.init(json: try JSONValue.decodeObject(from: decoder))
    }
}

// MARK: - /devices (who has access)

/// `GET /devices` (contract-stage4 §2.7).
public struct AccessList: Decodable, Equatable, Sendable {
    /// Active app keys, `seen` DESC.
    public var apps: [AppAccess]
    /// Live web sessions, `seen` DESC.
    public var web: [WebSession]
    /// Last 20 app logins, newest first.
    public var logins: [LoginRecord]
    /// Last ≤30 lines of the login journal, newest first.
    public var authLog: [AuthLogEntry]

    public init(json v: JSONValue) {
        apps = v.objects("apps").map { AppAccess(json: $0) }
        web = v.objects("web").map { WebSession(json: $0) }
        logins = v.objects("logins").map { LoginRecord(json: $0) }
        authLog = v.objects("auth_log").map { AuthLogEntry(json: $0) }
    }

    public init(from decoder: Decoder) throws {
        self.init(json: try JSONValue.decodeObject(from: decoder))
    }
}

/// A phone with the app.
public struct AppAccess: Decodable, Equatable, Sendable {
    /// 16 hex.
    public var id: String
    public var name: String
    /// «iPhone15,2».
    public var model: String
    /// «iOS 26.0», «18.1» (old clients) or "".
    public var os: String
    public var app: String
    public var created: Int
    public var seen: Int
    public var lastIP: String
    public var expires: Int
    public var hardExpires: Int
    /// This phone.
    public var current: Bool

    public init(json v: JSONValue) {
        id = v.str("id") ?? ""
        name = v.str("name") ?? ""
        model = v.str("model") ?? ""
        os = v.str("os") ?? ""
        app = v.str("app") ?? ""
        created = v.num("created") ?? 0
        seen = v.num("seen") ?? 0
        lastIP = v.str("last_ip") ?? ""
        expires = v.num("expires") ?? 0
        hardExpires = v.num("hard_expires") ?? 0
        current = v.flag("current") ?? false
    }

    public init(from decoder: Decoder) throws {
        self.init(json: try JSONValue.decodeObject(from: decoder))
    }
}

/// A web panel session.
public struct WebSession: Decodable, Equatable, Sendable {
    /// 16 hex (first 16 of the session hash).
    public var ref: String
    public var created: Int
    public var seen: Int
    public var ip: String
    /// User agent, ≤200.
    public var ua: String
    /// Always false for the app.
    public var current: Bool

    public init(json v: JSONValue) {
        ref = v.str("ref") ?? ""
        created = v.num("created") ?? 0
        seen = v.num("seen") ?? 0
        ip = v.str("ip") ?? ""
        ua = v.str("ua") ?? ""
        current = v.flag("current") ?? false
    }

    public init(from decoder: Decoder) throws {
        self.init(json: try JSONValue.decodeObject(from: decoder))
    }
}

/// An app login attempt.
public struct LoginRecord: Decodable, Equatable, Sendable {
    public var ts: Int
    public var name: String
    public var ip: String
    /// "pending", "approved", "issued", "expired", "denied", "notme", "cancelled".
    public var result: String

    public init(json v: JSONValue) {
        ts = v.num("ts") ?? 0
        name = v.str("name") ?? ""
        ip = v.str("ip") ?? ""
        result = v.str("result") ?? ""
    }

    public init(from decoder: Decoder) throws {
        self.init(json: try JSONValue.decodeObject(from: decoder))
    }
}

/// A line of the login journal (`ts` is correct Unix time).
public struct AuthLogEntry: Decodable, Equatable, Sendable {
    public var ts: Int
    /// `OK`, `FAIL`, `LOCKED`, `CODE`, `APP_OK`, … (`[A-Z_]{1,20}`).
    public var what: String
    public var ip: String

    public init(json v: JSONValue) {
        ts = v.num("ts") ?? 0
        what = v.str("what") ?? ""
        ip = v.str("ip") ?? ""
    }

    public init(from decoder: Decoder) throws {
        self.init(json: try JSONValue.decodeObject(from: decoder))
    }
}

// MARK: - Action results (200 bodies)

/// `pingone` 200: `{"id","ms","ts"}`; `ms` 0 = no answer.
public struct PingOneResult: Decodable, Equatable, Sendable {
    public var id: String
    public var ms: Int
    public var ts: Int

    public init(json v: JSONValue) {
        id = v.str("id") ?? ""
        ms = v.num("ms") ?? 0
        ts = v.num("ts") ?? 0
    }

    public init(from decoder: Decoder) throws {
        self.init(json: try JSONValue.decodeObject(from: decoder))
    }
}

/// A generic `{"ok":true, …}` action body: `same` (diradd/dirdel: nothing changed, PassWall not restarted),
/// `blocked` (block/unblock), `direct` (direct), `revoked` (revoke-all count, this phone included).
public struct ActionOK: Decodable, Equatable, Sendable {
    public var ok: Bool
    public var same: Bool
    public var mac: String?
    public var blocked: Bool?
    public var direct: Bool?
    public var revoked: Int?

    public init(json v: JSONValue) {
        ok = v.flag("ok") ?? false
        same = v.flag("same") ?? false
        mac = v.str("mac")
        blocked = v.flag("blocked")
        direct = v.flag("direct")
        revoked = v.num("revoked")
    }

    public init(from decoder: Decoder) throws {
        self.init(json: try JSONValue.decodeObject(from: decoder))
    }
}

/// `rename` 200: `{"ok":true,"names":{mac:name}}` — the whole names map (keys lowercased).
public struct RenameResult: Decodable, Equatable, Sendable {
    public var ok: Bool
    public var names: [String: String]

    public init(json v: JSONValue) {
        ok = v.flag("ok") ?? false
        var n: [String: String] = [:]
        if let o = v["names"]?.objectValue {
            for (key, value) in o {
                if let s = value.stringValue {
                    n[key.lowercased()] = s
                }
            }
        }
        names = n
    }

    public init(from decoder: Decoder) throws {
        self.init(json: try JSONValue.decodeObject(from: decoder))
    }
}

// MARK: - /data helpers

extension DataPoint {
    /// A week/month bucket `[mid, value, fails, off]` (day points have only `[ts, ms]`).
    public var isBucket: Bool {
        return fails != nil
    }
}

extension DataRange {
    /// Window length, seconds: 86 400 / 604 800 / 2 592 000.
    public var span: Int {
        switch self {
        case .day:
            return 86400
        case .week:
            return 7 * 86400
        case .month:
            return 30 * 86400
        }
    }

    /// Bucket width of `points`: 0 (day, raw minutes) / 1800 / 7200.
    public var step: Int {
        switch self {
        case .day:
            return 0
        case .week:
            return 1800
        case .month:
            return 7200
        }
    }

    /// Segmented control label: «24 ч», «7 дн», «30 дн».
    public var shortLabel: String {
        switch self {
        case .day:
            return "24" + Fmt.nbsp + "ч"
        case .week:
            return "7" + Fmt.nbsp + "дн"
        case .month:
            return "30" + Fmt.nbsp + "дн"
        }
    }

    /// «24 часа», «7 дней», «30 дней» (titles «Связь за 7 дней»).
    public var title: String {
        switch self {
        case .day:
            return "24" + Fmt.nbsp + "часа"
        case .week:
            return "7" + Fmt.nbsp + "дней"
        case .month:
            return "30" + Fmt.nbsp + "дней"
        }
    }
}

extension DataResponse {
    /// `range` as a `DataRange` (`day` when unknown).
    public var dataRange: DataRange {
        return DataRange(rawValue: range) ?? .day
    }

    /// The same response with the names map replaced (after `rename`; contract-stage4 §3.2).
    public func replacingNames(_ newNames: [String: String]) -> DataResponse {
        var copy = self
        var n: [String: String] = [:]
        for (k, v) in newNames {
            n[k.lowercased()] = v
        }
        copy.names = n
        return copy
    }
}
