#if !STANDALONE_TESTS && !SWIFT_PACKAGE
import AppKit
import Carbon
import XCTest
@testable import QRSnap

/// Every registration is a fake and every preference store is a disposable suite.
@MainActor final class ShortcutSettingsTests: XCTestCase {
    func testNewInstallDoesNotRegisterUntilExplicitEnable() throws {
        let (storage, defaults, suite) = try storage()
        defer { defaults.removePersistentDomain(forName: suite) }
        let fake = ShortcutRegistrationFake()
        let settings = ShortcutSettingsController(preferences: storage, registration: fake)
        XCTAssertEqual(settings.preferences, ShortcutPreferences())
        XCTAssertEqual(settings.restore(), .disabled)
        XCTAssertTrue(fake.registered.isEmpty)
        XCTAssertNil(defaults.object(forKey: AppPreferences.shortcutStorageKey))
    }

    func testEnabledPhysicalShortcutRestoresFromPersistedPreferences() throws {
        let (storage, defaults, suite) = try storage()
        defer { defaults.removePersistentDomain(forName: suite) }
        let chosen = KeyboardShortcut(keyCode: 17, modifiers: UInt32(controlKey | optionKey))
        let first = ShortcutSettingsController(preferences: storage, registration: ShortcutRegistrationFake())
        XCTAssertEqual(first.apply(ShortcutPreferences(enabled: true, shortcut: chosen)), .registered(chosen))
        first.terminate()
        let fake = ShortcutRegistrationFake()
        let reopened = ShortcutSettingsController(preferences: AppPreferences(defaults: defaults), registration: fake)
        XCTAssertEqual(reopened.restore(), .registered(chosen))
        XCTAssertEqual(fake.registered, [chosen])
        XCTAssertEqual(reopened.preferences.shortcut.keyCode, 17)
    }

    func testDisablePersistsWithoutLosingChosenShortcut() throws {
        let (storage, defaults, suite) = try storage()
        defer { defaults.removePersistentDomain(forName: suite) }
        let fake = ShortcutRegistrationFake()
        let settings = ShortcutSettingsController(preferences: storage, registration: fake)
        let chosen = KeyboardShortcut(keyCode: 1, modifiers: UInt32(controlKey))
        settings.apply(ShortcutPreferences(enabled: true, shortcut: chosen))
        XCTAssertEqual(settings.apply(ShortcutPreferences(enabled: false, shortcut: chosen)), .disabled)
        let reopenedFake = ShortcutRegistrationFake()
        let reopened = ShortcutSettingsController(preferences: storage, registration: reopenedFake)
        XCTAssertEqual(reopened.restore(), .disabled)
        XCTAssertEqual(reopened.preferences.shortcut, chosen)
        XCTAssertTrue(reopenedFake.registered.isEmpty)
        XCTAssertEqual(fake.events.suffix(1), ["unregister"])
    }

    func testCollisionRemainsUnavailableAndDoesNotInvokeScan() throws {
        let (storage, defaults, suite) = try storage()
        defer { defaults.removePersistentDomain(forName: suite) }
        let fake = ShortcutRegistrationFake()
        fake.result = OSStatus(eventHotKeyExistsErr)
        let settings = ShortcutSettingsController(preferences: storage, registration: fake)
        var invocations = 0
        settings.onInvoke = { invocations += 1 }
        let result = settings.apply(ShortcutPreferences(enabled: true))
        XCTAssertEqual(result, .unavailable(OSStatus(eventHotKeyExistsErr)))
        XCTAssertFalse(settings.status.isRegistered)
        XCTAssertTrue(result.message.contains("Scan QR code… from the menu"))
        XCTAssertTrue(storage.loadShortcut().enabled)
        fake.onInvoke?()
        XCTAssertEqual(invocations, 0)
        XCTAssertEqual(fake.events.suffix(1), ["unregister"])
        fake.result = noErr
        XCTAssertEqual(settings.restore(), .registered(.defaultShortcut))
        fake.onInvoke?()
        XCTAssertEqual(invocations, 1)
    }

    func testReplacingShortcutUnregistersOldBindingBeforeNewRegistration() throws {
        let (storage, defaults, suite) = try storage()
        defer { defaults.removePersistentDomain(forName: suite) }
        let fake = ShortcutRegistrationFake()
        let settings = ShortcutSettingsController(preferences: storage, registration: fake)
        settings.apply(ShortcutPreferences(enabled: true))
        fake.events.removeAll()
        let chosen = KeyboardShortcut(keyCode: 8, modifiers: UInt32(optionKey | shiftKey))
        settings.apply(ShortcutPreferences(enabled: true, shortcut: chosen))
        XCTAssertEqual(fake.events, ["unregister", "register"])
        XCTAssertEqual(fake.registered.last, chosen)
        XCTAssertEqual(settings.status, .registered(chosen))
    }

