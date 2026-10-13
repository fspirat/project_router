import SwiftUI
import RouterCore

/// «Telegram через Cloudflare» (`/tgws`, contract-stage4 §5.4.4, port of `renderTgws`, app.js:1036-1046).
/// Own card, shown whether or not zapret is installed. Toggle → `tgwsset {"on": !enabled}` → server 428
/// (medium, normal button). The router applies it in the background and fails silently, so the store re-reads
/// at +3 s and +8 s and says so if the proxy did not switch. No `tg://proxy` link (the secret stays on the router).
struct TgwsCard: View {
    @Environment(RouterStore.self) private var store

    var body: some View {
        let info = store.tgwsInfo
        Card {
            CardHeader(TgwsTexts.title, symbol: "paperplane") {
                ToneChip(text: TgwsTexts.tag, tone: .warn, systemImage: "flask")
            }
            if info.phase == .loading && store.offline {
                EmptyStateView(title: RouterStore.bypassOfflineEmpty, systemImage: "wifi.slash")
            } else {
                BypassStatusLine(
                    tone: info.tone,
                    summary: info.summary,
                    bold: info.summaryBold,
                    counter: info.counter,
                    showsProgress: info.phase == .loading || info.phase == .starting
                )
            }
            BypassReadError(kind: .tgws)
            if info.showsToggle {
                LineDivider()
                ConfirmToggle(
                    title: "Telegram мимо VPN",
                    subtitle: "Telegram на всех устройствах дома пойдёт через Cloudflare с IP провайдера. Если прокси перестанет работать, Telegram сам вернётся на VPN.",
                    isOn: info.isOn,
                    isBusy: isBusy(info),
                    isEnabled: store.canToggleTgws(info)
                ) {
                    store.perform(info.toggleAction, symbol: "paperplane")
                }
                if store.verifyingTgws {
                    BypassCaption("Проверяю, что роутер переключил прокси…", systemImage: "clock")
                } else {
                    LockCountdownNote(actions: [info.toggleAction])
                }
            }
        }
    }

    private func isBusy(_ info: TgwsInfo) -> Bool {
        return store.isRunning(named: "tgwsset") || store.isConfirming(info.toggleAction) || store.verifyingTgws
    }
}
