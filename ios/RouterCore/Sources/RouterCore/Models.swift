import Foundation

// All models are built from a `JSONValue` with lenient field access:
// a missing, `null` or wrongly typed field falls back to a default,
// a bad element of a list is skipped, and the whole document still decodes.
// Each model can be decoded with `JSONDecoder` (top level must be a JSON object)
// or built with `init(json:)` from an already parsed value.

// MARK: - /status

/// `GET /status` (router CGI `status`), contract §2.6.
public struct RouterStatus: Decodable, Equatable, Sendable {
    /// Any xray process is running.
    public var running: Bool
    /// PassWall global node is Split. `false` → MyDirect does not work.
    public var splitActive: Bool
    /// Node id, `"_direct"` (no VPN) or `""` (Split not found).
    public var current: String
    /// `nil` after a reboot until the first fspirat-ping.
    public var ping: PingInfo?
    /// Router log lines, not used in stage 3.
    public var log: [String]
    /// `[ts, ms]` points; `[]` after a reboot. Fallback for the mini chart.
    public var history: [DataPoint]
    /// Service latency via the current server; `nil` after a reboot.
    public var targets: Targets?
    /// The subscription that expires first; `nil` if unknown.
    public var sub: SubscriptionInfo?
    /// `[]` = no subscriptions; `nil` = the router failed to read them.
    public var subs: [SubscriptionItem]?
    public var svcDirect: [String]
    /// `"kind|name|addr"` strings.
    public var targetList: [String]
    /// Key = node id or `"direct"`.
    public var svc: [String: Targets]
    public var svcRunning: Bool
    public var speed: SpeedPair
    public var devices: [RouterDevice]
    public var sys: SystemInfo

    public init(json v: JSONValue) {
        running = v.flag("running") ?? false
        splitActive = v.flag("split_active") ?? false
        current = v.str("current") ?? ""
        if let p = v.obj("ping") {
            ping = PingInfo(json: p)
        } else {
            ping = nil
        }
        log = v.strings("log")
        history = v.list("history").compactMap { DataPoint(json: $0) }
        if let t = v.obj("targets") {
            targets = Targets(json: t)
        } else {
            targets = nil
        }
        if let s = v.obj("sub") {
            sub = SubscriptionInfo(json: s)
        } else {
            sub = nil
        }
        if let arr = v["subs"]?.arrayValue {
            subs = arr.filter { $0.isObject }.map { SubscriptionItem(json: $0) }
        } else {
            subs = nil
        }
        svcDirect = v.strings("svc_direct")
        targetList = v.strings("target_list")
        var svcMap: [String: Targets] = [:]
        if let o = v["svc"]?.objectValue {
            for (key, value) in o where value.isObject {
                svcMap[key] = Targets(json: value)
            }
        }
        svc = svcMap
        svcRunning = v.flag("svc_running") ?? false
        speed = SpeedPair(json: v.obj("speed") ?? .object([:]))
        devices = v.objects("devices").map { RouterDevice(json: $0) }
        sys = SystemInfo(json: v.obj("sys") ?? .object([:]))
    }

    public init(from decoder: Decoder) throws {
        self.init(json: try JSONValue.decodeObject(from: decoder))
    }
}

/// `status.ping`.
public struct PingInfo: Decodable, Equatable, Sendable {
    /// When fspirat-ping finished (unix seconds).
    public var updated: Int?
    /// The node that was current during that check (may differ from `status.current`).
    public var current: String
    /// `false` = SOCKS 127.0.0.1:1070 unreachable. `nil` when the key is absent.
    public var socks: Bool?
    /// VPN check: ms > 0 passed; 0 FAILED; `nil` only when `socks == false`.
    public var real: Int?
    public var nodes: [PingNode]

    public init(json v: JSONValue) {
        updated = v.num("updated")
        current = v.str("current") ?? ""
        socks = v.flag("socks")
        real = v.num("real")
        nodes = v.objects("nodes").map { PingNode(json: $0) }
    }

    public init(from decoder: Decoder) throws {
        self.init(json: try JSONValue.decodeObject(from: decoder))
    }
}

/// One server in `ping.nodes`.
public struct PingNode: Decodable, Equatable, Sendable {
    public var id: String
    /// Trimmed; may start with a flag emoji.
    public var name: String
    /// 0 = no answer.
    public var ms: Int
    public var group: String
    /// Own server (group "fspirat").
    public var own: Bool

