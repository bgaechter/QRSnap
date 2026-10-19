import Foundation
import Carbon

/// Physical key codes are intentionally independent of the active keyboard layout.
struct KeyboardShortcut: Codable, Equatable, Sendable {
    let keyCode: UInt32
    let modifiers: UInt32

    static let defaultShortcut = KeyboardShortcut(keyCode: 12, modifiers: UInt32(controlKey | shiftKey))
    static let allowedModifiers = UInt32(controlKey | optionKey | cmdKey | shiftKey)

    var validationMessage: String? {
        guard Self.keyNames[keyCode] != nil else { return "Choose a letter, number, punctuation, arrow, Space or function key." }
        guard modifiers & ~Self.allowedModifiers == 0,
              modifiers & UInt32(controlKey | optionKey | cmdKey) != 0 else {
            return "Include Control, Option or Command. Shift alone is not enough."
        }
        // Never take over the system's screenshot keys, including variants with extra modifiers.
        if [UInt32(20), 21, 23].contains(keyCode), modifiers & UInt32(cmdKey | shiftKey) == UInt32(cmdKey | shiftKey) {
            return "Choose a shortcut other than a macOS screenshot shortcut."
        }
        return nil
    }

    var displayName: String {
        var result = ""
        for (mask, symbol) in [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")] {
            if modifiers & UInt32(mask) != 0 { result += symbol }
        }
        return result + (Self.keyNames[keyCode] ?? "Unknown key")
    }

    // Labels describe a US keyboard's physical positions, not interpreted key events.
    private static let keyNames: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B",
        12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4",
        22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "−", 28: "8", 29: "0", 30: "]", 31: "O",
        32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\",
        43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 49: "Space", 50: "`",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11", 109: "F10",
        111: "F12", 118: "F4", 120: "F2", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑"
    ]
}

struct ShortcutPreferences: Codable, Equatable, Sendable {
    var enabled: Bool = false
    var shortcut: KeyboardShortcut = .defaultShortcut
}

/// Stores only the user's shortcut choice. No scan data or key-event text is persisted.
@MainActor final class AppPreferences {
    static let shortcutStorageKey = "shortcutSettings.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func loadShortcut() -> ShortcutPreferences {
        guard let data = defaults.data(forKey: Self.shortcutStorageKey),
              let value = try? JSONDecoder().decode(ShortcutPreferences.self, from: data),
              value.shortcut.validationMessage == nil else { return ShortcutPreferences() }
        return value
    }

    @discardableResult func saveShortcut(_ value: ShortcutPreferences) -> Bool {
        guard value.shortcut.validationMessage == nil,
              let data = try? JSONEncoder().encode(value) else { return false }
        defaults.set(data, forKey: Self.shortcutStorageKey)
        return true
    }
}