    func testInvalidSettingsPreserveSavedPreferenceAndWorkingRegistration() throws {
        let (storage, defaults, suite) = try storage()
        defer { defaults.removePersistentDomain(forName: suite) }
        let fake = ShortcutRegistrationFake()
        let settings = ShortcutSettingsController(preferences: storage, registration: fake)
        let original = ShortcutPreferences(enabled: true)
        settings.apply(original)
        let events = fake.events
        let invalid = KeyboardShortcut(keyCode: 12, modifiers: UInt32(shiftKey))
        let result = settings.apply(ShortcutPreferences(enabled: true, shortcut: invalid))
        guard case .invalidShortcut = result else { return XCTFail("Expected invalid shortcut") }
        XCTAssertEqual(settings.status, .registered(.defaultShortcut))
        XCTAssertEqual(settings.preferences, original)
        XCTAssertEqual(storage.loadShortcut(), original)
        XCTAssertEqual(fake.events, events)
    }

    func testRecordingSuspendsInvocationAndRestoresSavedRegistration() throws {
        let (storage, defaults, suite) = try storage()
        defer { defaults.removePersistentDomain(forName: suite) }
        let fake = ShortcutRegistrationFake()
        let settings = ShortcutSettingsController(preferences: storage, registration: fake)
        settings.apply(ShortcutPreferences(enabled: true))
        var invocations = 0
        settings.onInvoke = { invocations += 1 }
        settings.beginRecording()
        XCTAssertEqual(settings.status, .recording)
        fake.onInvoke?()
        XCTAssertEqual(invocations, 0)
        XCTAssertEqual(settings.endRecording(), .registered(.defaultShortcut))
        fake.onInvoke?()
        XCTAssertEqual(invocations, 1)
        settings.terminate()
        fake.onInvoke?()
        XCTAssertEqual(invocations, 1)
        XCTAssertTrue(storage.loadShortcut().enabled)
    }

    func testRecordingRestorationReportsConflictInsteadOfClaimingRegistered() throws {
        let (storage, defaults, suite) = try storage()
        defer { defaults.removePersistentDomain(forName: suite) }
        let fake = ShortcutRegistrationFake()
        let settings = ShortcutSettingsController(preferences: storage, registration: fake)
        settings.apply(ShortcutPreferences(enabled: true))
        settings.beginRecording()
        fake.result = OSStatus(eventHotKeyExistsErr)
        XCTAssertEqual(settings.endRecording(), .unavailable(OSStatus(eventHotKeyExistsErr)))
        XCTAssertFalse(settings.status.isRegistered)
    }

    func testEndingRecordingAfterTerminationDoesNotRegisterAgain() throws {
        let (storage, defaults, suite) = try storage()
        defer { defaults.removePersistentDomain(forName: suite) }
        let fake = ShortcutRegistrationFake()
        let settings = ShortcutSettingsController(preferences: storage, registration: fake)
        settings.apply(ShortcutPreferences(enabled: true))
        settings.beginRecording()
        settings.terminate()
        let registrations = fake.registered
        XCTAssertEqual(settings.endRecording(), .disabled)
        XCTAssertEqual(fake.registered, registrations)
    }