    public init(json v: JSONValue) {
        id = v.str("id") ?? ""
        name = (v.str("name") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        ms = v.num("ms") ?? 0
        group = v.str("group") ?? ""
        own = v.flag("own") ?? false
    }

    public init(from decoder: Decoder) throws {
        self.init(json: try JSONValue.decodeObject(from: decoder))
    }
}

/// Service latency results (`status.targets`, `status.svc[...]`).
public struct Targets: Decodable, Equatable, Sendable {
    public var ts: Int?
    /// Only in `svc.direct`: TCP to ya.ru, ms; 0 = no answer.
    public var base: Int?
    public var list: [TargetResult]

    public init(json v: JSONValue) {
        ts = v.num("ts")
        base = v.num("base")
        list = v.objects("list").map { TargetResult(json: $0) }
    }

    public init(from decoder: Decoder) throws {
        self.init(json: try JSONValue.decodeObject(from: decoder))
    }
}

public struct TargetResult: Decodable, Equatable, Sendable {
    /// "web" or "mc".
    public var kind: String
    public var name: String
    public var host: String
    /// ms; 0 = no answer; `nil` when missing.
    public var vpn: Int?

    public init(json v: JSONValue) {
        kind = v.str("kind") ?? "web"
        name = v.str("name") ?? ""
        host = v.str("host") ?? ""
        vpn = v.num("vpn")
    }

    public init(from decoder: Decoder) throws {
        self.init(json: try JSONValue.decodeObject(from: decoder))
    }
}

/// `status.sub`. Sizes are bytes; `total == 0` = no limit; `expire == 0` = no expiry.
public struct SubscriptionInfo: Decodable, Equatable, Sendable {
    public var ts: Int?
    public var up: Int
    public var down: Int
    public var total: Int
    public var expire: Int
    public var title: String

    public init(json v: JSONValue) {
        ts = v.num("ts")
        up = v.num("up") ?? 0
        down = v.num("down") ?? 0
        total = v.num("total") ?? 0
        expire = v.num("expire") ?? 0
        title = v.str("title") ?? ""
    }

    public init(from decoder: Decoder) throws {
        self.init(json: try JSONValue.decodeObject(from: decoder))
    }
}

/// One element of `status.subs`. Numeric keys are absent after a reboot.
public struct SubscriptionItem: Decodable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var host: String
    public var hwid: Bool
    public var nodes: Int
    public var ts: Int?
    public var up: Int?
    public var down: Int?
    public var total: Int?
    public var expire: Int?

    public init(json v: JSONValue) {
        id = v.str("id") ?? ""
        name = v.str("name") ?? ""
        host = v.str("host") ?? ""
        hwid = v.flag("hwid") ?? false
        nodes = v.num("nodes") ?? 0
        ts = v.num("ts")
        up = v.num("up")
        down = v.num("down")
        total = v.num("total")
        expire = v.num("expire")
    }

    public init(from decoder: Decoder) throws {
        self.init(json: try JSONValue.decodeObject(from: decoder))
    }
}

/// `status.speed`.
public struct SpeedPair: Decodable, Equatable, Sendable {
    public var vpn: SpeedResult?
    public var direct: SpeedResult?

    public init(json v: JSONValue) {
        if let x = v.obj("vpn") {
            vpn = SpeedResult(json: x)
        } else {
            vpn = nil
        }
        if let x = v.obj("direct") {
            direct = SpeedResult(json: x)
        } else {
            direct = nil
        }
    }

    public init(from decoder: Decoder) throws {
        self.init(json: try JSONValue.decodeObject(from: decoder))
    }
}

/// A speed test result. `down`/`up` are bits per second.
public struct SpeedResult: Decodable, Equatable, Sendable {
    public var via: String
    public var ts: Int
    public var down: Int
    public var up: Int
    public var latency: Int
    public var ip: String
    public var country: String
    public var server: String
    public var streams: Int
    public var upLimited: Bool

    public init(json v: JSONValue) {
        via = v.str("via") ?? ""
        ts = v.num("ts") ?? 0
        down = v.num("down") ?? 0
        up = v.num("up") ?? 0
        latency = v.num("latency") ?? 0
        ip = v.str("ip") ?? ""
        country = v.str("country") ?? ""
        server = v.str("server") ?? ""
        streams = v.num("streams") ?? 0
        upLimited = v.flag("up_limited") ?? false
    }

