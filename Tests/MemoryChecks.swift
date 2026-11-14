import AppKit
import Darwin

// Offline integration test: no AppDelegate, VPN monitoring, probes, hotkeys,
// login registration, or updater startup. Only synthetic model changes.
@main
struct MemoryChecks {
    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let vpn = VPNController(monitoring: false)
        let health = TunnelHealth()
        let settings = SettingsWindowController(vpn: vpn, health: health)
        autoreleasepool {
            settings.loadContent()
            settings.window?.contentView?.layoutSubtreeIfNeeded()
        }
        vpn.applyStatus(.connected)

        func drain() {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.0001))
        }
        func footprint() -> Int64 {
            var info = task_vm_info_data_t()
            var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
            let result = withUnsafeMutablePointer(to: &info) { pointer in
                pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
                }
            }
            precondition(result == KERN_SUCCESS)
            return Int64(info.phys_footprint)
        }
        // Exercise steady polling with settings loaded, then real changes while closed.
        for closed in [false, true] {
            if closed { settings.window?.close() }
            var baseline: Int64 = 0
            for batch in 0..<4 {
                for index in 0..<1000 {
                    autoreleasepool {
                        vpn.applyStatus(closed && index % 2 == 0 ? .disconnected : .connected)
                        health.publish(failed: closed && index % 2 == 0,
                                       detail: closed ? "Offline test \(index % 2)" : "Connected")
                        drain()
                    }
                }
                let memory = footprint()
                print("\(closed ? "closed changes" : "unchanged polls") batch=\(batch) footprint=\(memory)")
                fflush(stdout)
                if batch == 0 { baseline = memory }
                if batch == 3 {
                    precondition(memory - baseline < 4 * 1024 * 1024,
                                 "Settings observation memory grows across repeated updates")
                }
            }
        }
        autoreleasepool { settings.loadContent() }
        for _ in 0..<30 {
            weak var host: NSViewController?
            // Deliver the delegate event directly: this offscreen test never orders
            // the window front again, so repeated NSWindow.close() calls are no-ops.
            autoreleasepool {
                host = settings.window?.contentViewController
                settings.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: settings.window))
            }
            for _ in 0..<10 { drain() }
            precondition(settings.window?.contentViewController == nil, "Closed settings must detach their graph")
            precondition(host == nil, "Closed hosting controller must be released")
            autoreleasepool {
                settings.loadContent()
                settings.window?.contentView?.layoutSubtreeIfNeeded()
            }
        }
        settings.window?.close()
        print("Passed: bounded settings memory and 30 settings teardown/recreate cycles")
    }
}
