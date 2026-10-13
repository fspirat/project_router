import SwiftUI
import RouterCore

/// «Сайты без VPN» — the PassWall rule MyDirect (contract-stage4 §5.4.6, port of app.js:604-636).
///
/// - «Добавленные» (from the panel or the app): each with «Убрать» → `dirdel` → server 428 with a red button.
/// - «Весь список (N)»: read-only, collapsed, searchable; the first 60 matches.
/// - «Добавить сайт»: the domain is normalized and checked on the phone (server regex), then `diradd` → 428.
/// - `/mydirect` `500 no rule`: the message replaces the lists; add/remove are not offered.
/// Buttons only — no swipe-to-delete.
struct MyDirectCard: View {
    @Environment(RouterStore.self) private var store
    @State private var query = ""
    @State private var showsAll = false

    var body: some View {
        let info = store.myDirectInfo(query: query)
        let ruleMissing = store.myDirectRuleMissing
        Card {
            CardHeader(MyDirectTexts.title, symbol: "globe") {
                if let info = info, !ruleMissing {
                    Text(info.countText)
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Theme.dim)
                }
            }
            Text("Эти сайты открываются без VPN на всех устройствах дома.")
                .font(.footnote)
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
            if ruleMissing {
                Banner(tone: .err, text: noRuleText, symbol: "exclamationmark.triangle.fill")
            } else if let info = info {
                BypassReadError(kind: .mydirect)
                MyDirectAddedSection(rows: info.added, emptyText: info.addedEmptyText)
                LineDivider()
                MyDirectAllSection(info: info, query: $query, isExpanded: $showsAll)
                LineDivider()
                MyDirectAddSection()
            } else if store.readError(.mydirect) != nil {
                BypassReadError(kind: .mydirect)
            } else {
                EmptyStateView(
                    title: store.offline ? RouterStore.bypassOfflineEmpty : ZapretTexts.loading,
                    systemImage: store.offline ? "wifi.slash" : "hourglass"
                )
            }
        }
    }

    private var noRuleText: String {
        let message = store.readError(.mydirect) ?? ""
        return message.isEmpty ? ActionErrorPolicy.noRuleHint : message + " " + ActionErrorPolicy.noRuleHint
    }
}

// MARK: - Added

private struct MyDirectAddedSection: View {
    let rows: [MyDirectRow]
    let emptyText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(MyDirectTexts.addedTitle)
            if let emptyText = emptyText {
                EmptyStateView(title: emptyText, systemImage: "tray")
            } else {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        LineDivider()
                    }
                    MyDirectAddedRow(row: row)
                }
            }
        }
    }
}

private struct MyDirectAddedRow: View {
    @Environment(RouterStore.self) private var store
    let row: MyDirectRow

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "globe")
                .foregroundStyle(Theme.dim)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(row.domain)
                .font(.body)
                .foregroundStyle(Theme.text)
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if let action = row.removeAction {
                Button {
                    store.perform(action, label: row.domain, symbol: "trash")
                } label: {
                    HStack(spacing: 4) {
                        if store.isRunning(action) || store.isConfirming(action) {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(MyDirectTexts.remove)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(Theme.err)
                }
                .removeButtonStyle()
                .disabled(!store.myDirectEditable || !store.canPerform(action))
                .accessibilityLabel(MyDirectTexts.remove + " " + row.domain)
                .accessibilityHint("Сайт снова пойдёт через VPN. Нужно будет подтвердить")
            }
        }
        .frame(minHeight: 44)
    }
}

private extension View {
    /// «Убрать»: one non-glass red bordered capsule for every list length (a long list never gets glass per
    /// row, and the control does not change its look as the list grows). Regular size: ~34–36 pt in a 44-pt row.
    func removeButtonStyle() -> some View {
        self
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.regular)
            .tint(Theme.err)
    }
}

// MARK: - Whole list

private struct MyDirectAllSection: View {
    let info: MyDirectInfo
    @Binding var query: String
    @Binding var isExpanded: Bool

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                SearchField(text: $query, prompt: MyDirectTexts.searchPlaceholder)
                    .padding(.top, 8)
                if let notFound = info.notFoundText {
                    EmptyStateView(title: notFound, systemImage: "magnifyingglass")
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(info.found) { row in
                            MyDirectListRow(row: row)
                        }
                    }
                }
                if let more = info.moreText {
                    BypassCaption(more)
                }
            }
        } label: {
            Text(info.allTitle)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.text)
        }
        .tint(Theme.dim)
    }
}

/// A read-only entry («geosite:…» and other prefixed entries shown as is).
private struct MyDirectListRow: View {
    let row: MyDirectRow

    var body: some View {
        HStack(spacing: 8) {
            Text(row.domain)
                .font(.subheadline)
                .foregroundStyle(MyDirect.isPrefixed(row.domain) ? Theme.dim : Theme.text)
                .lineLimit(2)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if row.isAdded {
                ToneChip(text: MyDirectTexts.addedTag, tone: .info)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Add

private struct MyDirectAddSection: View {
    @Environment(RouterStore.self) private var store
    @State private var input = ""
    @State private var hint: String? = nil
    @State private var hintTone: Tone = .err
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(MyDirectTexts.addTitle)
            TextField(MyDirectTexts.placeholder, text: $input)
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($isFocused)
                .onSubmit(add)
                .fieldBackground()
                .accessibilityLabel("Домен сайта")
                .onChange(of: input) { _, _ in
                    hint = nil
                }
            if let hint = hint {
                Label(hint, systemImage: hintTone == .err ? "exclamationmark.circle" : "info.circle")
                    .font(.footnote)
                    .foregroundStyle(Theme.levelText(hintTone))
                    .fixedSize(horizontal: false, vertical: true)
            }
            AppButton(title: MyDirectTexts.addTitle, systemImage: "plus", kind: .secondary, isBusy: isBusy) {
                add()
            }
            .disabled(!canAdd)
            LockCountdownNote(actions: [probe])
        }
    }

    /// Any `diradd` (locks are per action name).
    private var probe: RouterAction {
        return .diradd(domain: "example.com")
    }

    private var canAdd: Bool {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        return !text.isEmpty && store.myDirectEditable && store.canPerform(probe)
    }

    private var isBusy: Bool {
        if case .diradd? = store.runningAction?.action {
            return true
        }
        if case .diradd? = store.pendingConfirm?.action {
            return true
        }
        return false
    }

    /// app.js:622 normalization + the server regex on the phone; never send what the server would reject.
    private func add() {
        guard canAdd else {
            return
        }
        switch MyDirect.check(input, list: store.mydirect) {
        case .invalid(let text):
            hintTone = .err
            hint = text
        case .alreadyListed(let text):
            hintTone = .info
            hint = text
        case .ok(let domain):
            isFocused = false
            store.perform(.diradd(domain: domain), label: domain, symbol: "plus.circle") { result in
                if result.isSuccess {
                    input = ""
                    hint = nil
                }
            }
        }
    }
}
