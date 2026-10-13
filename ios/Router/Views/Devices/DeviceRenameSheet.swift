import SwiftUI
import RouterCore

/// «Переименовать» (contract-stage4 §5.3.2): one text field and only a «Сохранить» button — nothing is saved
/// on dismiss, blur or the keyboard's return key. Prefill: own name or the DHCP name; placeholder: the DHCP
/// name or «Имя устройства». Typing drops control characters and stops at 40 characters. Empty → `""`
/// removes the own name. Works while the router is offline (server-only, no dialog).
struct DeviceRenameSheet: View {
    @Environment(RouterStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let mac: String
    @State private var text = ""
    @State private var loaded = false
    @State private var fieldError: String? = nil
    @FocusState private var focused: Bool

    var body: some View {
        let detail = store.deviceDetail(mac: mac)
        let action = detail.renameAction(text)
        let busy = store.isRunning(named: "rename")
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header(detail)
                TextField(detail.renamePlaceholder, text: $text)
                    .focused($focused)
                    .submitLabel(.done)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled()
                    .disabled(busy)
                    .fieldBackground()
                    .accessibilityLabel("Имя устройства")
                    .onSubmit {
                        focused = false
                    }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(DeviceTexts.renameFooter)
                        .font(.footnote)
                        .foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Text("\(text.unicodeScalars.count)/\(Validation.renameMaxLength)")
                        .font(.footnote)
                        .monospacedDigit()
                        .foregroundStyle(Theme.dim)
                        .accessibilityLabel("Символов: \(text.unicodeScalars.count) из \(Validation.renameMaxLength)")
                }
                if let error = fieldError {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.err)
                        .fixedSize(horizontal: false, vertical: true)
                }
                AppButton(title: DeviceTexts.save, systemImage: "checkmark", kind: .primary, isBusy: busy) {
                    save(action)
                }
                .disabled(!store.canPerform(action))
                .padding(.top, 4)
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .sheetSurface()
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(busy)
        .onAppear {
            if !loaded {
                loaded = true
                text = Validation.limitRenameInput(detail.renamePrefill)
                focused = true
            }
        }
        .onChange(of: text) { _, newValue in
            let limited = Validation.limitRenameInput(newValue)
            if limited != newValue {
                text = limited
            }
            fieldError = nil
        }
    }

    private func header(_ detail: DeviceDetail) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                Image(systemName: "pencil")
                    .font(.title2)
                    .foregroundStyle(Theme.acc)
                    .accessibilityHidden(true)
                Text(DeviceTexts.rename)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Theme.text)
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Text(detail.mac)
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(Theme.dim)
                .accessibilityLabel("MAC " + detail.mac)
        }
    }

    private func save(_ action: RouterAction) {
        focused = false
        fieldError = nil
        let close = dismiss
        store.perform(action, label: store.deviceActionLabel(mac: mac), symbol: "pencil") { result in
            switch result {
            case .done, .job:
                close()
            case .failed(let error):
                if error.code == "too_long" {
                    fieldError = error.userMessage
                }
            case .cancelled:
                break
            }
        }
    }
}
