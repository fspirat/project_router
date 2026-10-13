import SwiftUI
import RouterCore

/// The server card sheet item (a node id or `"direct"`).
struct VPNServerRef: Identifiable, Hashable {
    let id: String
}

/// «VPN» tab root (contract-stage4 §5.1): mode, «Лучший сервер для …», server list (→ server card sheet),
/// switch history, connection history chart, subscriptions, router speed test, own servers (`/vds`).
///
/// The shell (TabRoot) gives the NavigationStack, the large title, the gear, the status pill, toasts and the
/// 428 confirm sheets. Dangerous actions start only from buttons (never swipes or pull-to-refresh) and always
/// go through the store's confirm flow.
struct VPNView: View {
    @Environment(RouterStore.self) private var store
    /// The chart range (also the range of the switch history and of «Все в журнале»). UI state, per scene.
    @SceneStorage("vpn.range") private var range: DataRange = .day
    @State private var openedServer: VPNServerRef? = nil
    /// «Выбери сервер ниже…» after tapping «Через VPN» while direct.
    @State private var showsChooseHint = false

    /// Scroll target of the server list.
    static let serversAnchor = "vpn.servers"

    var body: some View {
        let kinds = RouterStore.vpnKinds(range: range)
        ScrollViewReader { proxy in
            TimelineView(.periodic(from: Date(), by: 30)) { context in
                ScreenScroll(refresh: kinds) {
                    VPNContent(
                        now: context.date.timeIntervalSince1970,
                        range: $range,
                        showsChooseHint: showsChooseHint,
                        openServer: { id in
                            openedServer = VPNServerRef(id: id)
                        },
                        chooseServer: {
                            showsChooseHint = true
                            withAnimation(.easeInOut(duration: 0.35)) {
                                proxy.scrollTo(VPNView.serversAnchor, anchor: .top)
                            }
                        }
                    )
                }
            }
        }
        .pollingScope(kinds)
        .appSheet(item: $openedServer) { ref in
            VPNServerSheet(serverID: ref.id)
        }
        .onChange(of: store.status?.current) { _, current in
            if current != "_direct" {
                showsChooseHint = false
            }
        }
    }
}

/// The cards, top to bottom in the order of contract-stage4 §5.1.
struct VPNContent: View {
    @Environment(RouterStore.self) private var store
    let now: TimeInterval
    @Binding var range: DataRange
    let showsChooseHint: Bool
    let openServer: (String) -> Void
    let chooseServer: () -> Void

    var body: some View {
        let stale = store.vpnShowsStaleData
        if let status = store.status {
            if stale {
                StaleDataNote()
            }
            VPNModeCard(status: status, chooseServer: chooseServer)
                .staleDimmed(stale)
            VPNBestServers(status: status)
                .staleDimmed(stale)
            VPNServersSection(status: status, now: now, showsChooseHint: showsChooseHint, openServer: openServer)
                .staleDimmed(stale)
                .id(VPNView.serversAnchor)
        } else {
            VPNNoStatusCard()
        }
        VPNSwitchHistoryCard(range: range, now: now)
        VPNConnectionCard(range: $range, now: now)
        if let status = store.status {
            VPNSubscriptionsCard(status: status, now: now)
                .staleDimmed(stale)
            VPNSpeedTestCard(status: status, now: now)
                .staleDimmed(stale)
        }
        VPNSpeedHistoryCard(now: now)
        VPNOwnServersCard(now: now)
    }
}

/// No `/status` yet: loading, offline at cold start, app disabled, or an error (contract-stage4 §4.3).
struct VPNNoStatusCard: View {
    @Environment(RouterStore.self) private var store

    var body: some View {
        Card {
            if store.appDisabled {
                EmptyStateView(title: AppTexts.appDisabledTitle, systemImage: "power.circle")
            } else if store.offline {
                EmptyStateView(title: VPNTexts.noStatus, systemImage: "wifi.slash")
            } else if !store.firstLoadFinished {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Загружаю данные роутера…")
                        .font(.subheadline)
                        .foregroundStyle(Theme.dim)
                }
                .frame(minHeight: 44)
                .accessibilityElement(children: .combine)
            } else {
                EmptyStateView(
                    title: store.statusError ?? "Нет данных роутера.",
                    systemImage: "exclamationmark.triangle",
                    text: "Потяни экран вниз, чтобы обновить."
                )
            }
        }
    }
}
