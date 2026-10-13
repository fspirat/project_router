import SwiftUI
import RouterCore

// Small building blocks of the «Обход» tab (local to this folder).

/// A state line: level dot + text with an optional bold part + an optional small counter.
/// The level is also read out as a word (colour alone is not enough).
struct BypassStatusLine: View {
    let tone: Tone
    let summary: String
    var bold: String? = nil
    var counter: String? = nil
    var showsProgress: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if showsProgress {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.dot(tone))
                    .accessibilityHidden(true)
            } else {
                // A view without text sits with its bottom on the baseline: the dot centres on the x-height.
                ToneDot(tone: tone, size: 10)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(attributed)
                    .font(.subheadline)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let counter = counter {
                    Text(counter)
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Theme.dim)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var attributed: AttributedString {
        var text = AttributedString(summary)
        if let bold = bold, !bold.isEmpty, let range = text.range(of: bold) {
            text[range].inlinePresentationIntent = .stronglyEmphasized
        }
        return text
    }

    private var accessibilityText: String {
        var parts = [Theme.levelWord(tone), summary]
        if let counter = counter {
            parts.append(counter)
        }
        return parts.joined(separator: ", ")
    }
}

/// A system toggle that never flips by itself: it always shows the **server** value (`isOn`); a tap only
/// asks for the change (`onRequest` → `store.perform`, which shows the server's 428 confirm). The switch moves
/// after the router has applied it and the next read says so (contract-stage4 §5.4.1).
struct ConfirmToggle: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    let isOn: Bool
    var isBusy: Bool = false
    let isEnabled: Bool
    var accessibilityHint: String = "Изменение нужно будет подтвердить"
    let onRequest: @MainActor () -> Void

    var body: some View {
        Toggle(isOn: request) {
            HStack(alignment: .center, spacing: 12) {
                if let systemImage = systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(Theme.dim)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle = subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(Theme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Выполняется")
                }
            }
        }
        .tint(Theme.acc)
        .frame(minHeight: 44)
        .disabled(!isEnabled)
        .accessibilityHint(accessibilityHint)
    }

    /// Reads the server value; a tap that would change it asks for the action instead of storing anything.
    private var request: Binding<Bool> {
        let current = isOn
        let ask = onRequest
        return Binding(
            get: {
                current
            },
            set: { @MainActor newValue in
                if newValue != current {
                    ask()
                }
            }
        )
    }
}

/// «Повтори через N с» while one of `actions` is locked (429 `retry_after`, PW lock-out, verification).
struct BypassLockNote: View {
    @Environment(RouterStore.self) private var store
    let actions: [RouterAction]

    var body: some View {
        if actions.contains(where: { store.isLocked($0) }) {
            TimelineView(.periodic(from: Date(), by: 1)) { context in
                let left = actions.map { store.lockSecondsLeft($0, now: context.date) }.max() ?? 0
                if left > 0 {
                    Label("Повтори через \(left)" + Fmt.nbsp + "с", systemImage: "hourglass")
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Theme.dim)
                }
            }
        }
    }
}

/// The read error of one kind inside its card (router 502/504 only from the 2nd failure in a row).
struct BypassReadError: View {
    @Environment(RouterStore.self) private var store
    let kind: ReadKind

    var body: some View {
        if let message = store.readError(kind) {
            Banner(tone: .err, text: message, symbol: "exclamationmark.triangle.fill")
        }
    }
}

/// A small caption under a control.
struct BypassCaption: View {
    let text: String
    var systemImage: String? = nil

    init(_ text: String, systemImage: String? = nil) {
        self.text = text
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let systemImage = systemImage {
                Image(systemName: systemImage)
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.footnote)
        .foregroundStyle(Theme.dim)
    }
}