    public init(from decoder: Decoder) throws {
        self.init(json: try JSONValue.decodeObject(from: decoder))
    }
}

/// One element of `status.devices`.
public struct RouterDevice: Decodable, Equatable, Sendable {
    /// DHCP name, may be "".
    public var name: String
    public var ip: String
    /// Lowercased.
    public var mac: String
    public var online: Bool
    /// "2g", "5g", "6g", "wired"; `nil` when offline or unknown.
    public var band: String?
    /// dBm (negative); 0 = unknown.
    public var signal: Int?
    /// Mbit/s.
    public var rate: Int?
    /// Bytes since the router's counter table was created; reset by reboot.
    public var up: Int
    public var dn: Int
    public var blocked: Bool
    public var sblocked: Bool
    public var direct: Bool
    /// "HHMM-HHMM".
    public var sched: String?

    public init(json v: JSONValue) {
        name = v.str("name") ?? ""
        ip = v.str("ip") ?? ""
        mac = (v.str("mac") ?? "").lowercased()
        online = v.flag("online") ?? false
        band = v.str("band")
        signal = v.num("signal")
        rate = v.num("rate")
        up = v.num("up") ?? 0
        dn = v.num("dn") ?? 0
        blocked = v.flag("blocked") ?? false
        sblocked = v.flag("sblocked") ?? false
        direct = v.flag("direct") ?? false
        sched = v.str("sched")
    }

    public init(from decoder: Decoder) throws {
        self.init(json: try JSONValue.decodeObject(from: decoder))
    }

    /// Locally administered ("hidden", randomized) MAC.
    public var isRandomizedMAC: Bool {
        return Validation.isRandomizedMAC(mac)
    }
}

/// `status.sys`. Memory and disk sizes are KiB.
public struct SystemInfo: Decodable, Equatable, Sendable {
    public var cpu: Int
    public var cores: Int
    /// A string like "0.21 0.17 0.15".
    public var load: String
    public var memTotal: Int
    public var memAvail: Int
    public var diskTotal: Int
    public var diskUsed: Int
    public var tmpTotal: Int
    public var tmpUsed: Int
    /// °C; `nil` = no sensor.
    public var temp: Int?
    /// Seconds.
    public var uptime: Int
    public var model: String
    public var fw: String
    /// KiB.
    public var xrayRSS: Int
    public var net: NetStats

    public init(json v: JSONValue) {
        cpu = v.num("cpu") ?? 0
        cores = v.num("cores") ?? 0
        load = v.str("load") ?? ""
        memTotal = v.num("mem_total") ?? 0
        memAvail = v.num("mem_avail") ?? 0
        diskTotal = v.num("disk_total") ?? 0
        diskUsed = v.num("disk_used") ?? 0
        tmpTotal = v.num("tmp_total") ?? 0
        tmpUsed = v.num("tmp_used") ?? 0
        temp = v.num("temp")
        uptime = v.num("uptime") ?? 0
        model = v.str("model") ?? ""
        fw = v.str("fw") ?? ""
        xrayRSS = v.num("xray_rss") ?? 0
        net = NetStats(json: v.obj("net") ?? .object([:]))
    }

    public init(from decoder: Decoder) throws {
        self.init(json: try JSONValue.decodeObject(from: decoder))
    }
}

/// `GET /net` and `status.sys.net`. `rx`/`tx` are bits/s; `*Total` are bytes since boot.
public struct NetStats: Decodable, Equatable, Sendable {
    public var dev: String
    public var rx: Int
    public var tx: Int
    public var rxTotal: Int
    public var txTotal: Int

    public init(json v: JSONValue) {
        dev = v.str("dev") ?? ""
        rx = v.num("rx") ?? 0
        tx = v.num("tx") ?? 0
        rxTotal = v.num("rx_total") ?? 0
        txTotal = v.num("tx_total") ?? 0
    }

    public init(from decoder: Decoder) throws {
        self.init(json: try JSONValue.decodeObject(from: decoder))
    }
}

// MARK: - /led

