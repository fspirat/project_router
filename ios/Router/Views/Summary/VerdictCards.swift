import SwiftUI
import RouterCore

/// «Итог» (contract §4.2): lamp, title, «обновлено …», reasons. The level is shown by colour AND word.
/// The one hero element of «Сводка»: real Liquid Glass tinted with the level colour on iOS 26
/// (`heroGlassCard`), a tinted material card before. Nothing inside it is glass (no glass on glass).
struct VerdictCard: View {
    let verdict: Verdict

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                VerdictLamp(level: verdict.level)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verdict.title)
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    UpdatedLabel()
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            if !verdict.items.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(verdict.items.enumerated()), id: \.offset) { _, item in
                        VerdictItemRow(item: item)
                    }
                }
            }
            if let warning = verdict.splitWarning {
                Banner(tone: .warn, text: warning)
            }
        }
        .heroGlassCard(tint: Theme.dot(verdict.level))
    }
}

/// 44×44 lamp, radius 12, soft fill and a 12 pt dot; pulses on `err` unless Reduce Motion is on.
struct VerdictLamp: View {
    let level: Tone
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @State var pulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Theme.soft(level))
            .frame(width: 44, height: 44)
            .overlay {
                Circle()
                    .fill(Theme.dot(level))
                    .frame(width: 12, height: 12)
                    .scaleEffect(pulse ? 1.35 : 1)
                    .opacity(pulse ? 0.55 : 1)
            }
            .accessibilityHidden(true)
            .onAppear {
                updatePulse()
            }
            .onChange(of: level) { _, _ in
                updatePulse()
            }
    }

    private func updatePulse() {
        if level == .err && !reduceMotion {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.2)) {
                pulse = false
            }
        }
    }
}

/// «● VPN работает»: dot, name in `dim`, text in bold in the level colour.
struct VerdictItemRow: View {
    let item: VerdictItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            ToneDot(tone: item.level)
            if let name = item.name {
                Text(name)
                    .foregroundStyle(Theme.dim)
            }
            Text(item.text)
                .fontWeight(.semibold)
                .foregroundStyle(item.level == .ok ? Theme.text : Theme.levelText(item.level))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.subheadline)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let word = Theme.levelWord(item.level)
        if let name = item.name {
            return "\(name): \(item.text), \(word)"
        }
        return "\(item.text), \(word)"
    }
}

/// «обновлено N сек назад», from the last successful status; refreshed every 5 s.
struct UpdatedLabel: View {
    @Environment(RouterStore.self) var store

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 5)) { context in
            let label = Summary.updatedLabel(
                lastSuccess: store.lastStatusAt?.timeIntervalSince1970,
                now: context.date.timeIntervalSince1970
            )
            Text(label ?? "ещё не обновлялось")
                .font(.footnote)
                .foregroundStyle(Theme.dim)
        }
    }
}

/// Quiet-window banner, status errors, login and TestFlight expiry warnings.
struct NoticeBanners: View {
    @Environment(RouterStore.self) var store
    let now: TimeInterval

    var body: some View {
        if let quiet = store.quietBanner {
            Banner(tone: .info, text: quiet, showsProgress: true)
        }
        if let error = store.statusError, !store.offline {
            Banner(tone: .warn, text: error)
        }
        if let warning = ExpiryNotice.loginWarning(hardExpires: store.sessionInfo?.hardExpires ?? 0, now: now) {
            Banner(tone: .info, text: warning, symbol: "key")
        }
        if let date = AppConfig.buildDate, let warning = ExpiryNotice.buildWarning(buildDate: date, now: now) {
            Banner(tone: .warn, text: warning, symbol: "hourglass")
        }
    }
}

/// «Роутер не на связи» (contract §4.12). Chart, events and today's traffic stay visible below.
struct OfflineCard: View {
    @Environment(RouterStore.self) var store
    let now: TimeInterval

    var body: some View {
        Card(accent: Theme.err, tint: Theme.err) {
            HStack(spacing: 10) {
                Image(systemName: "wifi.slash")
                    .foregroundStyle(Theme.err)
                    .accessibilityHidden(true)
                Text(OfflineBanner.heading)
                    .font(.headline)
                    .foregroundStyle(Theme.text)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Text(OfflineBanner.line(data: store.latestData, now: now))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(Theme.err)
                .fixedSize(horizontal: false, vertical: true)
            BulletList(title: OfflineBanner.whyTitle, lines: OfflineBanner.why)
            BulletList(title: OfflineBanner.whatTitle, lines: OfflineBanner.what)
            Text(OfflineBanner.note)
                .font(.footnote)
                .foregroundStyle(Theme.dim)
        }
    }
}

struct BulletList: View {
    let title: String
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.text)
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("•")
                        .foregroundStyle(Theme.dim)
                    Text(line)
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.subheadline)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// `503 app_disabled`: the token is kept; pull down to check again.
struct AppDisabledCard: View {
    var body: some View {
        Card(accent: Theme.warn, tint: Theme.warn) {
            HStack(spacing: 10) {
                Image(systemName: "power.circle")
                    .font(.title2)
                    .foregroundStyle(Theme.warn)
                    .accessibilityHidden(true)
                Text(AppTexts.appDisabledTitle)
                    .font(.headline)
                    .foregroundStyle(Theme.text)
            }
            Text(APIError.fallbackTexts["app_disabled"] ?? "Приложение выключено на сервере. Веб-панель работает.")
                .font(.subheadline)
                .foregroundStyle(Theme.text)
            Text("Потяни экран вниз, чтобы проверить снова. Вход сохранён.")
                .font(.footnote)
                .foregroundStyle(Theme.dim)
            Link(destination: Links.webPanel) {
                Label("Открыть веб-панель", systemImage: "globe")
                    .fontWeight(.semibold)
                    .foregroundStyle(ActionButtonStyle.Kind.secondary.labelColor)
                    .frame(maxWidth: .infinity)
            }
            .appButtonStyle(.secondary)
        }
    }
}
