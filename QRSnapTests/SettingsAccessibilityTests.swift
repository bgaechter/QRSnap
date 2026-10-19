#if !STANDALONE_TESTS && !SWIFT_PACKAGE
import AppKit
import Carbon
import XCTest
@testable import QRSnap

/// Real hidden AppKit controls receive synthetic key events. Global registration,
/// local event monitoring and accessibility announcements use injected boundaries.
@MainActor final class SettingsAccessibilityTests: XCTestCase {
    func testInitialFocusAndKeyboardTraversalReachEverySettingsControl() throws {
        let fixture = try SettingsAccessibilityFixture()
        defer { fixture.close() }
        let window = try XCTUnwrap(fixture.controller.window)
        let controls = try ["settings-shortcut-enabled", "settings-record", "settings-default", "settings-apply"]
            .map { try button($0, in: fixture) }
        XCTAssertTrue(fixture.effects.announcements.isEmpty)
        XCTAssertTrue(window.initialFirstResponder === controls[0])
        XCTAssertTrue(window.makeFirstResponder(controls[0]))
        for index in controls.indices {
            XCTAssertTrue(controls[index].acceptsFirstResponder)
            XCTAssertTrue(window.firstResponder === controls[index])
            controls[index].keyDown(with: key(48, "\t", in: window))
            XCTAssertTrue(window.firstResponder === controls[(index + 1) % controls.count])
        }
        controls[0].keyDown(with: key(48, "\t", flags: .shift, in: window))
        XCTAssertTrue(window.firstResponder === controls.last)
    }

    func testSpaceChangesEnablementAndReturnAppliesWithConflictAnnouncement() throws {
        let fixture = try SettingsAccessibilityFixture()
        defer { fixture.close() }
        let window = try XCTUnwrap(fixture.controller.window)
        fixture.registration.result = OSStatus(eventHotKeyExistsErr)
        let enabled = try button("settings-shortcut-enabled", in: fixture)
        enabled.keyDown(with: key(49, " ", in: window))
        XCTAssertEqual(enabled.state, .on)
        XCTAssertFalse(fixture.storage.loadShortcut().enabled)
        XCTAssertTrue(try XCTUnwrap(fixture.effects.announcements.last).contains("Apply to save"))
        XCTAssertTrue(window.performKeyEquivalent(with: key(36, "\r", in: window)))
        XCTAssertTrue(fixture.storage.loadShortcut().enabled)
        XCTAssertEqual(fixture.settings.status, .unavailable(OSStatus(eventHotKeyExistsErr)))
        XCTAssertEqual(fixture.effects.applied, [.unavailable(OSStatus(eventHotKeyExistsErr))])
        XCTAssertTrue(try XCTUnwrap(fixture.effects.announcements.last).contains("Shortcut unavailable"))
        XCTAssertTrue(try XCTUnwrap(fixture.effects.announcements.last).contains("Scan QR code… from the menu"))
        XCTAssertEqual(try label("settings-shortcut-status", in: fixture).stringValue, fixture.effects.announcements.last)
    }

    func testEscapeAndCommandWCloseWithoutApplyingDraftChanges() throws {
        for closeKey in [(UInt16(53), "\u{1b}", NSEvent.ModifierFlags()), (13, "w", .command)] {
            let fixture = try SettingsAccessibilityFixture()
            defer { fixture.close() }
            let window = try XCTUnwrap(fixture.controller.window)
            try button("settings-shortcut-enabled", in: fixture).keyDown(with: key(49, " ", in: window))
            XCTAssertTrue(window.performKeyEquivalent(with: key(closeKey.0, closeKey.1, flags: closeKey.2, in: window)))
            XCTAssertEqual(fixture.effects.closedWindows, 1)
            XCTAssertFalse(fixture.storage.loadShortcut().enabled)
            XCTAssertTrue(fixture.effects.applied.isEmpty)
            fixture.controller.show(activate: false)
            XCTAssertEqual(try button("settings-shortcut-enabled", in: fixture).state, .off)
        }
    }