/// `GET /led` and the `ledset` result.
public struct LedState: Decodable, Equatable, Sendable {
    /// The router has no LED script (`{"absent":true}`), or the body has no `on`.
    public var absent: Bool
    public var on: Bool
    public var items: [LedItem]

    /// Show the LED control only when this is true.
    public var isAvailable: Bool {
        return !absent
    }

    public init(json v: JSONValue) {
        let onValue = v.flag("on")
        absent = (v.flag("absent") ?? false) || onValue == nil
        on = onValue ?? false
        items = v.objects("items").map { LedItem(json: $0) }
    }

    public init(from decoder: Decoder) throws {
        self.init(json: try JSONValue.decodeObject(from: decoder))
    }
}

public struct LedItem: Decodable, Equatable, Sendable {
    public var name: String
    public var on: Bool

    public init(json v: JSONValue) {
        name = v.str("name") ?? ""
        on = v.flag("on") ?? false
    }

    public init(from decoder: Decoder) throws {
        self.init(json: try JSONValue.decodeObject(from: decoder))
    }
}

// MARK: - /data

public enum DataRange: String, CaseIterable, Sendable {
    case day
    case week
    case month
}

/// A chart point: day `[ts, ms]`; week/month `[mid_ts, avg|0|-1, fails, offline]`.
/// `ms > 0` ok; `0` VPN check failed; `-1` router offline.
public struct DataPoint: Decodable, Equatable, Sendable {
    public var ts: Int
    public var ms: Int
    public var fails: Int?
    public var offline: Int?

    public init(ts: Int, ms: Int, fails: Int? = nil, offline: Int? = nil) {
        self.ts = ts
        self.ms = ms
        self.fails = fails
        self.offline = offline
    }

    /// `nil` unless the value is an array with at least two numbers.
    public init?(json v: JSONValue) {
        guard let a = v.arrayValue, a.count >= 2, let t = a[0].intValue, let m = a[1].intValue else {
            return nil
        }
        ts = t
        ms = m
        fails = a.count > 2 ? a[2].intValue : nil
        offline = a.count > 3 ? a[3].intValue : nil
    }

    public init(from decoder: Decoder) throws {
        let v = try JSONValue(from: decoder)
        guard let p = DataPoint(json: v) else {
            throw JSONValue.shapeError(decoder, "point")
        }
        self = p
    }
}

/// A journal event `[ts, kind, text]`.
public struct DataEvent: Decodable, Equatable, Sendable {
    public var ts: Int
    public var kind: String
    public var text: String

    public init(ts: Int, kind: String, text: String) {
        self.ts = ts
        self.kind = kind
        self.text = text
    }

    public init?(json v: JSONValue) {
        guard let a = v.arrayValue, a.count >= 3, let t = a[0].intValue else {
            return nil
        }
        ts = t
        kind = a[1].stringValue ?? ""
        text = a[2].stringValue ?? ""
    }

    public init(from decoder: Decoder) throws {
        let v = try JSONValue(from: decoder)
        guard let e = DataEvent(json: v) else {
            throw JSONValue.shapeError(decoder, "event")
        }
        self = e
    }

    /// Level from `app.js` `LEVEL`: err / warn / ok, anything else info.
    public var level: Tone {
        return Summary.eventLevel(kind: kind)
    }
}

public struct DataStats: Decodable, Equatable, Sendable {
    public var avg: Int?
    public var min: Int?
    public var max: Int?
    public var fails: Int
    public var offlineMin: Int

    public init(json v: JSONValue) {
        avg = v.num("avg")
        min = v.num("min")
        max = v.num("max")
        fails = v.num("fails") ?? 0
        offlineMin = v.num("offline_min") ?? 0
    }

    public init(from decoder: Decoder) throws {
        self.init(json: try JSONValue.decodeObject(from: decoder))
    }
}

/// `traffic[mac]`: bytes today (`d`) and this month (`m`), each `[up, down]`. Day = Europe/Samara.
public struct TrafficEntry: Decodable, Equatable, Sendable {
    public var dayUp: Int
    public var dayDown: Int
    public var monthUp: Int
    public var monthDown: Int

    public init(dayUp: Int, dayDown: Int, monthUp: Int, monthDown: Int) {
        self.dayUp = dayUp
        self.dayDown = dayDown
        self.monthUp = monthUp
        self.monthDown = monthDown
    }

