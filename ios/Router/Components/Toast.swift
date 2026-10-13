import SwiftUI
import UIKit
import RouterCore

/// A short message after an action («VPN перезапускается.»).
struct ToastMessage: Identifiable, Equatable {
    let id: UUID
    let text: String
    let tone: Tone

    init(text: String, tone: Tone) {
        self.id = UUID()
        self.text = text
        self.tone = tone
    }
}

/// Bottom overlay that shows `store.toast` for a few seconds. Tap to hide.
/// Placed by the topmost presentation host (tab root or app sheet), above the tab bar.
struct ToastOverlay: View {
    @Environment(RouterStore.self) var store

    var body: some View {
        ZStack {
            if let toast = store.toast {
                ToastView(toast: toast)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onTapGesture {
                        store.dismissToast(toast.id)
                    }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: store.toast)
        .padding(.horizontal, Metrics.screenPadding)
        .padding(.bottom, 12)
        .task(id: store.toast?.id) { [store] in
            await store.autoDismissToast()
        }
    }
}

/// Floating glass capsule (Liquid Glass on iOS 26, material before), tinted with the level colour.
/// Neutral text on tinted glass; the colour is in the symbol and the tint (guide §3.10).
struct ToastView: View {
    let toast: ToastMessage

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: Theme.symbol(toast.tone))
                .foregroundStyle(Theme.dot(toast.tone))
                .accessibilityHidden(true)
            Text(toast.text)
                .font(.subheadline)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .floatingGlass(tint: Theme.dot(toast.tone))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
        .onAppear {
            UIAccessibility.post(notification: .announcement, argument: toast.text)
        }
    }
}

/// A non-interactive status capsule (quiet window, offline, app disabled) — the «VPN перезапускается…» pill.
struct StatusPill: View {
    let tone: Tone
    let text: String
    var systemImage: String? = nil
    var showsProgress: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.dot(tone))
            } else {
                Image(systemName: systemImage ?? Theme.symbol(tone))
                    .foregroundStyle(Theme.dot(tone))
                    .accessibilityHidden(true)
            }
            Text(text)
                .font(.footnote.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(Theme.text)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .floatingGlass(tint: Theme.dot(tone))
        .accessibilityElement(children: .combine)
    }
}
