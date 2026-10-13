import SwiftUI
import RouterCore

/// «YouTube и Discord без VPN» — zapret (contract-stage4 §5.4.1–5.4.3, port of `renderZap`, app.js:968-1005).
///
/// - Toggle: `zapretset {"on": !enabled}` → server 428 (high). Shows the server value, never flips before
///   the router reports it.
/// - Strategy «1 / 2 / 3»: `zapretstrat {n}` without a dialog; the store re-reads at +2/+4/+7 s and says
///   «Стратегия N выбрана.» or that it did not apply. The control keeps showing the server value meanwhile.
/// - «Проверить YouTube и Discord»: `zapretcheck` without a dialog; results as tiles.
/// - `/zapret` polls every 3 s while busy/checking (store, ≤ 2 min per trigger).
struct ZapretCard: View {
    @Environment(RouterStore.self) private var store

    var body: some View {
        let info = store.zapretInfo()
        Card {
            CardTitle(ZapretTexts.title, symbol: "play.rectangle")
            if info.phase == .loading && store.offline {
                EmptyStateView(title: RouterStore.bypassOfflineEmpty, systemImage: "wifi.slash")
            } else {
                BypassStatusLine(
                    tone: info.tone,
                    summary: info.summary,
                    bold: info.summaryBold,
                    counter: info.counters,
                    showsProgress: info.phase == .loading || info.phase == .busy
                )
            }
            if let error = info.errorText {
                Banner(tone: errorTone(info), text: error)
            }
            BypassReadError(kind: .zapret)
            if info.showsControls {
                ZapretControls(info: info)
            }
        }
    }

    /// The router's own error (fallback, nfqws rejected the strategy) and «not installed» are errors;
    /// the «Расхождение…» notes are warnings the watchdog fixes within a minute.
    private func errorTone(_ info: ZapretInfo) -> Tone {
        if info.phase == .notInstalled {
            return .err
        }
        if let z = store.zapret, !z.error.isEmpty {
            return .err
        }
        return .warn
    }
}

/// Toggle, strategy, check, details (only when the script is present).
private struct ZapretControls: View {
    @Environment(RouterStore.self) private var store
    let info: ZapretInfo
    @State private var showsDetails = false

    var body: some View {
        LineDivider()
        ConfirmToggle(
            title: "Обход для YouTube и Discord",
            subtitle: ZapretTexts.toggleCaption,
            isOn: info.isOn,
            isBusy: store.isRunning(named: "zapretset") || store.isConfirming(info.toggleAction),
            isEnabled: store.canToggleZapret(info)
        ) {
            store.perform(info.toggleAction, symbol: "play.rectangle")
        }
        LineDivider()
        ZapretStrategyRow(info: info)
        LineDivider()
        ZapretCheckSection(info: info)
        if store.verifyingStrategy == nil {
            // While a strategy is verified its caption says so; the short lock needs no countdown.
            LockCountdownNote(actions: [info.toggleAction, .zapretstrat(n: info.strategy), .zapretcheck])
        }
        if !info.details.isEmpty {
            DisclosureGroup(isExpanded: $showsDetails) {
                ZapretDetails(facts: info.details)
                    .padding(.top, 8)
            } label: {
                Text(ZapretTexts.detailsTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
            }
            .tint(Theme.dim)
        }
    }
}

// MARK: - Strategy

private struct ZapretStrategyRow: View {
    @Environment(RouterStore.self) private var store
    let info: ZapretInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Стратегия")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.text)
                Spacer(minLength: 8)
                if pending != nil {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                }
            }
            SegmentedPicker(title: "Стратегия zapret", selection: selection, options: options)
                .disabled(!store.canChangeStrategy(info))
            BypassCaption(caption)
        }
    }

    /// The strategy sent and not yet confirmed by a re-read (request in flight or being verified).
    private var pending: Int? {
        if let n = store.verifyingStrategy {
            return n
        }
        if case .zapretstrat(let n)? = store.runningAction?.action {
            return n
        }
        return nil
    }

    private var options: [SegmentOption<Int>] {
        return Zapret.strategies.map { SegmentOption($0.n, String($0.n)) }
    }

    /// Shows the server value; choosing another one asks the router (no dialog, plan §2).
    private var selection: Binding<Int> {
        let current = info.strategy
        let store = self.store
        return Binding(
            get: {
                current
            },
            set: { @MainActor n in
                if n != current {
                    store.selectZapretStrategy(n)
                }
            }
        )
    }

    private var caption: String {
        if let n = pending {
            return "Применяю стратегию \(n) — проверю, что она включилась."
        }
        if let s = Zapret.strategies.first(where: { $0.n == info.strategy }) {
            return "Сейчас: стратегия " + s.title + ". Другая может помочь, если YouTube или Discord тормозят."
        }
        return "Сейчас: стратегия \(info.strategy)."
    }
}

// MARK: - Check

private struct ZapretCheckSection: View {
    @Environment(RouterStore.self) private var store
    let info: ZapretInfo

    private let columns = [
        GridItem(.flexible(), spacing: 10, alignment: .top),
        GridItem(.flexible(), spacing: 10, alignment: .top)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            AppButton(
                title: info.checkTitle,
                systemImage: "checkmark.circle",
                kind: .secondary,
                isBusy: isChecking
            ) {
                store.perform(.zapretcheck, symbol: "checkmark.circle")
            }
            .disabled(!store.canCheckZapret(info))
            .accessibilityHint("Проверка идёт с роутера через те же правила, что у устройств дома")
            if !info.results.isEmpty {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    ForEach(info.results) { tile in
                        ZapretResultTileView(tile: tile)
                    }
                }
            }
            if let caption = info.checkCaption {
                BypassCaption(caption, systemImage: info.results.isEmpty ? "exclamationmark.triangle" : "clock")
            }
        }
    }

    private var isChecking: Bool {
        if store.isRunning(.zapretcheck) {
            return true
        }
        return store.zapret?.checking ?? false
    }
}

/// One result: name, «412 мс» / «нет», «время ответа», the zapret note.
private struct ZapretResultTileView: View {
    let tile: ZapretResultTile

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tile.name)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: Theme.symbol(tile.tone))
                    .imageScale(.small)
                    .foregroundStyle(Theme.dot(tile.tone))
                    .accessibilityHidden(true)
                Text(tile.valueText)
                    .font(.title3.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.levelText(tile.tone))
            }
            Text(tile.tone == .ok ? ZapretTexts.tileLabel + " · " + tile.footnote : tile.footnote)
                .font(.caption)
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .innerTile(tone: tile.tone)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        if tile.tone == .ok {
            return tile.name + ": открывается, " + ZapretTexts.tileLabel + " " + tile.valueText + ", " + tile.footnote
        }
        return tile.name + ": " + tile.footnote
    }
}

// MARK: - Details

private struct ZapretDetails: View {
    let facts: [StatusFact]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(facts) { fact in
                FactRow(label: fact.label, value: fact.value, valueColor: color(fact.tone))
            }
            Text("Когда включено, YouTube и Discord идут напрямую через провайдера, с IP провайдера, а не через VPN. Остальные сайты — как раньше (VPN / MyDirect). Голос Discord идёт через VPN (в режиме «Напрямую» — тоже напрямую). Проверка в приложении — с роутера; окончательно — видео на YouTube и голосовой канал Discord.")
                .font(.footnote)
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
    }

    private func color(_ tone: Tone) -> Color {
        return tone == .neutral ? Theme.text : Theme.levelText(tone)
    }
}