    func testRecordingConsumesReturnAndEscapeRestoresShortcutBeforeClosing() throws {
        let fixture = try SettingsAccessibilityFixture(preferences: ShortcutPreferences(enabled: true))
        defer { fixture.close() }
        let window = try XCTUnwrap(fixture.controller.window)
        let record = try button("settings-record", in: fixture)
        XCTAssertTrue(window.makeFirstResponder(record))
        record.keyDown(with: key(49, " ", in: window))
        XCTAssertEqual(fixture.settings.status, .recording)
        XCTAssertEqual(fixture.monitor.installs, 1)
        XCTAssertEqual(fixture.effects.announcements.last, "Press your shortcut now. Escape cancels.")
        for id in ["settings-shortcut-enabled", "settings-default", "settings-apply"] {
            let disabled = try button(id, in: fixture)
            XCTAssertFalse(disabled.isEnabled)
            XCTAssertFalse(disabled.acceptsFirstResponder)
        }
        fixture.effects.applied.removeAll()
        fixture.monitor.send(key(36, "\r", in: window))
        XCTAssertEqual(fixture.settings.status, .recording)
        XCTAssertTrue(fixture.effects.applied.isEmpty)
        XCTAssertTrue(try XCTUnwrap(fixture.effects.announcements.last).contains("Escape cancels"))
        fixture.monitor.send(key(53, "\u{1b}", in: window))
        XCTAssertEqual(fixture.monitor.removals, 1)
        XCTAssertEqual(fixture.effects.closedWindows, 0)
        XCTAssertEqual(fixture.settings.status, .registered(.defaultShortcut))
        XCTAssertTrue(window.firstResponder === record)
        XCTAssertTrue(try XCTUnwrap(fixture.effects.announcements.last).contains("Shortcut recording cancelled"))
        XCTAssertTrue(window.performKeyEquivalent(with: key(53, "\u{1b}", in: window)))
        XCTAssertEqual(fixture.effects.closedWindows, 1)
    }

    func testRecordedShortcutAnnouncesDraftAndReturnPersistsIt() throws {
        let fixture = try SettingsAccessibilityFixture(preferences: ShortcutPreferences(enabled: true))
        defer { fixture.close() }
        let window = try XCTUnwrap(fixture.controller.window)
        let chosen = KeyboardShortcut(keyCode: 17, modifiers: UInt32(controlKey | optionKey))
        try button("settings-record", in: fixture).keyDown(with: key(49, " ", in: window))
        fixture.monitor.send(key(17, "t", flags: [.control, .option], in: window))
        XCTAssertEqual(fixture.monitor.removals, 1)
        XCTAssertEqual(fixture.storage.loadShortcut().shortcut, .defaultShortcut)
        XCTAssertEqual(try label("settings-shortcut-value", in: fixture).stringValue, chosen.displayName)
        XCTAssertEqual(fixture.effects.announcements.last, "\(chosen.displayName) selected. Apply to save your changes.")
        XCTAssertTrue(window.performKeyEquivalent(with: key(36, "\r", in: window)))
        XCTAssertEqual(fixture.storage.loadShortcut(), ShortcutPreferences(enabled: true, shortcut: chosen))
        XCTAssertEqual(fixture.settings.status, .registered(chosen))
        XCTAssertEqual(fixture.effects.announcements.last, fixture.settings.status.message)
    }

    func testCancellingRecordingAnnouncesFailureToRestorePreviousRegistration() throws {
        let fixture = try SettingsAccessibilityFixture(preferences: ShortcutPreferences(enabled: true))
        defer { fixture.close() }
        let window = try XCTUnwrap(fixture.controller.window)
        try button("settings-record", in: fixture).keyDown(with: key(49, " ", in: window))
        fixture.registration.result = OSStatus(eventHotKeyExistsErr)
        fixture.monitor.send(key(53, "\u{1b}", in: window))
        XCTAssertEqual(fixture.settings.status, .unavailable(OSStatus(eventHotKeyExistsErr)))
        XCTAssertTrue(try XCTUnwrap(fixture.effects.announcements.last).contains("Shortcut unavailable"))
        XCTAssertEqual(fixture.storage.loadShortcut(), ShortcutPreferences(enabled: true))
    }

