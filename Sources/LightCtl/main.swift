import AppKit
import Foundation

let command = CommandLine.arguments.dropFirst().first?.lowercased() ?? "toggle"
guard ["on", "off", "toggle", "settings", "shadowrocket"].contains(command) else {
    fputs("usage: lightctl on|off|toggle|settings|shadowrocket\n", stderr)
    exit(64)
}
// URL dispatch discovers the installed app, regardless of its installation folder.
guard let url = URL(string: "light://\(command)"), NSWorkspace.shared.open(url) else {
    fputs("lightctl: install and open Light.app once to register its controls\n", stderr)
    exit(1)
}
