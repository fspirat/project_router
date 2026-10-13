import Foundation
import RouterCore

// «Журнал» tab (contract-stage4 §5.5): computed views of the `/data?range=…` caches. No stored state here —
// the range, the level filter and the search text live in JournalView (@SceneStorage / @State).
// `/data` comes from the server, so the journal works while the router is offline.

extension RouterStore {
    /// What the Journal screen reads: `/data` of the chosen range only (60 s timer, contract-stage4 §4.2).
    func journalKinds(_ range: DataRange) -> Set<ReadKind> {
        return [.data(range)]
    }

    /// Own device names for « (<name>)» after MACs: the newest `/data` of any range, else this range's.
    private func journalNames(_ data: DataResponse) -> [String: String] {
        if let latest = latestData, !latest.names.isEmpty {
            return latest.names
        }
        return data.names
    }

    /// Filtered, searched, grouped by Samara day (RouterCore `Journal.build`); nil until the range is loaded.
    func journal(range: DataRange, filter: JournalFilter, query: String, now: Date = Date()) -> JournalInfo? {
        guard let data = self.data(range) else {
            return nil
        }
        return Journal.build(
            data.events,
            names: journalNames(data),
            range: range,
            filter: filter,
            query: query,
            now: now.timeIntervalSince1970
        )
    }

    /// Rows per level filter for the chips (the search applies, the level filter does not).
    func journalFilterCounts(range: DataRange, query: String, now: Date = Date()) -> [JournalFilter: Int] {
        guard let all = journal(range: range, filter: .all, query: query, now: now) else {
            return [:]
        }
        var counts: [JournalFilter: Int] = [:]
        for filter in JournalFilter.allCases {
            var n = 0
            for day in all.days {
                for row in day.rows where filter.matches(row.level) {
                    n += 1
                }
            }
            counts[filter] = n
        }
        return counts
    }

    /// The range has never loaded and nothing explains why yet → show the loading card.
    func journalIsLoading(_ range: DataRange) -> Bool {
        return data(range) == nil && readError(.data(range)) == nil && !appDisabled
    }
}
