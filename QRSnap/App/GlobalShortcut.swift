import AppKit
import Carbon

@MainActor final class GlobalShortcut {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onInvoke: (() -> Void)?

    func register() -> OSStatus {
        unregister()
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr, identifier.signature == 0x5152534E, identifier.id == 1 else {
                return OSStatus(eventNotHandledErr)
            }
            MainActor.assumeIsolated {
                Unmanaged<GlobalShortcut>.fromOpaque(userData).takeUnretainedValue().onInvoke?()
            }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard installed == noErr else { return installed }
        let status = RegisterEventHotKey(UInt32(kVK_ANSI_Q), UInt32(controlKey | shiftKey),
                                         EventHotKeyID(signature: 0x5152534E, id: 1),
                                         GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &hotKey)
        if status != noErr { unregister() }
        return status
    }

    func unregister() {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        hotKey = nil
        handler = nil
    }
}
