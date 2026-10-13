import SwiftUI
import RouterCore

/// «Защита» (contract-stage4 §5.6.1, §1.3).
///
/// - «Face ID при открытии»: turning it on needs a successful Face ID first; turning it off does not.
/// - «Блокировать»: сразу / 1 мин / 5 мин (only with the lock on).
/// - «Face ID для опасных действий» (default on): turning it off is itself protected by Face ID.
/// - «Скрывать в переключателе приложений» (default **off**): the app-switcher snapshot shows the logo instead
///   of the screen. The lock on return works as configured either way (`AppLock`).
/// The method name follows the iPhone (Face ID / Touch ID / код-пароль).
struct SettingsSecuritySection: View {
    let bio: BiometricInfo
    @AppStorage(AppSettings.lockOnOpenKey) private var lockOnOpen = false
    @AppStorage(AppSettings.lockDelayKey) private var lockDelay = 0
    @AppStorage(AppSettings.biometricForDangerKey) private var biometricForDanger = true
    @AppStorage(AppSettings.hideInSwitcherKey) private var hideInSwitcher = SwitcherPrivacy.defaultValue
    /// Face ID is being asked for one of the toggles (the toggle shows the requested value meanwhile).
    @State private var lockPendingOn = false
    @State private var dangerPendingOff = false

    private var authBusy: Bool {
        return lockPendingOn || dangerPendingOff
    }

    var body: some View {
        Section {
            Toggle(isOn: lockBinding) {
                Label(bio.title + " при открытии", systemImage: bio.symbol)
            }
            .tint(Theme.acc)
            // Without a passcode the lock cannot be turned on, but a lock left on can still be turned off.
            .disabled((!bio.canAuthenticate && !lockOnOpen) || authBusy)

            lockDelayRow

            Toggle(isOn: dangerBinding) {
                Label(bio.title + " для опасных действий", systemImage: "exclamationmark.shield")
            }
            .tint(Theme.acc)
            .disabled(authBusy)

            Toggle(isOn: $hideInSwitcher) {
                Label(SettingsTexts.hideInSwitcherTitle, systemImage: "eye.slash")
            }
            .tint(Theme.acc)
        } header: {
            Text("Защита")
        } footer: {
            footer
        }
        .listRowBackground(Theme.card)
    }

    private var lockDelayRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(SettingsTexts.lockAfter)
                .foregroundStyle(lockOnOpen ? Theme.text : Theme.dim)
                .accessibilityHidden(true)
            SegmentedPicker(
                title: SettingsTexts.lockAfter,
                selection: $lockDelay,
                options: [
                    SegmentOption(0, "Сразу"),
                    SegmentOption(60, "1 мин"),
                    SegmentOption(300, "5 мин")
                ]
            )
            .accessibilityHint(lockOnOpen ? "Через сколько времени в фоне приложение снова спросит \(bio.method)." : "Сначала включи «\(bio.title) при открытии».")
        }
        .padding(.vertical, 2)
        .disabled(!lockOnOpen)
    }

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !bio.canAuthenticate {
                Text("На iPhone не задан код-пароль — блокировка приложения недоступна.")
            }
            Text(SettingsTexts.faceIDForActionsFooter)
            Text(SettingsTexts.hideInSwitcherFooter)
        }
    }

    // MARK: - Bindings (keep the stored value until Face ID answers)

    private var lockBinding: Binding<Bool> {
        return Binding(
            get: { lockOnOpen || lockPendingOn },
            set: { newValue in
                lockToggleChanged(newValue)
            }
        )
    }

    private var dangerBinding: Binding<Bool> {
        return Binding(
            get: { biometricForDanger && !dangerPendingOff },
            set: { newValue in
                dangerToggleChanged(newValue)
            }
        )
    }

    /// Turning the lock on needs a successful Face ID first; turning it off does not.
    private func lockToggleChanged(_ newValue: Bool) {
        if authBusy || newValue == lockOnOpen {
            return
        }
        if !newValue {
            lockOnOpen = false
            return
        }
        lockPendingOn = true
        Task { @MainActor in
            let ok = await BiometricGate.authenticate(reason: SettingsTexts.unlockReason)
            if ok {
                lockOnOpen = true
            }
            lockPendingOn = false
        }
    }

    /// Turning Face ID for dangerous actions off is itself protected by Face ID.
    private func dangerToggleChanged(_ newValue: Bool) {
        if authBusy || newValue == biometricForDanger {
            return
        }
        if newValue {
            biometricForDanger = true
            return
        }
        dangerPendingOff = true
        Task { @MainActor in
            let ok = await BiometricGate.confirmDangerous(reason: "Отключить \(bio.method) для опасных действий")
            if ok {
                biometricForDanger = false
            }
            dangerPendingOff = false
        }
    }
}
