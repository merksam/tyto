import Carbon.HIToolbox
import Foundation

/// System-wide hotkey via Carbon's RegisterEventHotKey. Needs no Accessibility permission and is
/// still undeprecated in the macOS 27 SDK. One Carbon event handler is installed for the whole
/// app; hotkeys are looked up by id.
final class GlobalHotkey {
    static let defaultKeyCode = UInt32(kVK_ANSI_9)
    static let defaultModifiers = UInt32(cmdKey | shiftKey)

    private static var registry: [UInt32: GlobalHotkey] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false

    private let id: UInt32
    private var hotKeyRef: EventHotKeyRef?
    let action: () -> Void

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        id = Self.nextID
        Self.nextID += 1
        Self.installHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: 0x4F574C31 /* 'OWL1' */, id: id)
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status == noErr {
            Self.registry[id] = self
        } else {
            Log.app.error("RegisterEventHotKey failed: \(status)")
        }
    }

    func unregister() {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        hotKeyRef = nil
        Self.registry[id] = nil
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hk = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hk)
            // Carbon dispatches on the main run loop.
            MainActor.assumeIsolated {
                GlobalHotkey.registry[hk.id]?.action()
            }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
