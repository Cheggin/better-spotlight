import AppKit

/// Triggers when the user presses left and right Command keys at the same time.
/// Uses NSEvent.flagsChanged with device-specific bits in modifierFlags.rawValue:
///   NX_DEVICELCMDKEYMASK = 0x08
///   NX_DEVICERCMDKEYMASK = 0x10
final class DualCmdMonitor {
    private let onTrigger: () -> Void
    private let simultaneityWindow: TimeInterval = 0.20

    private var monitor: Any?
    private var leftDownAt: Date?
    private var rightDownAt: Date?
    private var armed = true

    private let leftCmdBit:  UInt = 0x08
    private let rightCmdBit: UInt = 0x10

    init(onTrigger: @escaping () -> Void) { self.onTrigger = onTrigger }

    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
        }
        Log.info("dual-cmd monitor started", category: "app")
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) {
        let raw = event.modifierFlags.rawValue
        let left  = (raw & leftCmdBit)  != 0
        let right = (raw & rightCmdBit) != 0
        let now = Date()

        // Reject if any non-cmd modifier is also pressed.
        let nonCmd = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting(.command)
        guard nonCmd.isEmpty else { return }

        if left  && leftDownAt  == nil { leftDownAt  = now }
        if right && rightDownAt == nil { rightDownAt = now }

        // Both keys released → re-arm.
        if !left && !right {
            leftDownAt = nil
            rightDownAt = nil
            armed = true
            return
        }

        guard armed, let l = leftDownAt, let r = rightDownAt else { return }
        let delta = abs(l.timeIntervalSince(r))
        if delta <= simultaneityWindow {
            armed = false
            Log.info("dual-cmd fired (Δ=\(Int(delta * 1000))ms)", category: "app")
            DispatchQueue.main.async { [weak self] in self?.onTrigger() }
        }
    }
}