    func testMalformedOrUnsafeStoredPreferenceFallsBackToDisabled() throws {
        let (storage, defaults, suite) = try storage()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("invalid".utf8), forKey: AppPreferences.shortcutStorageKey)
        XCTAssertEqual(storage.loadShortcut(), ShortcutPreferences())
        let unsafe = ShortcutPreferences(enabled: true, shortcut: KeyboardShortcut(keyCode: 12, modifiers: 0))
        defaults.set(try JSONEncoder().encode(unsafe), forKey: AppPreferences.shortcutStorageKey)
        let fake = ShortcutRegistrationFake()
        let settings = ShortcutSettingsController(preferences: storage, registration: fake)
        XCTAssertEqual(settings.restore(), .disabled)
        XCTAssertTrue(fake.registered.isEmpty)
        XCTAssertFalse(storage.saveShortcut(unsafe))
    }

    func testShortcutValidationProtectsOrdinaryTypingAndSystemScreenshotKeys() {
        XCTAssertNotNil(KeyboardShortcut(keyCode: 12, modifiers: 0).validationMessage)
        XCTAssertNotNil(KeyboardShortcut(keyCode: 12, modifiers: UInt32(shiftKey)).validationMessage)
        XCTAssertNotNil(KeyboardShortcut(keyCode: 53, modifiers: UInt32(controlKey)).validationMessage)
        XCTAssertNotNil(KeyboardShortcut(keyCode: 56, modifiers: UInt32(controlKey)).validationMessage)
        XCTAssertNotNil(KeyboardShortcut(keyCode: 12, modifiers: UInt32(controlKey | alphaLock)).validationMessage)
        for keyCode in [UInt32(20), 21, 23] {
            XCTAssertNotNil(KeyboardShortcut(keyCode: keyCode, modifiers: UInt32(cmdKey | shiftKey)).validationMessage)
            XCTAssertNotNil(KeyboardShortcut(keyCode: keyCode, modifiers: UInt32(cmdKey | shiftKey | optionKey)).validationMessage)
        }
        XCTAssertNil(KeyboardShortcut.defaultShortcut.validationMessage)
        XCTAssertEqual(KeyboardShortcut.defaultShortcut.displayName, "⌃⇧Q")
        XCTAssertNil(KeyboardShortcut(keyCode: 123, modifiers: UInt32(optionKey)).validationMessage)
    }

    func testHiddenSettingsWindowAppliesPreferenceAndShowsConflictFallback() throws {
        let (storage, defaults, suite) = try storage()
        defer { defaults.removePersistentDomain(forName: suite) }
        let fake = ShortcutRegistrationFake()
        fake.result = OSStatus(eventHotKeyExistsErr)
        let settings = ShortcutSettingsController(preferences: storage, registration: fake)
        let controller = SettingsWindowController(settings: settings)
        defer { controller.close() }
        var applied: ShortcutRegistrationStatus?
        controller.onApply = { applied = $0 }
        controller.show(activate: false)
        let enabled = try XCTUnwrap(find("settings-shortcut-enabled", in: controller.window?.contentView) as? NSButton)
        XCTAssertEqual(enabled.state, .off)
        enabled.performClick(nil)
        let apply = try XCTUnwrap(find("settings-apply", in: controller.window?.contentView) as? NSButton)
        apply.performClick(nil)
        XCTAssertEqual(applied, .unavailable(OSStatus(eventHotKeyExistsErr)))
        let status = try XCTUnwrap(find("settings-shortcut-status", in: controller.window?.contentView) as? NSTextField)
        XCTAssertTrue(status.stringValue.contains("Shortcut unavailable"))
        XCTAssertTrue(status.stringValue.contains("Scan QR code… from the menu"))
        XCTAssertTrue(storage.loadShortcut().enabled)
    }

    func testClosingSettingsDiscardsUnappliedPreferenceChanges() throws {
        let (storage, defaults, suite) = try storage()
        defer { defaults.removePersistentDomain(forName: suite) }
        let fake = ShortcutRegistrationFake()
        let settings = ShortcutSettingsController(preferences: storage, registration: fake)
        let controller = SettingsWindowController(settings: settings)
        defer { controller.close() }
        controller.show(activate: false)
        let enabled = try XCTUnwrap(find("settings-shortcut-enabled", in: controller.window?.contentView) as? NSButton)
        enabled.performClick(nil)
        controller.close()
        controller.show(activate: false)
        XCTAssertEqual(enabled.state, .off)
        XCTAssertFalse(storage.loadShortcut().enabled)
        XCTAssertTrue(fake.registered.isEmpty)
    }

    private func storage() throws -> (AppPreferences, UserDefaults, String) {
        let suite = "QRSnap-ShortcutSettingsTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        return (AppPreferences(defaults: defaults), defaults, suite)
    }

    private func find(_ id: String, in view: NSView?) -> NSView? {
        guard let view else { return nil }
        if view.identifier?.rawValue == id { return view }
        return view.subviews.lazy.compactMap { self.find(id, in: $0) }.first
    }
}

@MainActor private final class ShortcutRegistrationFake: ShortcutRegistering {
    var onInvoke: (() -> Void)?
    var result: OSStatus = noErr
    var registered: [KeyboardShortcut] = []
    var events: [String] = []

    func register(_ shortcut: KeyboardShortcut) -> OSStatus {
        events.append("register")
        registered.append(shortcut)
        return result
    }

    func unregister() { events.append("unregister") }
}
#endif
