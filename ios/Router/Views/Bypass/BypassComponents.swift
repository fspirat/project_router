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
        // A neutral state (off, not installed) has no level word: «проверяется» would be wrong there. The loading
        // state (spinner) keeps it.
        var parts: [String] = []
        if tone != .neutral || showsProgress {
            parts.append(Theme.levelWord(tone))
        }
        parts.append(summary)
        if let counter = counter {
            parts.append(counter)
        }
        return parts.joined(separator: ", ")
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
