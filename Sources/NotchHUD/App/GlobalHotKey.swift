import AppKit
import Carbon.HIToolbox

/// System-wide hotkey via Carbon RegisterEventHotKey. Unlike an NSEvent global
/// key monitor this needs no Accessibility / Input Monitoring grant, and it
/// fires even though NotchHUD is an accessory app that is never active.
@MainActor
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: @MainActor () -> Void

    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping @MainActor () -> Void) {
        self.action = action

        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let installed = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                // Carbon delivers application-target events on the main thread.
                MainActor.assumeIsolated { hotKey.action() }
                return noErr
            },
            1,
            &spec,
            Unmanaged.passUnretained(self).toOpaque(),
            &handlerRef
        )
        guard installed == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: 0x4E48_4844 /* "NHHD" */, id: 1)
        let registered = RegisterEventHotKey(
            keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef
        )
        guard registered == noErr else {
            NSLog("NotchHUD could not register the global hotkey (OSStatus %d)", registered)
            return nil
        }
    }
}
