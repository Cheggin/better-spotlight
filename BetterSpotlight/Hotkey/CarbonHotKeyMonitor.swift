import Carbon
import Foundation

/// Global hotkey backed by the system hotkey API. This does not require
/// Accessibility permission.
final class CarbonHotKeyMonitor {
    private let onTrigger: () -> Void
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    init(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger
    }

    func start() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                let monitor = Unmanaged<CarbonHotKeyMonitor>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                DispatchQueue.main.async {
                    Log.info("option-shift-space fired", category: "app")
                    Log.info("hotkey option-shift-space fired", category: "timing")
                    monitor.onTrigger()
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &handlerRef
        )
        guard handlerStatus == noErr else {
            Log.error("option-shift-space handler failed: \(handlerStatus)", category: "app")
            return
        }

        let hotKeyID = EventHotKeyID(signature: fourCharCode("BSPT"), id: 1)
        let hotKeyStatus = RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(optionKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if hotKeyStatus == noErr {
            Log.info("option-shift-space registered", category: "app")
            Log.info("hotkey option-shift-space registered", category: "timing")
        } else {
            Log.error("option-shift-space registration failed: \(hotKeyStatus)", category: "app")
            Log.error("hotkey option-shift-space registration failed: \(hotKeyStatus)",
                      category: "timing")
        }
    }

    func stop() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
        }
        hotKeyRef = nil
        handlerRef = nil
    }
}

private func fourCharCode(_ value: String) -> OSType {
    value.utf8.reduce(0) { ($0 << 8) + OSType($1) }
}
