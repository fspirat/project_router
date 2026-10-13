import SwiftUI
import RouterCore

/// Settings (sheet from the gear on every tab; contract-stage4 §5.6, replaces stage 3 §7.9).
///
/// Sections in the order of the spec and the mock-up: Защита (incl. the stage 4 toggle «Скрывать в переключателе
/// приложений», default off), Этот телефон, Доступ к роутеру (`/devices`: phones, browsers, login journal),
/// Выход, Тема, Ссылки, О приложении.
///
/// Style: a system `Form` (iOS 26 draws the sheet and its controls as Liquid Glass; no glass inside the sheet's
/// content — glass on glass), rows on the `card` colour, the sheet's own background left to the system.
/// Everything here talks to the server only, so it all works while the router is offline.
struct SettingsView: View {
    @Environment(RouterStore.self) var store
    @Environment(\.dismiss) var dismiss
    @State private var bio = BiometricInfo.unknown
    @State private var now = Date()
    @State private var confirmLogout = false
    @State private var loggingOut = false
    @State private var showRevokeAll = false
    @State private var revokeTarget: PhoneRow? = nil

    var body: some View {
        NavigationStack {
            Form {
                SettingsSecuritySection(bio: bio)
                SettingsPhoneSection()
                SettingsAccessSection(now: now) { row in
                    revokeTarget = row
                }
                logoutSection
                SettingsThemeSection()
                SettingsLinksSection()
                SettingsAboutSection()
            }
            .sheetFormBackground()
            .refreshable { [store, kinds = store.settingsKinds] in
                await store.refresh(kinds)
            }
            .navigationTitle("Настройки")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog(SettingsTexts.logoutTitle, isPresented: $confirmLogout, titleVisibility: .visible) {
                Button(SettingsTexts.logoutConfirm, role: .destructive) {
                    logout()
                }
                Button("Отмена", role: .cancel) {}
            } message: {
                Text(SettingsTexts.logoutText)
            }
            .alert(
                revokeTarget.map { AccessTexts.revokeTitle($0.name) } ?? "",
                isPresented: revokeDialogShown,
                presenting: revokeTarget
            ) { row in
                Button(AccessTexts.revokeButton, role: .destructive) {
                    store.revokePhone(row)
                }
                Button("Отмена", role: .cancel) {}
            } message: { _ in
                Text(AccessTexts.revokeText)
            }
        }
        // On the stack (not the Form): pushing «Браузеры» / «Журнал входов» keeps the scope, no extra reads.
        .pollingScope(store.settingsKinds)
        .appSheet(isPresented: $showRevokeAll) {
            RevokeAllSheet()
        }
        .onAppear {
            bio = BiometricInfo.current()
            now = Date()
        }
        .task { [store] in
            // Stage 3: `/me` on every open (name, expiry dates).
            await store.read(.me)
        }
        .task {
            // «был в сети N мин назад» stays fresh while the sheet is open.
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 60_000_000_000)
                } catch {
                    break
                }
                now = Date()
            }
        }
    }

    // MARK: - Выход (contract-stage4 §5.6.5)

    private var logoutSection: some View {
        Section {
            Button(role: .destructive) {
                confirmLogout = true
            } label: {
                HStack {
                    Label(SettingsTexts.logoutButton, systemImage: "rectangle.portrait.and.arrow.right")
                    if loggingOut {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(loggingOut)
            Button(role: .destructive) {
                showRevokeAll = true
            } label: {
                HStack {
                    Label(AccessTexts.revokeAllRow, systemImage: "person.2.slash")
                    if store.isRevokeAllBusy {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(loggingOut || store.appDisabled)
        } header: {
            Text("Выход")
        } footer: {
            Text("«Выйти везде» отзывает доступ у всех телефонов с приложением, и у этого тоже; по желанию — и у всех браузеров.")
        }
        .listRowBackground(Theme.card)
    }

    private var revokeDialogShown: Binding<Bool> {
        return Binding(
            get: { revokeTarget != nil },
            set: { shown in
                if !shown {
                    revokeTarget = nil
                }
            }
        )
    }

    private func logout() {
        loggingOut = true
        Task {
            await store.logoutFromSettings()
            loggingOut = false
        }
    }
}

/// Face ID / Touch ID / passcode availability, read once when Settings opens (each read creates an LAContext).
struct BiometricInfo: Equatable {
    var canAuthenticate: Bool
    /// `BiometricGate.methodName`: «Face ID», «Touch ID» or «код-пароль».
    var method: String

    static let unknown = BiometricInfo(canAuthenticate: true, method: "Face ID")

    static func current() -> BiometricInfo {
        return BiometricInfo(canAuthenticate: BiometricGate.canAuthenticate, method: BiometricGate.methodName)
    }

    /// For the start of a label: «Face ID», «Touch ID», «Код-пароль».
    var title: String {
        if method == "код-пароль" {
            return "Код-пароль"
        }
        return method
    }

    var symbol: String {
        switch method {
        case "Face ID":
            return "faceid"
        case "Touch ID":
            return "touchid"
        default:
            return "lock"
        }
    }
}
