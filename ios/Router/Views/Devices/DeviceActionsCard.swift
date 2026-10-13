import SwiftUI
import RouterCore

/// The card's buttons (contract-stage4 §5.3.2). Every router action goes through `store.perform`
/// (428 sheet with the server texts, red button for block, re-reads, toasts). Buttons only — no gestures.
/// - «Переименовать»: sheet; works while the router is offline (server-only).
/// - «Выключить интернет» (block, red confirm) / «Включить интернет» (unblock, no dialog).
/// - «Пускать мимо VPN» / «Снова через VPN» (direct, confirm; PW lock-out afterwards).
/// - «Расписание…»: sheet.
struct DeviceActionsCard: View {
    @Environment(RouterStore.self) private var store
    let detail: DeviceDetail
    @Binding var showRename: Bool
    @Binding var showSchedule: Bool

    var body: some View {
        Card {
            CardTitle("Действия", symbol: "slider.horizontal.3")
            notes
            VStack(spacing: 10) {
                AppButton(title: DeviceTexts.rename, systemImage: "pencil", kind: .secondary) {
                    showRename = true
                }
                .accessibilityHint("Своё имя устройства в панели и приложении")
                internetButton
                directButton
                scheduleButton
            }
            DeviceLockNote(actions: lockableActions)
        }
    }

    // MARK: - Notes

    @ViewBuilder
    private var notes: some View {
        if !detail.isKnown {
            Text(store.status == nil
                 ? "Роутер не на связи — сейчас можно только переименовать устройство."
                 : "Устройства сейчас нет в списке роутера — можно только переименовать.")
                .font(.footnote)
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        } else if store.offline {
            Text("Роутер не на связи — интернет, VPN и расписание поменять нельзя. Переименовать можно.")
                .font(.footnote)
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
        if detail.isKnown && detail.sblocked && !detail.blocked {
            Banner(tone: .warn, text: ScheduleTexts.unblockDuringWindow, symbol: "timer")
        }
    }

    // MARK: - Buttons

    @ViewBuilder
    private var internetButton: some View {
        if let action = detail.blockAction {
            AppButton(
                title: DeviceTexts.block,
                systemImage: "nosign",
                kind: .destructiveOutline,
                isBusy: store.isRunning(action)
            ) {
                store.perform(action, label: label, symbol: "nosign")
            }
            .disabled(!store.canPerform(action))
        } else if let action = detail.unblockAction {
            AppButton(
                title: DeviceTexts.unblock,
                systemImage: "checkmark",
                kind: .primary,
                isBusy: store.isRunning(action)
            ) {
                unblock(action)
            }
            .disabled(!store.canPerform(action))
        }
    }

    @ViewBuilder
    private var directButton: some View {
        if let action = detail.directAction {
            AppButton(
                title: detail.directButtonTitle,
                systemImage: detail.direct ? "lock.shield" : "arrow.uturn.right",
                kind: .secondary,
                isBusy: store.isRunning(action)
            ) {
                store.perform(action, label: label, symbol: detail.direct ? "lock.shield" : "arrow.uturn.right")
            }
            .disabled(!store.canPerform(action))
        }
    }

    @ViewBuilder
    private var scheduleButton: some View {
        if detail.isKnown {
            let probe = ScheduleWindow.initial(for: detail.sched).action(mac: detail.mac)
            AppButton(
                title: detail.scheduleButtonTitle,
                systemImage: "timer",
                kind: .secondary,
                isBusy: store.isRunning(named: "schedule")
            ) {
                showSchedule = true
            }
            .disabled(!store.canPerform(probe))
        }
    }

    // MARK: - Helpers

    private var label: String? {
        return store.deviceActionLabel(mac: detail.mac)
    }

    /// The actions whose 429 / PW lock-out countdown the card shows.
    private var lockableActions: [RouterAction] {
        guard detail.isKnown else {
            return []
        }
        var out: [RouterAction] = []
        if let a = detail.blockAction {
            out.append(a)
        }
        if let a = detail.unblockAction {
            out.append(a)
        }
        if let a = detail.directAction {
            out.append(a)
        }
        out.append(.scheduleClear(mac: detail.mac))
        return out
    }

    /// «Включить интернет» has no dialog. During an active schedule window the device stays offline:
    /// replace the success toast with the hint (contract-stage4 §5.3.2).
    private func unblock(_ action: RouterAction) {
        let duringWindow = detail.sblocked
        let store = self.store
        store.perform(action, label: label, symbol: "checkmark") { result in
            if result.isSuccess && duringWindow {
                store.showToast(ScheduleTexts.unblockDuringWindow, tone: .info)
            }
        }
    }
}

/// «Повтори через N с» while an action is locked (429 `retry_after`, PW lock-out after «мимо VPN»).
struct DeviceLockNote: View {
    @Environment(RouterStore.self) private var store
    let actions: [RouterAction]

    var body: some View {
        if actions.contains(where: { store.isLocked($0) }) {
            TimelineView(.periodic(from: Date(), by: 1)) { context in
                let left = actions.map { store.lockSecondsLeft($0, now: context.date) }.max() ?? 0
                if left > 0 {
                    Label("Повтори через \(left)" + Fmt.nbsp + "с", systemImage: "hourglass")
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Theme.dim)
                }
            }
        }
    }
}
