import AppKit
import Carbon

// Disposable second process for the explicit G0 exclusive-registration check.
// It observes no keys and synthesizes no input. --hold retains the registration
// until Return so the app's collision UI can be exercised.
let app = NSApplication.shared
var hotKey: EventHotKeyRef?
let status = RegisterEventHotKey(UInt32(kVK_ANSI_Q), UInt32(controlKey | shiftKey),
                                 EventHotKeyID(signature: 0x47305052, id: 1),
                                 GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &hotKey)
print("Exclusive Control-Shift-Q registration status: \(status)")
if status == noErr, CommandLine.arguments.contains("--hold") {
    print("Holding synthetic conflict; press Return to release.")
    _ = readLine()
}
if let hotKey { print("Unregister status: \(UnregisterEventHotKey(hotKey))") }
