import SwiftUI
import RouterCore

/// «Сводка» (contract §4): cards from status, net, data and LED; actions at the bottom.
/// Polling runs only while this screen is visible, the app is active and not locked.
struct SummaryView: View {
    @Environment(RouterStore.self) var store
    @Environment(AppLock.self) var lock
    @Environment(\.scenePhase) var scenePhase
    @AppStorage(AppSettings.themeKey) var theme: ThemeChoice = .system

    private var pollingEnabled: Bool {
        return scenePhase == .active && !lock.isLocked
    }

    var body: some View {
        @Bindable var bindableStore = store
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    SummaryContent()
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .background {
                Theme.bg.ignoresSafeArea()
            }
            .refreshable { [store] in
                await store.refreshAll()
            }
            .navigationTitle("Сводка")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.isSettingsPresented = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Настройки")
                }
            }
        }
        .overlay(alignment: .bottom) {
            ToastOverlay()
        }
        .sheet(isPresented: $bindableStore.isSettingsPresented) {
            SettingsView()
                .sheetChrome(store: store, lock: lock, theme: theme)
        }
        .sheet(item: $bindableStore.pendingConfirm) { pending in
            ConfirmSheet(pending: pending)
                .sheetChrome(store: store, lock: lock, theme: theme)
        }
        .confirmationDialog(PingPreDialog.title, isPresented: $bindableStore.showPingPreDialog, titleVisibility: .visible) {
            Button(PingPreDialog.confirm) {
                store.startPing()
            }
            Button(PingPreDialog.cancel, role: .cancel) {}
        } message: {
            Text(PingPreDialog.text)
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

/// The cards, in the order of the owner's plan §2.
struct SummaryContent: View {
    @Environment(RouterStore.self) var store

    var body: some View {
        let now = Date().timeIntervalSince1970
        if store.appDisabled {
            AppDisabledCard()
        } else {
            let verdict = Summary.verdict(
                status: store.status,
                isOffline: store.offline,
                firstLoadFinished: store.firstLoadFinished,
                now: now
            )
            VerdictCard(verdict: verdict)
            NoticeBanners(now: now)
            if store.offline {
                OfflineCard(now: now)
            }
            if let status = store.status, !store.offline, verdict.showsCurrentServer {
                ServerCard(status: status, now: now)
                ServicesCard(status: status)
            }
            InternetCard()
            if let status = store.status, !store.offline {
                RouterCard(status: status)
                SubscriptionCard(status: status, now: now)
            }
            HistoryChartCard(now: now)
            EventsCard(now: now)
            if let status = store.status, !store.offline {
                DevicesCard(status: status)
            }
            ActionsCard()
        }
    }
}
