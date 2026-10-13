import SwiftUI
import RouterCore

/// The cards of the «Журнал» tab (inside the ScreenScroll lazy column): caption and count, period picker,
/// level chips, then one card per Samara day, footer notices; loading / error / empty states.
struct JournalContent: View {
    @Environment(RouterStore.self) private var store
    @Binding var range: DataRange
    @Binding var filter: JournalFilter
    @Binding var query: String

    var body: some View {
        let now = Date()
        let info = store.journal(range: range, filter: filter, query: query, now: now)
        let counts = store.journalFilterCounts(range: range, query: query, now: now)

        JournalHeader(countText: info?.countText ?? "")
        SegmentedPicker(
            title: "Период",
            selection: $range,
            options: DataRange.allCases.map { SegmentOption($0, $0.shortLabel) }
        )
        JournalFilterChips(filter: $filter, counts: counts)
            .fullBleed()
        if let error = store.readError(.data(range)) {
            Banner(tone: .warn, text: error)
        }
        if let info = info {
            JournalBody(info: info, range: range, onReset: resetFilters)
        } else {
            JournalNoDataState(range: range)
        }
    }

    /// «Сбросить фильтр и поиск»: selection only, never a router action.
    private func resetFilters() {
        filter = .all
        query = ""
    }
}

// MARK: - Header

/// «Время роутера (Самара, UTC+4)» and «7 записей» / «найдено 1 из 7».
private struct JournalHeader: View {
    let countText: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                note
                Spacer(minLength: 8)
                count
            }
            VStack(alignment: .leading, spacing: 4) {
                note
                count
            }
        }
        .font(.footnote)
        .foregroundStyle(Theme.dim)
    }

    private var note: some View {
        Label(JournalTexts.timeNote, systemImage: "clock")
    }

    @ViewBuilder
    private var count: some View {
        if !countText.isEmpty {
            Text(countText)
                .monospacedDigit()
                .lineLimit(1)
        }
    }
}

// MARK: - Level chips

/// «Все» / «Ошибки» / «Внимание» / «Действия» with counts (search applied). Selection only.
private struct JournalFilterChips: View {
    @Binding var filter: JournalFilter
    let counts: [JournalFilter: Int]

    var body: some View {
        GlassChipRow {
            ForEach(JournalFilter.allCases, id: \.self) { item in
                GlassChip(
                    title: item.title,
                    systemImage: JournalFilterChips.symbol(item),
                    count: counts[item],
                    isSelected: filter == item
                ) {
                    filter = item
                }
                .accessibilityLabel(JournalFilterChips.voiceLabel(item, count: counts[item]))
            }
        }
    }

    static func symbol(_ item: JournalFilter) -> String? {
        switch item {
        case .all:
            return nil
        case .errors:
            return Theme.symbol(.err)
        case .warnings:
            return Theme.symbol(.warn)
        case .actions:
            return "hand.tap"
        }
    }

    static func voiceLabel(_ item: JournalFilter, count: Int?) -> String {
        guard let count = count else {
            return item.title
        }
        return item.title + ", " + Fmt.count(count, "запись", "записи", "записей")
    }
}

// MARK: - Loaded

/// Days, the empty states and the footer notices of one loaded range.
private struct JournalBody: View {
    let info: JournalInfo
    let range: DataRange
    let onReset: () -> Void

    var body: some View {
        if let empty = info.emptyText {
            if info.total == 0 {
                JournalEmptyState(range: range, text: empty)
            } else {
                JournalFilteredEmptyState(text: empty, onReset: onReset)
            }
        } else {
            ForEach(info.days) { day in
                JournalDaySection(day: day)
            }
        }
        if !info.notices.isEmpty {
            JournalNotices(notices: info.notices)
        }
    }
}

/// One Samara day: a header («Сегодня», «Вчера», «12 октября») and a card with its rows.
/// The card is the only surface; rows are plain (no glass per row).
private struct JournalDaySection: View {
    let day: JournalDay

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(day.title)
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text(Fmt.count(day.rows.count, "запись", "записи", "записей"))
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(Theme.dim)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 4)
            Card(spacing: 0) {
                ForEach(Array(day.rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        LineDivider()
                    }
                    JournalRowView(row: row)
                }
            }
        }
    }
}

/// The 100-event limit and «За 30 дней список может быть неполным.».
private struct JournalNotices: View {
    let notices: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(notices, id: \.self) { notice in
                Label(notice, systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(Theme.dim)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Empty, loading, error

/// No events in the period: «За 7 дней событий нет» + «Здесь появятся смены сервера…».
private struct JournalEmptyState: View {
    let range: DataRange
    let text: String

    var body: some View {
        EmptyStateView(
            title: "За " + range.title + " событий нет",
            systemImage: AppTab.journal.symbol,
            text: JournalEmptyState.description(text),
            style: .full
        )
        .padding(.top, 12)
    }

    /// The core text without its first sentence («Событий пока нет.»); the whole text if it has one sentence.
    static func description(_ text: String) -> String {
        guard let dot = text.range(of: ". ") else {
            return text
        }
        let rest = text[dot.upperBound...].trimmingCharacters(in: .whitespaces)
        return rest.isEmpty ? text : rest
    }
}

/// Filter or search left nothing: «Таких записей нет.» + reset (selection only).
private struct JournalFilteredEmptyState: View {
    let text: String
    let onReset: () -> Void

    var body: some View {
        Card {
            EmptyStateView(
                title: text,
                systemImage: "line.3.horizontal.decrease.circle",
                text: "Попробуй другой фильтр, период или запрос."
            )
            Button(action: onReset) {
                Text("Показать все записи")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .appButtonStyle(.secondary)
        }
    }
}

/// The range has no `/data` yet: loading, app disabled, or the read failed (the banner above says why).
private struct JournalNoDataState: View {
    @Environment(RouterStore.self) private var store
    let range: DataRange

    var body: some View {
        if store.journalIsLoading(range) {
            Card {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Загружаю журнал…")
                        .font(.subheadline)
                        .foregroundStyle(Theme.dim)
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .accessibilityElement(children: .combine)
            }
        } else if store.appDisabled {
            Card {
                EmptyStateView(
                    title: "Журнал сейчас недоступен",
                    systemImage: "power.circle",
                    text: "Приложение выключено на сервере. Когда его включат, журнал загрузится сам."
                )
            }
        } else {
            Card {
                EmptyStateView(
                    title: "Журнал не загрузился",
                    systemImage: "exclamationmark.arrow.circlepath",
                    text: "Потяни экран вниз, чтобы попробовать ещё раз."
                )
            }
        }
    }
}
