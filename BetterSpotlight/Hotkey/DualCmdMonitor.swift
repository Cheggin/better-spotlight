import AppKit
import CoreGraphics
import ApplicationServices

/// Triggers when the user presses left and right Command keys at the same
/// time. Uses a `CGEventTap` (system-level event hook) instead of
/// `NSEvent.addGlobalMonitorForEvents` because the latter drops events when
/// our app isn't frontmost and is unreliable in practice.
///
/// Requires the Accessibility permission. We prompt for it on `start()`
/// and log a clear warning if the tap can't be installed.
final class DualCmdMonitor {
    private let onTrigger: () -> Void
    private let simultaneityWindow: TimeInterval = 0.20

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private var leftDownAt: Date?
    private var rightDownAt: Date?
    private var armed = true

    // Device-dependent shift bits in CGEventFlags (NX_DEVICE{L,R}CMDKEYMASK).
    private let leftCmdBit:  UInt64 = 0x08
    private let rightCmdBit: UInt64 = 0x10

    init(onTrigger: @escaping () -> Void) { self.onTrigger = onTrigger }

    func start() {
        // Force the Accessibility permission prompt up-front. Without it,
        // CGEventTap creation silently returns nil.
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(opts)
        Log.info("dual-cmd monitor: AX trusted = \(trusted)", category: "app")

        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo = userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<DualCmdMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                monitor.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: userInfo
        ) else {
            Log.error("dual-cmd monitor: CGEventTap creation failed — Accessibility permission required",
                      category: "app")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.tap = tap
        self.runLoopSource = source
        Log.info("dual-cmd monitor started (CGEventTap)", category: "app")
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        tap = nil
        runLoopSource = nil
    }

    private func handle(type: CGEventType, event: CGEvent) {
        // The tap may get disabled by the system (timeout / user input). Re-enable.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard type == .flagsChanged else { return }

        let raw = event.flags.rawValue
        let left  = (raw & leftCmdBit)  != 0
        let right = (raw & rightCmdBit) != 0
        let now = Date()

        // Reject when any non-cmd device-independent modifier is held.
        let nonCmd = event.flags.subtracting([.maskCommand, .maskNonCoalesced])
        // CGEventFlags is a bit field that includes some kernel housekeeping
        // bits; we just need to make sure no other USER modifier is on.
        let userOther: CGEventFlags = [.maskShift, .maskAlphaShift, .maskControl,
                                       .maskAlternate, .maskSecondaryFn, .maskHelp]
        if !event.flags.intersection(userOther).isEmpty { return }
        _ = nonCmd

        if left  && leftDownAt  == nil { leftDownAt  = now }
        if right && rightDownAt == nil { rightDownAt = now }

        // Both released → re-arm.
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