    public init(json v: JSONValue) {
        let d = v.list("d")
        let m = v.list("m")
        dayUp = d.count > 0 ? (d[0].intValue ?? 0) : 0
        dayDown = d.count > 1 ? (d[1].intValue ?? 0) : 0
        monthUp = m.count > 0 ? (m[0].intValue ?? 0) : 0
        monthDown = m.count > 1 ? (m[1].intValue ?? 0) : 0
    }

    public init(from decoder: Decoder) throws {
        self.init(json: try JSONValue.decodeObject(from: decoder))
    }
}

/// `data.speed` row `[ts, via, down_bps, up_bps, latency_ms]`.
public struct SpeedHistoryEntry: Decodable, Equatable, Sendable {
    public var ts: Int
    public var via: String
    public var down: Int
    public var up: Int
    public var latency: Int

    public init?(json v: JSONValue) {
        guard let a = v.arrayValue, a.count >= 5, let t = a[0].intValue else {
            return nil
        }
        ts = t
        via = a[1].stringValue ?? ""
        down = a[2].intValue ?? 0
        up = a[3].intValue ?? 0
        latency = a[4].intValue ?? 0
    }

    public init(from decoder: Decoder) throws {
        let v = try JSONValue(from: decoder)
        guard let e = SpeedHistoryEntry(json: v) else {
            throw JSONValue.shapeError(decoder, "speed row")
        }
        self = e
    }
}

/// `data.site`. Strings may be "".
public struct SiteInfo: Decodable, Equatable, Sendable {
    public var luci: String
    public var bot: String
    public var mtg: String
    public var panels: [String]

    public init(json v: JSONValue) {
        luci = v.str("luci") ?? ""
        bot = v.str("bot") ?? ""
        mtg = v.str("mtg") ?? ""
        panels = v.strings("panels")
    }

    public init(from decoder: Decoder) throws {
        self.init(json: try JSONValue.decodeObject(from: decoder))
    }
}

/// `data.newdevs` element.
public struct NewDevice: Decodable, Equatable, Sendable {
    public var ts: Int
    /// Lowercased.
    public var mac: String

    public init(json v: JSONValue) {
        ts = v.num("ts") ?? 0
        mac = (v.str("mac") ?? "").lowercased()
    }

    public init(from decoder: Decoder) throws {
        self.init(json: try JSONValue.decodeObject(from: decoder))
    }
}

/// `GET /data?range=…` (built by the server; works while the router is offline).
public struct DataResponse: Decodable, Equatable, Sendable {
    public var now: Int
    public var range: String
    public var step: Int
    public var points: [DataPoint]
    public var stats: DataStats
    /// Newest first.
    public var events: [DataEvent]
    public var offlineSince: Int?
    public var lastOK: Int?
    /// Own device names, keys lowercased MACs.
    public var names: [String: String]
    /// Service name → `[ts, ms]` points.
    public var tpoints: [String: [DataPoint]]
    /// Keys lowercased MACs.
    public var traffic: [String: TrafficEntry]
    public var speed: [SpeedHistoryEntry]
    public var site: SiteInfo
    public var newdevs: [NewDevice]

    public init(json v: JSONValue) {
        now = v.num("now") ?? 0
        range = v.str("range") ?? "day"
        step = v.num("step") ?? 0
        points = v.list("points").compactMap { DataPoint(json: $0) }
        stats = DataStats(json: v.obj("stats") ?? .object([:]))
        events = v.list("events").compactMap { DataEvent(json: $0) }
        offlineSince = v.num("offline_since")
        lastOK = v.num("last_ok")
        var n: [String: String] = [:]
        if let o = v["names"]?.objectValue {
            for (key, value) in o {
                if let s = value.stringValue {
                    n[key.lowercased()] = s
                }
            }
        }
        names = n
        var tp: [String: [DataPoint]] = [:]
        if let o = v["tpoints"]?.objectValue {
            for (key, value) in o {
                if let arr = value.arrayValue {
                    tp[key] = arr.compactMap { DataPoint(json: $0) }
                }
            }
        }
        tpoints = tp
        var tr: [String: TrafficEntry] = [:]
        if let o = v["traffic"]?.objectValue {
            for (key, value) in o where value.isObject {
                tr[key.lowercased()] = TrafficEntry(json: value)
            }
        }
        traffic = tr
        speed = v.list("speed").compactMap { SpeedHistoryEntry(json: $0) }
        site = SiteInfo(json: v.obj("site") ?? .object([:]))
        newdevs = v.objects("newdevs").map { NewDevice(json: $0) }
    }

