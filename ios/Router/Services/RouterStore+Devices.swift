import Foundation
import RouterCore

// «Устройства» tab and the device card (contract-stage4 §5.2, §5.3): read-only views of the shared caches
// (`status.devices` + `/data` names, traffic, newdevs) and the tab badge. No stored state here — everything is
// computed from the store; per-screen UI state lives in the views.

/// Keys of the Devices screen's own (non-router) settings.
enum DevicesStorage {
    /// Unix time the user last looked at the Devices tab (contract-stage4 §5.2.4, tab badge).
    static let seenAtKey = "devicesSeenAt"
}

/// A pushed device card (`NavigationLink(value:)`).
struct DeviceRoute: Hashable {
    /// Lowercased MAC.
    let mac: String

    init(mac: String) {
        self.mac = mac.lowercased()
    }
}

extension RouterStore {
    // MARK: - Sources

    /// `status.devices` (empty before the first `/status`).
    var routerDevices: [RouterDevice] {
        return status?.devices ?? []
    }

    /// Own names from the newest `/data` of any range (keys: lowercased MACs).
    var deviceNames: [String: String] {
        return latestData?.names ?? [:]
    }

    /// Today/month traffic from the newest `/data` (keys: lowercased MACs).
    var deviceTraffic: [String: TrafficEntry] {
        return latestData?.traffic ?? [:]
    }

    /// The device for a MAC, or nil when the lease is gone (or no `/status` yet).
    func routerDevice(mac: String) -> RouterDevice? {
        let key = mac.lowercased()
        return routerDevices.first { $0.mac == key }
    }

    // MARK: - List

    /// The grouped list for the search text and the filter (RouterCore `Devices.list`).
    func deviceList(query: String, filter: DeviceFilter) -> DeviceListInfo {
        return Devices.list(routerDevices, names: deviceNames, traffic: deviceTraffic, query: query, filter: filter)
    }

    /// How many devices a filter chip would show for the current search text.
    func deviceCount(filter: DeviceFilter, query: String) -> Int {
        let names = deviceNames
        return routerDevices.filter { Devices.matches($0, filter: filter) && Devices.matches($0, query: query, names: names) }.count
    }

    /// «Новые за неделю» (newest first, one row per MAC).
    func newDevicesThisWeek(now: TimeInterval) -> [NewDeviceRow] {
        let newdevs = latestData?.newdevs ?? []
        return Devices.newThisWeek(newdevs, devices: routerDevices, names: deviceNames, now: now)
    }

    // MARK: - Card

    /// The device card for a MAC (a MAC without a lease gives only MAC, traffic and rename).
    func deviceDetail(mac: String) -> DeviceDetail {
        return Devices.detail(mac: mac, device: routerDevice(mac: mac), names: deviceNames, traffic: deviceTraffic)
    }

    /// Display name for the aftermath toasts («Интернет для «iPad» выключен.»); nil → the store uses the MAC.
    func deviceActionLabel(mac: String) -> String? {
        let key = mac.lowercased()
        var name = ""
        if let d = routerDevice(mac: key) {
            name = Devices.displayName(d, names: deviceNames)
        } else if let own = deviceNames[key] {
            name = own
        }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Tab badge (contract-stage4 §1.1, §5.2.4)

    /// New devices since the user last opened the Devices tab.
    var unseenNewDevices: Int {
        let seenAt = UserDefaults.standard.integer(forKey: DevicesStorage.seenAtKey)
        return Devices.unseenCount(latestData?.newdevs ?? [], seenAt: seenAt)
    }

    /// The Devices tab is on screen: everything in `newdevs` counts as seen, the badge goes away.
    func markDevicesSeen() {
        let now = Int(Date().timeIntervalSince1970)
        let newest = (latestData?.newdevs ?? []).map { $0.ts }.max() ?? 0
        let seenAt = max(now, newest)
        if UserDefaults.standard.integer(forKey: DevicesStorage.seenAtKey) < seenAt {
            UserDefaults.standard.set(seenAt, forKey: DevicesStorage.seenAtKey)
        }
        if (tabBadges[.devices] ?? 0) != 0 {
            tabBadges[.devices] = 0
        }
    }

    /// Recomputes the badge from the cached `newdevs` (call after a `/data` read).
    func refreshDevicesBadge() {
        let count = unseenNewDevices
        if (tabBadges[.devices] ?? 0) != count {
            tabBadges[.devices] = count
        }
    }
}
