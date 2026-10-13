import UIKit

/// Hides the keyboard of whatever text field is focused (no reference to the field needed).
enum Keyboard {
    @MainActor
    static func dismiss() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}
