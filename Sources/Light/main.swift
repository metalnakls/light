import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var timer: Timer?
    private var isLightOn = LightState.read()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.imagePosition = .imageOnly
        statusItem.button?.toolTip = nil
        statusItem.menu = makeMenu()

        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURL(event:replyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleStateChanged),
            name: LightState.changedNotification,
            object: nil
        )

        updateStatus()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.reloadStatus()
        }
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        return menu
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func handleURL(event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor) {
        guard
            let rawURL = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
            let url = URL(string: rawURL)
        else {
            return
        }

        let command = url.host?.lowercased()
            ?? url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()

        switch command {
        case "on":
            setLight(on: true)
        case "off":
            setLight(on: false)
        case "toggle":
            setLight(on: !isLightOn)
        default:
            break
        }
    }

    private func setLight(on: Bool) {
        isLightOn = on
        LightState.write(on)
        updateStatus()
    }

    @objc private func handleStateChanged() {
        reloadStatus()
    }

    private func reloadStatus() {
        let savedState = LightState.read()
        guard savedState != isLightOn else { return }
        isLightOn = savedState
        updateStatus()
    }

    private func updateStatus() {
        if isLightOn {
            statusItem.isVisible = true
            statusItem.button?.image = LightIcon.make(color: .systemYellow)
            statusItem.button?.setAccessibilityLabel("Light on")
        } else {
            statusItem.isVisible = false
            statusItem.button?.image = nil
        }
    }
}

enum LightState {
    static let changedNotification = Notification.Name("local.light.state.changed")

    static var stateURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Light/state", isDirectory: false)
    }

    static func read() -> Bool {
        guard let state = try? String(contentsOf: stateURL, encoding: .utf8) else {
            return false
        }

        return state.trimmingCharacters(in: .whitespacesAndNewlines) == "on"
    }

    static func write(_ isOn: Bool) {
        let directory = stateURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? (isOn ? "on\n" : "off\n").write(to: stateURL, atomically: true, encoding: .utf8)
        DistributedNotificationCenter.default().post(name: changedNotification, object: nil)
    }
}

@main
enum LightApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}

enum LightIcon {
    static func make(color: NSColor) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)

        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.clear.setFill()
        NSRect(origin: .zero, size: size).fill()

        let glowRect = NSRect(x: 2, y: 2, width: 14, height: 14)
        color.withAlphaComponent(0.25).setFill()
        NSBezierPath(ovalIn: glowRect).fill()

        let lightRect = NSRect(x: 5, y: 5, width: 8, height: 8)
        color.setFill()
        NSBezierPath(ovalIn: lightRect).fill()

        color.blended(withFraction: 0.35, of: .white)?.setStroke()
        let stroke = NSBezierPath(ovalIn: lightRect.insetBy(dx: 0.5, dy: 0.5))
        stroke.lineWidth = 1
        stroke.stroke()

        image.isTemplate = false
        return image
    }
}
