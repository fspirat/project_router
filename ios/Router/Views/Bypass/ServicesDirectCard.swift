import SwiftUI
import RouterCore

/// «Сервисы напрямую» (svcdirect, contract-stage4 §5.4.5, port of app.js:276-281, 658-667).
/// One toggle per service of the router's target list (`/status`); on = the service is in `svc_direct`.
/// Toggle → `svcdirect {"name", "on"}` → server 428 (high); PassWall restarts, then every PassWall control in
/// the app waits out the lock-out. Names the server would reject are shown with the toggle disabled.
struct ServicesDirectCard: View {
    @Environment(RouterStore.self) private var store

    var body: some View {
        let rows = store.svcDirectRows
        Card {
            CardTitle(SvcDirect.title, symbol: "arrow.uturn.right")
            Text("Сервис пойдёт без VPN на всех устройствах дома — запись в MyDirect.")
                .font(.footnote)
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
            if store.status == nil {
                EmptyStateView(
                    title: store.offline ? RouterStore.bypassOfflineEmpty : ZapretTexts.loading,
                    systemImage: store.offline ? "wifi.slash" : "hourglass"
                )
            } else if rows.isEmpty {
                EmptyStateView(title: SvcDirect.empty, systemImage: "square.stack.3d.up.slash")
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 {
                            LineDivider()
                                .padding(.vertical, 6)
                        }
                        ServiceDirectRow(row: row)
                    }
                }
                // Locks are per action name: one probe covers every service toggle.
                BypassLockNote(actions: Array(rows.compactMap { $0.toggleAction }.prefix(1)))
            }
        }
    }
}

private struct ServiceDirectRow: View {
    @Environment(RouterStore.self) private var store
    let row: SvcDirectRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ConfirmToggle(
                title: row.name,
                subtitle: row.host.isEmpty ? nil : row.host,
                systemImage: row.icon,
                isOn: row.isOn,
                isBusy: isBusy,
                isEnabled: store.canToggleService(row)
            ) {
                if let action = row.toggleAction {
                    store.perform(action, label: row.name, symbol: row.icon)
                }
            }
            BypassCaption(row.editCaption ?? row.caption)
                .padding(.leading, 36)
        }
        .accessibilityElement(children: .contain)
    }

    private var isBusy: Bool {
        guard let action = row.toggleAction else {
            return false
        }
        return store.isRunning(action) || store.isConfirming(action)
    }
}
