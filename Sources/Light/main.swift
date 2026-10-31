import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let vpn = VPNController()
    private var statusItem: NSStatusItem!
    private lazy var settings = SettingsWindowController(vpn: vpn)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        vpn.onChange = { [weak self] in self?.updateStatus() }
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURL(event:replyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
        updateStatus()
        if !UserDefaults.standard.bool(forKey: "hasOpenedSettings") { showSettings() }
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp || NSApp.currentEvent?.modifierFlags.contains(.control) == true {
            showSettings()
        } else { vpn.disconnect() }
    }

    @objc func showSettings() {
        UserDefaults.standard.set(true, forKey: "hasOpenedSettings")
        settings.showWindow(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    @objc private func handleURL(event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor) {
        guard let raw = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: raw), url.scheme?.lowercased() == "light" else { return }
        switch url.host?.lowercased() {
        case "on": vpn.connect()
        case "off": vpn.disconnect()
        case "toggle": vpn.toggle()
        case "shadowrocket": vpn.openShadowrocket()
        case "settings": showSettings()
        default: break
        }
    }

    func updateStatus() {
        statusItem.isVisible = vpn.state != .disconnected && vpn.state != .unavailable
        statusItem.button?.image = LightIcon.make(color: vpn.state == .failed ? .systemRed : .systemYellow)
        statusItem.button?.toolTip = vpn.error ?? vpn.state.description
        statusItem.button?.setAccessibilityLabel("VPN: \(vpn.state.description). Click to disconnect; right-click for settings.")
    }
}

@main
enum LightApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

enum LightIcon {
    static func make(color: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: 5, y: 5, width: 8, height: 8)).fill()
        image.unlockFocus()
        image.isTemplate = false
        return image
    }
}
