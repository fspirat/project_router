import SwiftUI
import RouterCore

/// «Устройства» tab root (contract-stage4 §5.2): «N в сети из M», search (name/IP/MAC), filter chips,
/// «Новые за неделю», then one card per group (Wi-Fi 5 ГГц / 2,4 ГГц / по кабелю / не в сети).
/// The shell (TabRoot) gives the NavigationStack, title, gear, status pill, toasts and confirm sheets.
/// Taps only open cards; nothing here starts a router action (no swipe actions).
struct DevicesView: View {
    @Environment(RouterStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    /// UI state only (not router data).
    @SceneStorage("devicesFilter") private var filter: DeviceFilter = .all
    @State private var query = ""

    private static let kinds: Set<ReadKind> = [.status, .data(.day)]

    var body: some View {
        ScreenScroll(refresh: DevicesView.kinds) {
            DevicesContent(query: query, filter: $filter)
        }
        .searchable(text: $query, prompt: Text(DeviceTexts.searchPrompt))
        .autocorrectionDisabled()
        .textInputAutocapitalization(.never)
        .navigationDestination(for: DeviceRoute.self) { route in
            DeviceDetailView(mac: route.mac)
        }
        .pollingScope(DevicesView.kinds)
        .onAppear {
            updateBadge()
        }
        .onChange(of: store.latestData?.newdevs) { _, _ in
            updateBadge()
        }
        .onChange(of: store.selectedTab) { _, _ in
            updateBadge()
        }
        .onChange(of: scenePhase) { _, _ in
            updateBadge()
        }
    }

    /// On screen → everything is seen (badge 0); on another tab → count what came since the last visit.
    private func updateBadge() {
        if store.selectedTab == .devices && scenePhase == .active {
            store.markDevicesSeen()
        } else {
            store.refreshDevicesBadge()
        }
    }
}

/// The cards of the tab (inside the ScreenScroll lazy column).
private struct DevicesContent: View {
    @Environment(RouterStore.self) private var store
    let query: String
    @Binding var filter: DeviceFilter

    var body: some View {
        let list = store.deviceList(query: query, filter: filter)
        let hasStatus = store.status != nil
        let isSearching = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let newRows = store.newDevicesThisWeek(now: Date().timeIntervalSince1970)

        if hasStatus {
            DevicesSummaryLine(text: list.summary)
            DeviceFilterChips(filter: $filter, query: query)
                .fullBleed()
        }
        if !newRows.isEmpty && !isSearching && filter == .all {
            DevicesNewCard(rows: newRows)
        }
        if let error = store.readError(.data(.day)) {
            Banner(tone: .warn, text: error)
        }
        if hasStatus {
            DevicesSections(list: list, isStale: store.offline)
        } else {
            DevicesNoStatusState()
        }
    }
}

/// «4 в сети из 6» / «найдено 2 из 6».
private struct DevicesSummaryLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline)
            .monospacedDigit()
            .foregroundStyle(Theme.dim)
            .padding(.horizontal, 4)
            .accessibilityAddTraits(.isSummaryElement)
    }
}

/// «Все» / «В сети» / «Не в сети» / «Ограничены» with counts (selection only).
private struct DeviceFilterChips: View {
    @Environment(RouterStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var filter: DeviceFilter
    let query: String

    var body: some View {
        GlassChipRow {
            ForEach(DeviceFilter.allCases, id: \.self) { option in
                GlassChip(
                    title: option.title,
                    count: store.deviceCount(filter: option, query: query),
                    isSelected: filter == option
                ) {
                    if reduceMotion {
                        filter = option
                    } else {
                        withAnimation(.snappy) {
                            filter = option
                        }
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Фильтр устройств")
    }
}

/// The groups, or the empty state; dimmed with a note while the router is offline.
private struct DevicesSections: View {
    let list: DeviceListInfo
    let isStale: Bool

    var body: some View {
        if isStale {
            StaleDataNote()
                .padding(.horizontal, 4)
        }
        if let empty = list.emptyText {
            EmptyStateView(
                title: empty,
                systemImage: list.total == 0 ? "wifi.slash" : "magnifyingglass",
                style: .full
            )
            .staleDimmed(isStale)
        } else {
            ForEach(list.sections) { section in
                DeviceSectionCard(section: section)
                    .staleDimmed(isStale)
            }
        }
    }
}

/// No `/status` yet: loading, an error, or the cold-start offline text (contract-stage4 §4.3).
private struct DevicesNoStatusState: View {
    @Environment(RouterStore.self) private var store

    var body: some View {
        if store.offline {
            Card {
                EmptyStateView(title: DeviceTexts.noStatus, systemImage: "wifi.slash")
            }
        } else if let error = store.statusError {
            Banner(tone: .err, text: error)
        } else {
            HStack(spacing: 10) {
                ProgressView()
                Text("Загружаю список устройств…")
                    .font(.subheadline)
                    .foregroundStyle(Theme.dim)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 32)
            .accessibilityElement(children: .combine)
        }
    }
}

/// One group card. «Не в сети» starts collapsed («Не в сети: 2») unless the filter or the search opens it.
struct DeviceSectionCard: View {
    let section: DeviceSection
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Card(spacing: 0) {
            if section.isCollapsed {
                collapsibleHeader
                if expanded {
                    rows
                        .padding(.top, 6)
                }
            } else {
                CardHeader(section.title, symbol: section.symbol) {
                    countText
                }
                .padding(.bottom, 6)
                rows
            }
        }
    }

    private var countText: some View {
        Text(String(section.count))
            .font(.subheadline.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(Theme.dim)
            .accessibilityLabel(Fmt.count(section.count, "устройство", "устройства", "устройств"))
    }

    private var collapsibleHeader: some View {
        Button {
            if reduceMotion {
                expanded.toggle()
            } else {
                withAnimation(.easeInOut(duration: 0.2)) {
                    expanded.toggle()
                }
            }
        } label: {
            HStack(spacing: 8) {
                CardTitle(section.header, symbol: section.symbol)
                Spacer(minLength: 8)
                Image(systemName: "chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.dim)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(section.header)
        .accessibilityValue(expanded ? "развёрнуто" : "свёрнуто")
        .accessibilityHint(expanded ? "Скрыть устройства" : "Показать устройства")
        .accessibilityAddTraits(.isHeader)
    }

    private var rows: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(section.rows.enumerated()), id: \.element.id) { item in
                if item.offset > 0 {
                    LineDivider()
                        .padding(.leading, 21)
                }
                NavigationLink(value: DeviceRoute(mac: item.element.mac)) {
                    DeviceListRow(row: item.element)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
