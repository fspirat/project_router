import SwiftUI
import RouterCore

/// The logged-in shell (contract-stage4 §1): five tabs, each with its own NavigationStack, the Settings gear,
/// toasts and confirm sheets, polling and haptics.
///
/// Classic `TabView` + `.tabItem` + `.tag` (the `Tab` struct is iOS 18+, the target is iOS 17). Built with the
/// iOS 26 SDK it gets the floating Liquid Glass tab bar by itself; no tab bar background is painted and
/// `tabBarMinimizeBehavior` is not used (5 tabs; HIG: keep the tab bar visible).
struct MainTabView: View {
    @Environment(RouterStore.self) var store
    @Environment(AppLock.self) var lock
    @Environment(\.scenePhase) var scenePhase
    /// Per-scene UI state (not router data): restored when iOS relaunches a discarded scene.
    @SceneStorage("tab") private var storedTab: AppTab = .summary

    /// Polling only while the app is active and unlocked (never in the background or under the lock).
    private var pollingEnabled: Bool {
        return scenePhase == .active && !lock.isLocked && store.isLoggedIn
    }

    var body: some View {
        @Bindable var bindableStore = store
        TabView(selection: $bindableStore.selectedTab) {
            TabRoot(tab: .summary) {
                SummaryView()
            }
            .tabItem {
                Label(AppTab.summary.title, systemImage: AppTab.summary.symbol)
            }
            .tag(AppTab.summary)

            TabRoot(tab: .vpn) {
                VPNView()
            }
            .tabItem {
                Label(AppTab.vpn.title, systemImage: AppTab.vpn.symbol)
            }
            .tag(AppTab.vpn)

            TabRoot(tab: .devices) {
                DevicesView()
            }
            .tabItem {
                Label(AppTab.devices.title, systemImage: AppTab.devices.symbol)
            }
            .badge(store.tabBadges[.devices] ?? 0)
            .tag(AppTab.devices)

            TabRoot(tab: .bypass) {
                BypassView()
            }
            .tabItem {
                Label(AppTab.bypass.title, systemImage: AppTab.bypass.symbol)
            }
            .tag(AppTab.bypass)

            TabRoot(tab: .journal) {
                JournalView()
            }
            .tabItem {
                Label(AppTab.journal.title, systemImage: AppTab.journal.symbol)
            }
            .tag(AppTab.journal)
        }
        .tint(Theme.acc)
        .appSheet(isPresented: $bindableStore.isSettingsPresented) {
            SettingsView()
        }
        .onAppear {
            if !store.tabRestored {
                store.tabRestored = true
                store.selectedTab = storedTab
            }
        }
        .onChange(of: store.selectedTab) { _, tab in
            storedTab = tab
            // The Devices badge is kept by the store (also before the Devices tab is first opened).
            store.updateDevicesBadge()
        }
        .task(id: pollingEnabled) { [store, enabled = pollingEnabled] in
            if enabled {
                await store.runPolling()
            }
        }
        .sensoryFeedback(.success, trigger: store.successTick)
        .sensoryFeedback(.error, trigger: store.errorTick)
    }
}

/// One tab: NavigationStack with a large title, the Settings gear, the status pill (not on «Сводка»,
/// which shows full banners) and the presentation host (toast above the tab bar, 428 confirm sheets).
///
/// Screens are the stack's root content: they push details with `NavigationLink(value:)` +
/// `.navigationDestination(for:)` declared inside their own view (or `.navigationDestination(item:)`).
struct TabRoot<Content: View>: View {
    let tab: AppTab
    private let content: Content

    init(tab: AppTab, @ViewBuilder content: () -> Content) {
        self.tab = tab
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(tab.title)
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        SettingsToolbarButton()
                    }
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    if tab != .summary {
                        StatusPillBar()
                    }
                }
        }
        .presentationHost(isSheet: false)
    }
}