    func testRecordingLossOfFocusRemovesMonitorAndIgnoresLateKeys() throws {
        let fixture = try SettingsAccessibilityFixture(preferences: ShortcutPreferences(enabled: true))
        defer { fixture.close() }
        let window = try XCTUnwrap(fixture.controller.window)
        try button("settings-record", in: fixture).keyDown(with: key(49, " ", in: window))
        let lateKey = try XCTUnwrap(fixture.monitor.receive)
        fixture.controller.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: window))
        let announcements = fixture.effects.announcements
        XCTAssertEqual(fixture.monitor.removals, 1)
        XCTAssertEqual(fixture.settings.status, .registered(.defaultShortcut))
        lateKey(17, [.control, .option], false)
        XCTAssertEqual(try label("settings-shortcut-value", in: fixture).stringValue, KeyboardShortcut.defaultShortcut.displayName)
        XCTAssertEqual(fixture.effects.announcements, announcements)
        XCTAssertEqual(fixture.storage.loadShortcut(), ShortcutPreferences(enabled: true))
    }

    func testSpaceRestoresDefaultOnlyAfterReturnAppliesIt() throws {
        let chosen = KeyboardShortcut(keyCode: 17, modifiers: UInt32(controlKey | optionKey))
        let original = ShortcutPreferences(enabled: true, shortcut: chosen)
        let fixture = try SettingsAccessibilityFixture(preferences: original)
        defer { fixture.close() }
        let window = try XCTUnwrap(fixture.controller.window)
        try button("settings-default", in: fixture).keyDown(with: key(49, " ", in: window))
        XCTAssertEqual(fixture.effects.announcements.last, "Default shortcut selected. Apply to save your changes.")
        XCTAssertEqual(fixture.storage.loadShortcut(), original)
        XCTAssertTrue(window.performKeyEquivalent(with: key(36, "\r", in: window)))
        XCTAssertEqual(fixture.storage.loadShortcut(), ShortcutPreferences(enabled: true))
    }

    private func key(_ code: UInt16, _ characters: String, flags: NSEvent.ModifierFlags = [], in window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                        windowNumber: window.windowNumber, context: nil, characters: characters,
                        charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    }

    private func find(_ id: String, in view: NSView?) -> NSView? {
        guard let view else { return nil }
        if view.identifier?.rawValue == id { return view }
        return view.subviews.lazy.compactMap { self.find(id, in: $0) }.first
    }

    private func button(_ id: String, in fixture: SettingsAccessibilityFixture) throws -> NSButton {
        try XCTUnwrap(find(id, in: fixture.controller.window?.contentView) as? NSButton)
    }

    private func label(_ id: String, in fixture: SettingsAccessibilityFixture) throws -> NSTextField {
        try XCTUnwrap(find(id, in: fixture.controller.window?.contentView) as? NSTextField)
    }
}

@MainActor private final class SettingsAccessibilityFixture {
    let storage: AppPreferences
    let settings: ShortcutSettingsController
    let controller: SettingsWindowController
    let registration: SettingsKeyboardRegistrationFake
    let monitor: SettingsRecordingMonitorFake
    let effects: SettingsAccessibilityEffects
    private let defaults: UserDefaults
    private let suite: String
    private var closeObserver: NSObjectProtocol?

    init(preferences: ShortcutPreferences = ShortcutPreferences()) throws {
        _ = NSApplication.shared
        let suite = "QRSnap-SettingsAccessibilityTests-\(UUID().uuidString)"
        self.suite = suite
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        self.defaults = defaults
        let storage = AppPreferences(defaults: defaults)
        self.storage = storage
        storage.saveShortcut(preferences)
        let registration = SettingsKeyboardRegistrationFake()
        self.registration = registration
        let monitor = SettingsRecordingMonitorFake()
        self.monitor = monitor
        let effects = SettingsAccessibilityEffects()
        self.effects = effects
        let settings = ShortcutSettingsController(preferences: storage, registration: registration)
        self.settings = settings
        settings.restore()
        let controller = SettingsWindowController(settings: settings, announce: { effects.announcements.append($0) },
                                                  recordingMonitor: monitor.boundary)
        self.controller = controller
        controller.onApply = { effects.applied.append($0) }
        controller.show(activate: false)
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                                               object: controller.window, queue: .main) { _ in
            MainActor.assumeIsolated { effects.closedWindows += 1 }
        }
    }

    func close() {
        controller.close()
        settings.terminate()
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        defaults.removePersistentDomain(forName: suite)
    }
}

@MainActor private final class SettingsAccessibilityEffects {
    var announcements: [String] = []
    var applied: [ShortcutRegistrationStatus] = []
    var closedWindows = 0
}

@MainActor private final class SettingsKeyboardRegistrationFake: ShortcutRegistering {
    var onInvoke: (() -> Void)?
    var result: OSStatus = noErr
    func register(_ shortcut: KeyboardShortcut) -> OSStatus { result }
    func unregister() {}
}

@MainActor private final class SettingsRecordingMonitorFake {
    var receive: (@MainActor (UInt16, NSEvent.ModifierFlags, Bool) -> Void)?
    var installs = 0
    var removals = 0

    var boundary: SettingsWindowController.RecordingMonitor {
        .init { _, receive in
            self.installs += 1
            self.receive = receive
            return {
                self.removals += 1
                self.receive = nil
            }
        }
    }

    func send(_ event: NSEvent) { receive?(event.keyCode, event.modifierFlags, event.isARepeat) }
}
#endif
