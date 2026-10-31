import AppKit
import SystemConfiguration
import Combine

struct VPNService: Identifiable, Equatable {
    let id: String
    let name: String
}

enum VPNState: Equatable {
    case unavailable, disconnected, connecting, connected, disconnecting, failed
    var description: String {
        switch self {
        case .unavailable: return "Choose an available VPN profile."
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        case .disconnecting: return "Disconnecting…"
        case .failed: return "VPN status unavailable"
        }
    }
}

@MainActor
final class VPNController: ObservableObject {
    @Published private(set) var services: [VPNService] = []
    @Published private(set) var state: VPNState = .unavailable
    @Published var error: String?
    @Published var selectedID: String {
        didSet {
            UserDefaults.standard.set(selectedID, forKey: "vpnService")
            attach()
        }
    }
    var onChange: (() -> Void)?
    private var connection: SCNetworkConnection?
    private var timer: Timer?
    private var requestedAt: Date?
    private var requestedConnection: Bool?

    init() {
        selectedID = UserDefaults.standard.string(forKey: "vpnService") ?? ""
        refreshServices()
        attach()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refreshServices() {
        guard let preferences = SCPreferencesCreate(nil, "Light" as CFString, nil) else { return }
        services = (SCNetworkServiceCopyAll(preferences) as? [SCNetworkService] ?? []).compactMap { service in
            guard SCNetworkServiceGetEnabled(service),
                  let id = SCNetworkServiceGetServiceID(service) as String?,
                  let candidate = SCNetworkConnectionCreateWithServiceID(nil, id as CFString, nil, nil),
                  SCNetworkConnectionGetStatus(candidate) != .invalid else { return nil }
            return VPNService(id: id, name: SCNetworkServiceGetName(service) as String? ?? "VPN")
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        // Never silently switch away from a previously selected profile.
        if selectedID.isEmpty, let shadowrocket = services.first(where: { $0.name.lowercased() == "shadowrocket" }) {
            selectedID = shadowrocket.id
        }
    }

    private func attach() {
        connection = selectedID.isEmpty ? nil : SCNetworkConnectionCreateWithServiceID(nil, selectedID as CFString, nil, nil)
        requestedAt = nil
        requestedConnection = nil
        error = nil
        refresh()
    }

    func refresh() {
        let previous = state
        if let connection {
            switch SCNetworkConnectionGetStatus(connection) {
            case .disconnected: state = .disconnected
            case .connecting: state = .connecting
            case .connected: state = .connected
            case .disconnecting: state = .disconnecting
            default: state = .failed
            }
        } else { state = .unavailable }
        if let requestedAt, let desired = requestedConnection {
            if (desired && state == .connected) || (!desired && state == .disconnected) {
                self.requestedAt = nil
                requestedConnection = nil
            } else if Date().timeIntervalSince(requestedAt) > 30 {
                error = "The VPN did not finish \(desired ? "connecting" : "disconnecting"). Open Shadowrocket to check its configuration."
                self.requestedAt = nil
                requestedConnection = nil
            }
        }
        if state != previous { onChange?() }
    }

    func toggle() {
        refresh()
        switch state {
        case .connected, .connecting: disconnect()
        case .disconnected: connect()
        default: error = "Wait for the VPN transition or select an available profile in Settings."
        }
    }
    func connect() { request(connected: true) }
    func disconnect() { request(connected: false) }

    private func request(connected: Bool) {
        guard let connection else { error = "Choose a VPN profile in Settings first."; return }
        guard requestedAt == nil else { return }
        let accepted = connected
            ? SCNetworkConnectionStart(connection, nil, false)
            : SCNetworkConnectionStop(connection, true)
        guard accepted else {
            error = "macOS could not \(connected ? "connect" : "disconnect") this VPN: \(String(cString: SCErrorString(SCError())))"
            onChange?()
            return
        }
        error = nil
        requestedAt = Date()
        requestedConnection = connected
        refresh()
        onChange?()
    }

    var interfaceName: String? {
        guard let connection, state == .connected,
              let status = SCNetworkConnectionCopyExtendedStatus(connection) as? [String: Any] else { return nil }
        for key in ["IPv4", "IPv6", "VPN"] {
            if let value = (status[key] as? [String: Any])?["InterfaceName"] as? String { return value }
        }
        if let name = status["InterfaceName"] as? String { return name }
        if let store = SCDynamicStoreCreate(nil, "Light" as CFString, nil, nil) {
            for family in ["IPv4", "IPv6"] {
                let key = "State:/Network/Service/\(selectedID)/\(family)" as CFString
                if let value = SCDynamicStoreCopyValue(store, key) as? [String: Any],
                   let name = value["InterfaceName"] as? String { return name }
            }
        }
        return nil
    }

    func openShadowrocket() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.liguangming.Shadowrocket") else {
            error = "Shadowrocket is not installed. Install and configure it before using Light."
            return
        }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if let error { Task { @MainActor in self.error = error.localizedDescription } }
        }
    }
}
