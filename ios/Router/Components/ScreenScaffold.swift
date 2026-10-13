import SwiftUI
import RouterCore

/// The standard screen body: app gradient behind, a lazy column of cards with 16 pt side padding and
/// 14 pt between cards, pull-to-refresh that re-reads `refresh` (never runs actions).
///
/// ```swift
/// ScreenScroll(refresh: [.status, .vds]) {
///     ModeCard()
///     GlassChipRow { … }.fullBleed()      // chip rows pad themselves
///     ServersCard()
/// }
/// .pollingScope([.status, .vds])
/// ```
struct ScreenScroll<Content: View>: View {
    @Environment(RouterStore.self) private var store
    let refresh: Set<ReadKind>
    private let content: Content

    init(refresh: Set<ReadKind>, @ViewBuilder content: () -> Content) {
        self.refresh = refresh
        self.content = content()
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Metrics.cardSpacing) {
                content
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .appScreenBackground()
        .refreshable { [store, refresh] in
            await store.refresh(refresh)
        }
    }
}

/// The gear in the top-trailing toolbar of every tab root: opens Settings (sheet).
/// No button style: the system draws it as Liquid Glass on iOS 26.
struct SettingsToolbarButton: View {
    @Environment(RouterStore.self) private var store

    var body: some View {
        Button {
            store.isSettingsPresented = true
        } label: {
            Image(systemName: "gearshape")
        }
        .accessibilityLabel("Настройки")
    }
}

/// The floating status pill under the navigation bar on tabs other than «Сводка» (which has full banners):
/// quiet window («VPN перезапускается…»), offline (compact line, contract-stage4 §4.3), app disabled.
struct StatusPillBar: View {
    @Environment(RouterStore.self) private var store

    var body: some View {
        let shown = store.appDisabled || store.quietBanner != nil || store.offline
        // The animation sits on a container that always exists, so the pill's insert/remove transition runs.
        VStack(spacing: 0) {
            if shown {
                pill
                    .padding(.horizontal, Metrics.screenPadding)
                    .padding(.bottom, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: shown)
    }

    @ViewBuilder
    private var pill: some View {
        Group {
            if store.appDisabled {
                StatusPill(tone: .warn, text: AppTexts.appDisabledTitle, systemImage: "power.circle")
            } else if let quiet = store.quietBanner {
                StatusPill(tone: .info, text: quiet, showsProgress: true)
            } else if store.offline {
                TimelineView(.periodic(from: Date(), by: 30)) { context in
                    StatusPill(
                        tone: .err,
                        text: OfflineBanner.compactLine(data: store.latestData, now: context.date.timeIntervalSince1970),
                        systemImage: "wifi.slash"
                    )
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: store.offline)
        .animation(.easeInOut(duration: 0.25), value: store.quietBanner)
    }
}
