import Carbon

@MainActor protocol ShortcutRegistering: AnyObject {
    var onInvoke: (() -> Void)? { get set }
    func register(_ shortcut: KeyboardShortcut) -> OSStatus
    func unregister()
}

enum ShortcutRegistrationStatus: Equatable {
    case disabled
    case registered(KeyboardShortcut)
    case unavailable(OSStatus)
    case invalidShortcut(String)
    case recording

    var isRegistered: Bool {
        if case .registered = self { return true }
        return false
    }

    var message: String {
        switch self {
        case .disabled: return "Global shortcut is off. Use Scan QR code… from the menu."
        case .registered(let shortcut): return "\(shortcut.displayName) is registered. Some system or application conflicts may still take precedence."
        case .unavailable(let status): return "Shortcut unavailable (status \(status)). Another app or macOS may reserve it. Choose another shortcut or use Scan QR code… from the menu."
        case .invalidShortcut(let reason): return reason
        case .recording: return "Press your shortcut now. Escape cancels."
        }
    }
}

/// Separates the saved preference from whether an exclusive registration actually succeeded.
@MainActor final class ShortcutSettingsController {
    private let storage: AppPreferences
    private let registration: any ShortcutRegistering
    private var recording = false
    private(set) var preferences: ShortcutPreferences
    private(set) var status: ShortcutRegistrationStatus = .disabled
    var onInvoke: (() -> Void)?

    init(preferences: AppPreferences = AppPreferences(), registration: any ShortcutRegistering = GlobalShortcut()) {
        storage = preferences
        self.registration = registration
        self.preferences = preferences.loadShortcut()
        registration.onInvoke = { [weak self] in
            guard let self, self.status.isRegistered else { return }
            self.onInvoke?()
        }
    }

    @discardableResult func restore() -> ShortcutRegistrationStatus {
        preferences = storage.loadShortcut()
        recording = false
        return registerSavedPreference()
    }

    @discardableResult func apply(_ value: ShortcutPreferences) -> ShortcutRegistrationStatus {
        guard let error = value.shortcut.validationMessage else {
            storage.saveShortcut(value)
            preferences = value
            recording = false
            return registerSavedPreference()
        }
        // Invalid input never replaces a working registration or the last saved preference.
        return .invalidShortcut(error)
    }

    func beginRecording() {
        guard !recording else { return }
        recording = true
        registration.unregister()
        status = .recording
    }

    @discardableResult func endRecording() -> ShortcutRegistrationStatus {
        guard recording else { return status }
        recording = false
        return registerSavedPreference()
    }

    func terminate() {
        recording = false
        registration.unregister()
        status = .disabled
    }

    private func registerSavedPreference() -> ShortcutRegistrationStatus {
        registration.unregister()
        guard preferences.enabled else { status = .disabled; return status }
        let result = registration.register(preferences.shortcut)
        if result == noErr {
            status = .registered(preferences.shortcut)
        } else {
            registration.unregister()
            status = .unavailable(result)
        }
        return status
    }
}
