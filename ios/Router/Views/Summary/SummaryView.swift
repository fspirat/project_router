import SwiftUI
import RouterCore

/// «Сводка» (contract §4, contract-stage4 §9): cards from status, net, data and LED; actions at the bottom.
/// The tab shell (TabRoot) gives the navigation stack, title, gear, toasts and confirm sheets.
struct SummaryView: View {
    @Environment(RouterStore.self) var store

    var body: some View {
        // The «Проверить?» pre-dialog is shown by the presentation host (PresentationHost.swift).
        ScreenScroll(refresh: SummaryKinds.all) {
            SummaryContent()
        }
        .pollingScope(SummaryKinds.all)
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
