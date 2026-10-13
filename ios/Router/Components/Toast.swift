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
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .task(id: store.toast?.id) { [store] in
            await store.autoDismissToast()
        }
    }
}

struct ToastView: View {
    let toast: ToastMessage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: Theme.symbol(toast.tone))
                .foregroundStyle(Theme.dot(toast.tone))
                .accessibilityHidden(true)
            Text(toast.text)
                .font(.subheadline)
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raise, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.ring(toast.tone), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.18), radius: 12, x: 0, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
        .onAppear {
            UIAccessibility.post(notification: .announcement, argument: toast.text)
        }
    }
}
