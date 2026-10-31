import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    init(vpn: VPNController) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 540),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = "Light Settings"
        window.toolbarStyle = .automatic
        window.minSize = NSSize(width: 620, height: 460)
        window.setFrameAutosaveName("LightSettings")
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.contentViewController = NSHostingController(rootView: SettingsView(vpn: vpn))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func showWindow(_ sender: Any?) {
        NSApp.setActivationPolicy(.regular)
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func windowWillClose(_ notification: Notification) { NSApp.setActivationPolicy(.accessory) }
}

enum SettingsTab: String, CaseIterable, Identifiable {
    case connection = "Connection", appearance = "Appearance", about = "About"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .connection: return "network"
        case .appearance: return "circle.lefthalf.filled"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var vpn: VPNController
    @State private var selection: SettingsTab? = .connection
    @State private var history: [SettingsTab] = [.connection]
    @State private var historyIndex = 0
    @State private var navigating = false
    @AppStorage("indicatorColor") private var indicatorColor = "yellow"

    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(SettingsTab.allCases, selection: $selection) { tab in
                Label(tab.rawValue, systemImage: tab.symbol).tag(tab)
            }
            .listStyle(.sidebar)
            .softScrollEdges()
            .navigationTitle("Settings")
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } detail: {
            Form {
                switch selection ?? .connection {
                case .connection: connection
                case .appearance: appearance
                case .about: about
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .settingsMargins()
            .navigationTitle((selection ?? .connection).rawValue)
        }
        .navigationTitle("Settings")
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button { navigate(-1) } label: { Image(systemName: "chevron.left") }
                    .help("Back").accessibilityLabel("Back").disabled(historyIndex == 0)
                Button { navigate(1) } label: { Image(systemName: "chevron.right") }
                    .help("Forward").accessibilityLabel("Forward").disabled(historyIndex == history.count - 1)
            }
        }
        .onChange(of: selection) { tab in
            guard !navigating, let tab, history[historyIndex] != tab else { return }
            history = Array(history.prefix(historyIndex + 1)) + [tab]
            historyIndex = history.count - 1
        }
    }

    private func navigate(_ delta: Int) {
        let next = historyIndex + delta
        guard history.indices.contains(next) else { return }
        navigating = true
        historyIndex = next
        selection = history[next]
        DispatchQueue.main.async { navigating = false }
    }

    @ViewBuilder private var connection: some View {
        Section("VPN") {
            Picker("Profile", selection: $vpn.selectedID) {
                Text("Choose a profile").tag("")
                if !vpn.selectedID.isEmpty && !vpn.services.contains(where: { $0.id == vpn.selectedID }) {
                    Text("Unavailable profile").tag(vpn.selectedID)
                }
                ForEach(vpn.services) { service in Text(service.name).tag(service.id) }
            }
            Button("Refresh Profiles") { vpn.refreshServices() }
            LabeledContent("Status", value: vpn.state.description)
            HStack {
                Button(vpn.state == .connected || vpn.state == .connecting ? "Disconnect" : "Connect") { vpn.toggle() }
                    .disabled(![VPNState.connected, .connecting, .disconnected].contains(vpn.state))
                Button("Open Shadowrocket") { vpn.openShadowrocket() }
            }
            Text("Set up a VPN in Shadowrocket first. Light uses that existing profile and never imports your credentials.")
                .font(.caption).foregroundStyle(.secondary)
            if let error = vpn.error { Text(error).foregroundStyle(.red).textSelection(.enabled) }
        }
        Section("Controls") {
            Text("Click the dot to disconnect. Right-click it or reopen Light to return to Settings. The dot hides after macOS confirms disconnection.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var appearance: some View {
        Section("Indicator") {
            Picker("Connected color", selection: $indicatorColor) {
                Text("Yellow").tag("yellow")
                Text("White").tag("white")
            }
            Text("The indicator has no shadow. A connection failure stays red.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var about: some View {
        Section {
            LabeledContent("Light", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Development")
            Text("A small light for your VPN.").foregroundStyle(.secondary)
            Link("Website and setup", destination: URL(string: "https://metalnakls.github.io/light/")!)
            Link("Source code", destination: URL(string: "https://github.com/metalnakls/light")!)
        }
    }
}

private extension View {
    @ViewBuilder func softScrollEdges() -> some View {
        if #available(macOS 26, *) { scrollEdgeEffectStyle(.soft, for: .all) } else { self }
    }
    @ViewBuilder func settingsMargins() -> some View {
        if #available(macOS 14, *) { contentMargins(.top, 8, for: .scrollContent) } else { self }
    }
}
