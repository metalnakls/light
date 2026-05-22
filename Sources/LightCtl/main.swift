import AppKit
import Foundation

enum LightCtl {
    static let changedNotification = Notification.Name("local.light.state.changed")

    static var stateURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Light/state", isDirectory: false)
    }

    static func main() {
        let command = CommandLine.arguments.dropFirst().first?.lowercased() ?? "toggle"
        let nextState: Bool

        switch command {
        case "on":
            nextState = true
        case "off":
            nextState = false
        case "toggle":
            nextState = !read()
        default:
            fputs("usage: lightctl on|off|toggle\n", stderr)
            Foundation.exit(64)
        }

        write(nextState)
        launchAgent()
    }

    static func read() -> Bool {
        guard let state = try? String(contentsOf: stateURL, encoding: .utf8) else {
            return false
        }

        return state.trimmingCharacters(in: .whitespacesAndNewlines) == "on"
    }

    static func write(_ isOn: Bool) {
        let directory = stateURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try (isOn ? "on\n" : "off\n").write(to: stateURL, atomically: true, encoding: .utf8)
        } catch {
            fputs("lightctl: failed to write state: \(error.localizedDescription)\n", stderr)
            Foundation.exit(1)
        }

        DistributedNotificationCenter.default().post(name: changedNotification, object: nil)
    }

    static func launchAgent() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-gj", "/Applications/Utilities/Light.app"]
        try? process.run()
    }
}

LightCtl.main()