    public init(from decoder: Decoder) throws {
        self.init(json: try JSONValue.decodeObject(from: decoder))
    }
}

// MARK: - /me

/// `GET /me`.
public struct MeResponse: Decodable, Equatable, Sendable {
    public var device: MeDevice
    /// Server clock (unix seconds).
    public var now: Int

    public init(json v: JSONValue) {
        device = MeDevice(json: v.obj("device") ?? .object([:]))
        now = v.num("now") ?? 0
    }

    public init(from decoder: Decoder) throws {
        self.init(json: try JSONValue.decodeObject(from: decoder))
    }
}

public struct MeDevice: Decodable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var created: Int
    /// Slides: 90 days from the last request, capped at `hardExpires`.
    public var expires: Int
    /// Login + 365 days.
    public var hardExpires: Int

    public init(json v: JSONValue) {
        id = v.str("id") ?? ""
        name = v.str("name") ?? ""
        created = v.num("created") ?? 0
        expires = v.num("expires") ?? 0
        hardExpires = v.num("hard_expires") ?? 0
    }

    public init(from decoder: Decoder) throws {
        self.init(json: try JSONValue.decodeObject(from: decoder))
    }
}

// MARK: - /auth

/// `POST /auth/login` 200 body.
public struct LoginChallenge: Decodable, Equatable, Sendable {
    /// 64 lowercase hex. Secret: memory only, never log it.
    public var loginID: String
    /// 10–99, show it big.
    public var number: Int
    public var expiresIn: Int
    public var pollEvery: Int

    public init(loginID: String, number: Int, expiresIn: Int, pollEvery: Int) {
        self.loginID = loginID
        self.number = number
        self.expiresIn = expiresIn
        self.pollEvery = pollEvery
    }

    public init(from decoder: Decoder) throws {
        let v = try JSONValue.decodeObject(from: decoder)
        guard let id = v.str("login_id"), Validation.isValidLoginID(id), let n = v.num("number") else {
            throw JSONValue.shapeError(decoder, "login")
        }
        loginID = id
        number = n
        expiresIn = v.num("expires_in") ?? 120
        pollEvery = v.num("poll_every") ?? 2
    }
}

/// Issued token. The token is a secret: Keychain only.
public struct ApprovedLogin: Equatable, Sendable {
    public var token: String
    public var deviceID: String
    public var expires: Int
    public var hardExpires: Int

    public init(token: String, deviceID: String, expires: Int, hardExpires: Int) {
        self.token = token
        self.deviceID = deviceID
        self.expires = expires
        self.hardExpires = hardExpires
    }
}

/// `POST /auth/poll` 200 body.
public enum PollResult: Decodable, Equatable, Sendable {
    /// `expiresIn` = seconds left on the server.
    case pending(expiresIn: Int?)
    case approved(ApprovedLogin)

    public init(from decoder: Decoder) throws {
        let v = try JSONValue.decodeObject(from: decoder)
        let state = v.str("state") ?? ""
        if state == "pending" {
            self = .pending(expiresIn: v.num("expires_in"))
            return
        }
        if state == "approved" {
            guard let token = v.str("token"), Validation.isValidToken(token) else {
                throw JSONValue.shapeError(decoder, "approved without a valid token")
            }
            self = .approved(ApprovedLogin(
                token: token,
                deviceID: v.str("device_id") ?? "",
                expires: v.num("expires") ?? 0,
                hardExpires: v.num("hard_expires") ?? 0
            ))
            return
        }
        throw JSONValue.shapeError(decoder, "poll state")
    }
}

/// `POST /auth/cancel` 200 body. Always means "login closed".
public struct CancelResult: Decodable, Equatable, Sendable {
    public var ok: Bool
    /// "cancelled", "issued", "expired", "denied", "notme".
    public var state: String

    public init(json v: JSONValue) {
        ok = v.flag("ok") ?? false
        state = v.str("state") ?? ""
    }

    public init(from decoder: Decoder) throws {
        self.init(json: try JSONValue.decodeObject(from: decoder))
    }
}
