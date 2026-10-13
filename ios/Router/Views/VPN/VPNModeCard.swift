import SwiftUI
import RouterCore

// MARK: - Mode (§5.1.1)

/// «Через VPN» / «Напрямую» + «Подключён: …» + the Split warning.
/// The segment shows the server state and never flips before the 200 (the switch goes through 428 + Face ID).
/// The «Выбери сервер ниже» hint after «Через VPN» is shown above the server list (VPNServersSection),
/// where the scroll lands.
struct VPNModeCard: View {
    @Environment(RouterStore.self) private var store
    let status: RouterStatus
    let chooseServer: () -> Void

    var body: some View {
        let isDirect = VPN.mode(status) == .direct
        let server = VPN.connected(status)
        Card {
            CardTitle("Режим", symbol: "shield.lefthalf.filled")
            VPNModeSwitch(
                isDirect: isDirect,
                isBusy: store.vpnIsBusy(.switchDirect),
                isEnabled: store.isLoggedIn && !store.offline && !store.appDisabled,
                canGoDirect: store.canPerform(.switchDirect),
                onVPN: {
                    if isDirect {
                        chooseServer()
                    }
                },
                onDirect: {
                    if !isDirect {
                        store.vpnGoDirect()
                    }
                }
            )
            VStack(alignment: .leading, spacing: 4) {
                SectionLabel("Подключён")
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(status.current.isEmpty ? "—" : VPN.nodeName(status, status.current))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if let tag = server.tag {
                        ToneChip(text: tag, tone: server.isDirect ? .warn : .neutral)
                    }
                    Spacer(minLength: 0)
                }
            }
            .accessibilityElement(children: .combine)
            if let warning = VPN.splitWarning(status) {
                Banner(tone: .warn, text: warning)
            }
        }
    }
}

/// Two glass segments. «Напрямую» starts the dangerous switch (critical); «Через VPN» while direct only
/// scrolls to the server list (a server has to be chosen). Side by side; stacked at accessibility text sizes.
struct VPNModeSwitch: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let isDirect: Bool
    let isBusy: Bool
    let isEnabled: Bool
    let canGoDirect: Bool
    let onVPN: () -> Void
    let onDirect: () -> Void

    var body: some View {
        GlassGroup(axis: typeSize.isAccessibilitySize ? .vertical : .horizontal, spacing: 8, containerSpacing: 4) {
            VPNModeSegment(
                title: VPNTexts.modeVPN,
                symbol: "lock.shield",
                isSelected: !isDirect,
                isBusy: false,
                isEnabled: isEnabled,
                hint: isDirect ? "Покажет список серверов: VPN включится, когда подключишь сервер." : "",
                action: onVPN
            )
            VPNModeSegment(
                title: VPNTexts.modeDirect,
                symbol: "arrow.right",
                isSelected: isDirect,
                isBusy: isBusy,
                isEnabled: isEnabled && (isDirect || canGoDirect),
                hint: isDirect ? "" : "Весь трафик пойдёт без VPN. Сначала спросит подтверждение и Face ID.",
                action: onDirect
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Режим")
    }
}

struct VPNModeSegment: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let title: String
    let symbol: String
    let isSelected: Bool
    let isBusy: Bool
    let isEnabled: Bool
    let hint: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: isSelected ? "checkmark" : symbol)
                        .imageScale(.small)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                    .minimumScaleFactor(0.8)
            }
            .font(.subheadline.weight(isSelected ? .semibold : .regular))
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassChip(selected: isSelected)
        .disabled(!isEnabled)
        .opacity(isEnabled || isSelected ? 1 : 0.5)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(hint)
    }
}

// MARK: - «Лучший сервер для …» (§5.1.2)

struct VPNBestServers: View {
    let status: RouterStatus

    var body: some View {
        let chips = VPN.bestChips(status)
        if !chips.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(VPNTexts.bestTitle)
                    .padding(.horizontal, 4)
                    .accessibilityAddTraits(.isHeader)
                GlassChipRow {
                    ForEach(chips) { chip in
                        VPNBestChip(chip: chip)
                    }
                }
                .fullBleed()
            }
        }
    }
}

/// One chip. The current node's chip is selected and inert («Уже подключён»); another node's chip starts the
/// switch flow (428 high) — it is an action, so it is a real button, not a `GlassChip` filter.
struct VPNBestChip: View {
    @Environment(RouterStore.self) private var store
    let chip: BestServerChip

    var body: some View {
        if let action = chip.action {
            Button {
                store.vpnConnect(id: chip.nodeID, name: chip.nodeName)
            } label: {
                label(busy: store.vpnIsBusy(action))
            }
            .buttonStyle(.plain)
            .glassChip(selected: false)
            .disabled(!store.canPerform(action))
            .opacity(store.canPerform(action) || store.vpnIsBusy(action) ? 1 : 0.5)
            .accessibilityLabel("Лучший для \(chip.service): \(chip.nodeName), \(Fmt.ms(chip.ms))")
            .accessibilityHint("Подключить этот сервер. Сначала спросит подтверждение.")
        } else {
            // Not a control: no interactive (touch-reacting) glass.
            label(busy: false)
                .glassChip(selected: true, interactive: false)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Лучший для \(chip.service): \(chip.nodeName), \(Fmt.ms(chip.ms)), уже подключён")
        }
    }

    private func label(busy: Bool) -> some View {
        HStack(spacing: 6) {
            if busy {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: chip.isCurrent ? "checkmark" : chip.icon)
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            Text(chip.text)
                .monospacedDigit()
        }
        .font(.subheadline.weight(chip.isCurrent ? .semibold : .regular))
        .lineLimit(1)
        .padding(.horizontal, 14)
        .frame(minHeight: 44)
        .contentShape(Capsule())
    }
}
