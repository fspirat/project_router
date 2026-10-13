import SwiftUI
import RouterCore

/// «Выйти везде — телефоны и браузеры» (contract-stage4 §5.6.5, §3.3): first this app sheet with the toggle
/// «Также закрыть все сессии веб-панели» (default off), then «Продолжить» → `POST /devices/revoke-all {"web"}`
/// → the server's 428 (critical: red button, Face ID) on top of this sheet → 200 → LOGOUT with the banner.
/// The store runs everything after «Продолжить»; this sheet stays open under the dialog, so «Отмена» there
/// returns here. Works offline (server-only).
struct RevokeAllSheet: View {
    @Environment(RouterStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettings.biometricForDangerKey) private var biometricForDanger = true
    @State private var includeWeb = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label {
                        Text("Доступ отзывается у всех телефонов с приложением, и у этого тоже. Войти заново — пароль и число в Telegram.")
                            .foregroundStyle(Theme.text)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "person.2.slash")
                            .foregroundStyle(Theme.err)
                    }
                    Toggle(AccessTexts.revokeAllToggle, isOn: $includeWeb)
                        .tint(Theme.acc)
                        .disabled(busy)
                } footer: {
                    Text(includeWeb
                         ? "Каждый браузер снова попросит код из Telegram."
                         : "Сессии веб-панели останутся открытыми.")
                }
                .listRowBackground(Theme.card)

                Section {
                    Button(role: .destructive) {
                        store.revokeEverywhere(includeWeb: includeWeb)
                    } label: {
                        HStack {
                            Text(AccessTexts.revokeAllContinue)
                                .fontWeight(.semibold)
                            Spacer()
                            if busy {
                                ProgressView()
                            }
                        }
                    }
                    .disabled(busy || !store.canPerform(.revokeAll(web: includeWeb)))
                } footer: {
                    Text(biometricForDanger ? "Дальше — подтверждение и \(BiometricGate.methodName)." : "Дальше — подтверждение.")
                }
                .listRowBackground(Theme.card)
            }
            .sheetFormBackground()
            .navigationTitle("Выйти везде")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        dismiss()
                    }
                    .disabled(busy)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(busy)
    }

    private var busy: Bool {
        return store.isRevokeAllBusy
    }
}
