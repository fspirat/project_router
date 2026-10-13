import SwiftUI
import RouterCore

/// The server card (contract-stage4 §5.1.4), a sheet with `.medium` / `.large` detents.
/// - «Проверить сейчас» = `pingone` (no dialog; < 1 s; not for the direct row);
/// - «Подключить» = `switch` (428 high; the server warns itself when the node does not answer); hidden for the
///   current node;
/// - direct row: «Напрямую, без VPN» = `switch direct` (428 critical + Face ID); hidden when already direct.
/// All buttons are disabled offline, during the PassWall lock-out and while another action runs (`canPerform`).
struct VPNServerSheet: View {
    @Environment(RouterStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let serverID: String

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 15)) { context in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    content(now: context.date.timeIntervalSince1970)
                }
                .padding(20)
            }
        }
        .sheetSurface()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .pollingScope([.status])
    }

    @ViewBuilder
    private func content(now: TimeInterval) -> some View {
        // «Проверено только что» after `pingone`: the stamp is kept by the store (survives closing the card).
        if let status = store.status, let detail = VPN.serverDetail(status, id: serverID, now: now, pingedAt: store.pingedAt[serverID]) {
            VPNServerHeader(detail: detail, close: close)
            if store.vpnShowsStaleData {
                StaleDataNote()
            }
            VPNServerPingTile(detail: detail)
            if !detail.isDirect && detail.pingLevel == 0 {
                Banner(
                    tone: .warn,
                    text: "Сервер сейчас не отвечает. Если подключить его, дом может остаться без VPN до автопереключения (~10 мин)."
                )
            }
            VPNServerServices(detail: detail)
            VPNServerButtons(detail: detail, onSwitched: close)
        } else {
            HStack {
                Spacer(minLength: 0)
                GlassIconButton(systemImage: "xmark", accessibilityLabel: "Закрыть", action: close)
            }
            EmptyStateView(
                title: "Этого сервера больше нет в списке.",
                systemImage: "questionmark.circle",
                text: "Список серверов обновился. Закрой карточку и выбери сервер заново."
            )
        }
    }

    private func close() {
        dismiss()
    }
}

struct VPNServerHeader: View {
    let detail: VPNServerDetail
    let close: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text(detail.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 6) {
                    if let tag = detail.tag {
                        ToneChip(text: tag, tone: detail.isDirect ? .warn : .neutral)
                    }
                    if let current = detail.currentText {
                        ToneChip(text: current, tone: .ok, systemImage: "checkmark")
                    }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            GlassIconButton(systemImage: "xmark", accessibilityLabel: "Закрыть", action: close)
        }
    }
}

struct VPNServerPingTile: View {
    let detail: VPNServerDetail

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "cellularbars", variableValue: Double(max(0, min(5, detail.pingLevel))) / 5)
                .font(.title2)
                .foregroundStyle(Theme.dot(detail.pingTone))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(detail.isDirect ? "Пинг до ya.ru" : "Пинг")
                    .font(.caption)
                    .foregroundStyle(Theme.dim)
                Text(detail.pingText)
                    .font(.title2.weight(.semibold))
                    .numericValue(detail.pingText)
                    .foregroundStyle(Theme.levelText(detail.pingTone))
            }
            Spacer(minLength: 8)
            if let checked = detail.checkedText {
                Text(checked)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.dim)
                    .multilineTextAlignment(.trailing)
            }
        }
        .innerTile()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel((detail.isDirect ? "Пинг до ya.ru: " : "Пинг: ") + detail.pingText + ", " + VPNA11y.level(detail.pingTone))
        .accessibilityValue(detail.checkedText ?? "")
    }
}

struct VPNServerServices: View {
    let detail: VPNServerDetail

    var body: some View {
        if !detail.services.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(detail.isDirect ? "Сервисы без VPN" : "Сервисы через этот сервер")
                VStack(spacing: 0) {
                    ForEach(detail.services) { service in
                        if service.id != detail.services.first?.id {
                            LineDivider()
                        }
                        HStack(spacing: 10) {
                            Image(systemName: service.icon)
                                .foregroundStyle(Theme.dim)
                                .frame(width: 24)
                                .accessibilityHidden(true)
                            Text(service.name)
                                .font(.subheadline)
                                .foregroundStyle(Theme.text)
                            Spacer(minLength: 8)
                            Text(service.valueText)
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(service.tone == .neutral ? Theme.dim : Theme.levelText(service.tone))
                                .multilineTextAlignment(.trailing)
                        }
                        .frame(minHeight: 40)
                        .accessibilityElement(children: .combine)
                    }
                }
                .innerTile()
                if let measured = detail.measuredText {
                    Text(measured)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.dim)
                }
            }
        }
    }
}

struct VPNServerButtons: View {
    @Environment(RouterStore.self) private var store
    let detail: VPNServerDetail
    let onSwitched: () -> Void

    var body: some View {
        GlassGroup(axis: .vertical, spacing: 10) {
            if let ping = detail.pingAction {
                let busy = store.isRunning(ping)
                AppButton(
                    title: busy ? VPNTexts.pingBusy : VPNTexts.pingNow,
                    systemImage: "arrow.clockwise",
                    kind: .secondary,
                    isBusy: busy
                ) {
                    store.perform(ping, label: detail.name)
                }
                .disabled(!store.canPerform(ping))
                .accessibilityHint("Пинг одного сервера, меньше секунды, без вопроса.")
            }
            if let connect = detail.connectAction {
                if detail.showsDirectButton {
                    AppButton(
                        title: VPNTexts.directButton,
                        systemImage: "exclamationmark.shield",
                        kind: .destructiveOutline,
                        isBusy: store.vpnIsBusy(connect)
                    ) {
                        store.vpnGoDirect { result in
                            if result.isSuccess {
                                onSwitched()
                            }
                        }
                    }
                    .disabled(!store.canPerform(connect))
                    .accessibilityHint("Весь трафик пойдёт без VPN. Сначала спросит подтверждение и Face ID.")
                } else {
                    AppButton(
                        title: VPNTexts.connect,
                        systemImage: "bolt.horizontal",
                        kind: .primary,
                        isBusy: store.vpnIsBusy(connect)
                    ) {
                        store.vpnConnect(id: detail.id, name: detail.name) { result in
                            if result.isSuccess {
                                onSwitched()
                            }
                        }
                    }
                    .disabled(!store.canPerform(connect))
                    .accessibilityHint("VPN перезапустится. Сначала спросит подтверждение.")
                }
                LockCountdownNote(actions: [connect], centered: true)
            }
        }
        .padding(.top, 4)
    }
}
