import SwiftUI
import RouterCore

/// «Расписание: <имя>» (contract-stage4 §5.3.3; web `sched-dlg`): two 24-hour pickers in router time
/// (Europe/Samara), «Сохранить» → `schedule` (428 medium; red button + warning line when the window is active
/// right now), «Убрать расписание» → no dialog, «Отмена» closes.
struct DeviceScheduleSheet: View {
    @Environment(RouterStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let mac: String
    @State private var offTime = Date()
    @State private var onTime = Date()
    @State private var loaded = false

    var body: some View {
        let detail = store.deviceDetail(mac: mac)
        let window = DeviceScheduleClock.window(off: offTime, on: onTime)
        let saveAction = window.action(mac: detail.mac)
        let clearAction = RouterAction.scheduleClear(mac: detail.mac)
        let clearing = store.isRunning(clearAction)
        let saving = store.isRunning(named: "schedule") && !clearing
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                DeviceScheduleHeader(title: ScheduleTexts.title(detail.title))
                Text(ScheduleTexts.text)
                    .font(.body)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                pickers
                Label(ScheduleTexts.caption, systemImage: "clock")
                    .font(.footnote)
                    .foregroundStyle(Theme.dim)
                hints(window)
                GlassGroup(axis: .vertical, spacing: 10) {
                    AppButton(title: ScheduleTexts.save, systemImage: "checkmark", kind: .primary, isBusy: saving) {
                        save(window, detail: detail)
                    }
                    .disabled(window.hasSameTimes || !store.canPerform(saveAction))
                    if detail.sched != nil {
                        AppButton(title: ScheduleTexts.clear, systemImage: "trash", kind: .destructiveOutline, isBusy: clearing) {
                            clear(clearAction)
                        }
                        .disabled(!store.canPerform(clearAction))
                    }
                    AppButton(title: ScheduleTexts.cancel, kind: .secondary) {
                        dismiss()
                    }
                    .disabled(saving || clearing)
                }
                .padding(.top, 4)
                LockCountdownNote(actions: [saveAction])
            }
            .padding(20)
        }
        .sheetSurface()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(saving || clearing)
        .onAppear {
            if !loaded {
                loaded = true
                let initial = ScheduleWindow.initial(for: detail.sched)
                offTime = DeviceScheduleClock.date(hour: initial.offHour, minute: initial.offMinute)
                onTime = DeviceScheduleClock.date(hour: initial.onHour, minute: initial.onMinute)
            }
        }
    }

    private var pickers: some View {
        VStack(spacing: 0) {
            DeviceTimeRow(title: ScheduleTexts.offLabel, symbol: "moon", selection: $offTime)
            LineDivider()
            DeviceTimeRow(title: ScheduleTexts.onLabel, symbol: "sun.max", selection: $onTime)
        }
        .padding(.horizontal, 12)
        .modifier(TileSurface())
    }

    @ViewBuilder
    private func hints(_ window: ScheduleWindow) -> some View {
        if window.hasSameTimes {
            Label(ScheduleTexts.sameTime, systemImage: "exclamationmark.circle.fill")
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.err)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            TimelineView(.periodic(from: Date(), by: 30)) { context in
                if window.isActive(now: context.date.timeIntervalSince1970) {
                    Label(ScheduleTexts.activeNowWarning, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func save(_ window: ScheduleWindow, detail: DeviceDetail) {
        guard window.isValid else {
            return
        }
        // Decided at the tap (minute resolution, Samara time): an active window → warning line + red button.
        let activeNow = window.isActive(now: Date().timeIntervalSince1970)
        let close = dismiss
        store.perform(
            window.action(mac: detail.mac),
            label: store.deviceActionLabel(mac: detail.mac),
            note: activeNow ? ScheduleTexts.activeNowWarning : nil,
            destructive: activeNow,
            symbol: "timer"
        ) { result in
            if result.isSuccess {
                close()
            }
        }
    }

    private func clear(_ action: RouterAction) {
        let close = dismiss
        store.perform(action, label: store.deviceActionLabel(mac: mac), symbol: "timer") { result in
            if result.isSuccess {
                close()
            }
        }
    }
}

private struct DeviceScheduleHeader: View {
    let title: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "timer")
                .font(.title2)
                .foregroundStyle(Theme.acc)
                .accessibilityHidden(true)
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// «Выключать в  23:00»: a compact 24-hour picker in router time.
private struct DeviceTimeRow: View {
    let title: String
    let symbol: String
    @Binding var selection: Date

    var body: some View {
        DatePicker(selection: $selection, displayedComponents: .hourAndMinute) {
            Label(title, systemImage: symbol)
                .foregroundStyle(Theme.text)
        }
        .environment(\.timeZone, DeviceScheduleClock.timeZone)
        .environment(\.locale, DeviceScheduleClock.locale)
        .environment(\.calendar, DeviceScheduleClock.calendar)
        .frame(minHeight: 52)
    }
}

/// Picker dates ↔ router wall-clock `HHMM` (Europe/Samara, whatever zone the iPhone is in).
enum DeviceScheduleClock {
    static let timeZone: TimeZone = Fmt.samaraTimeZone
    /// Russian, 24-hour.
    static let locale = Locale(identifier: "ru_RU")

    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        c.locale = locale
        return c
    }

    /// Today (Samara) at `hour:minute`.
    static func date(hour: Int, minute: Int) -> Date {
        let cal = calendar
        let start = cal.startOfDay(for: Date())
        return cal.date(bySettingHour: hour, minute: minute, second: 0, of: start) ?? start
    }

    /// The window the two pickers show.
    static func window(off: Date, on: Date) -> ScheduleWindow {
        let cal = calendar
        let a = cal.dateComponents([.hour, .minute], from: off)
        let b = cal.dateComponents([.hour, .minute], from: on)
        return ScheduleWindow(offHour: a.hour ?? 0, offMinute: a.minute ?? 0, onHour: b.hour ?? 0, onMinute: b.minute ?? 0)
    }
}
