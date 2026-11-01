import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let vpn = VPNController()
    private var statusItem: NSStatusItem!
    private let indicator = Indicator()
    private let health = TunnelHealth()
    private var appearanceTimer: Timer?
    private lazy var settings = SettingsWindowController(vpn: vpn, health: health)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Updates.shared.start()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        vpn.onChange = { [weak self] in self?.health.refresh(); self?.updateStatus() }
        health.onChange = { [weak self] in self?.updateStatus() }
        health.start(vpn: vpn)
        NSAppleEventManager.shared().setEventHandler(self, andSelector: #selector(handleURL(event:replyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
        Hotkeys.shared.onToggle = { [weak self] in self?.vpn.toggle() }
        Hotkeys.shared.onOpen = { [weak self] in self?.vpn.openShadowrocket() }
        Hotkeys.shared.start()
        appearanceTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard self.statusItem.isVisible else { return }
                await self.indicator.sample(near: self.statusItem.button)
                self.updateStatus()
            }
        }
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
        statusItem.button?.image = indicator.image(failed: vpn.state == .failed || health.failed, transitioning: vpn.state == .connecting || vpn.state == .disconnecting)
        statusItem.button?.toolTip = vpn.error ?? (vpn.state == .connected ? health.detail : vpn.state.description)
        statusItem.button?.setAccessibilityLabel("VPN: \(vpn.state.description). \(vpn.state == .connected ? health.detail : "") Click to disconnect; right-click for settings.")
    }
}

@main
enum LightApp {
    @MainActor static func main() {
        // Exercise dyld and all linked frameworks without creating windows or touching the VPN.
        if CommandLine.arguments.contains("--self-check") {
            print("Light runtime loaded")
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

