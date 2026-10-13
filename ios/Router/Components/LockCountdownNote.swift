import SwiftUI
import RouterCore

/// «Повтори через N с» while one of `actions` is locked (429 `retry_after`, PassWall pause after a restart or
/// «мимо VPN», verification windows; contract-stage4 §3.6). Shared by VPN, Devices and Bypass.
/// `centered: true` centres it under full-width buttons.
struct LockCountdownNote: View {
    @Environment(RouterStore.self) private var store
    let actions: [RouterAction]
    var centered: Bool = false

    var body: some View {
        if actions.contains(where: { store.isLocked($0) }) {
            TimelineView(.periodic(from: Date(), by: 1)) { context in
                let left = actions.map { store.lockSecondsLeft($0, now: context.date) }.max() ?? 0
                if left > 0 {
                    Label("Повтори через \(left)" + Fmt.nbsp + "с", systemImage: "hourglass")
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Theme.dim)
                        .frame(maxWidth: centered ? .infinity : nil)
                }
            }
        }
    }
}
