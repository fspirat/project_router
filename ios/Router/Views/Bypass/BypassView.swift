import SwiftUI
import RouterCore

/// «Обход» tab root (contract-stage4 §5.4): zapret · Telegram через Cloudflare · Сервисы напрямую ·
/// Сайты без VPN (MyDirect).
///
/// The shell (TabRoot) gives the NavigationStack, title, gear, status pill, toasts and the 428 sheets.
/// Every change goes through `store.perform` (server 428 confirm for toggles and sites); nothing is started by
/// a swipe or by pull-to-refresh, which only re-reads `/status`, `/zapret`, `/tgws`, `/mydirect`.
struct BypassView: View {
    @Environment(RouterStore.self) private var store

    var body: some View {
        ScreenScroll(refresh: BypassKinds.all) {
            if store.bypassHasNoRouterData {
                EmptyStateView(
                    title: "Роутер не на связи",
                    systemImage: "wifi.slash",
                    text: ZapretTexts.noStatus,
                    style: .full
                )
                .padding(.top, 40)
            } else {
                BypassIntro()
                if store.bypassShowsStaleData {
                    StaleDataNote()
                }
                Group {
                    ZapretCard()
                    TgwsCard()
                    ServicesDirectCard()
                    MyDirectCard()
                }
                .staleDimmed(store.offline)
            }
        }
        .pollingScope(BypassKinds.all)
    }
}

/// One line under the large title (mock-up: «Что идёт мимо VPN и как обходить замедления»).
private struct BypassIntro: View {
    var body: some View {
        Text("Что идёт мимо VPN и как обходить замедления")
            .font(.subheadline)
            .foregroundStyle(Theme.dim)
            .fixedSize(horizontal: false, vertical: true)
    }
}
