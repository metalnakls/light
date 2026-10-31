import Foundation
import Network
import Combine

struct HealthEvidence {
    private(set) var consecutiveFailures = 0
    var failed: Bool { consecutiveFailures >= 3 }
    mutating func record(_ reachable: Bool?) {
        guard let reachable else { consecutiveFailures = 0; return }
        consecutiveFailures = reachable ? 0 : consecutiveFailures + 1
    }
}

@MainActor
final class TunnelHealth: ObservableObject {
    @Published private(set) var failed = false
    @Published private(set) var detail = "Waiting for a VPN connection."
    var onChange: (() -> Void)?
    private var evidence = HealthEvidence()
    private var generation = 0
    private var lastService = ""
    private var lastState: VPNState = .unavailable
    private var connectedAt: Date?
    private var checking = false
    private var lastCheck = Date.distantPast
    private let monitor = NWPathMonitor()
    private var interfaces: [NWInterface] = []

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.interfaces = path.availableInterfaces }
        }
        monitor.start(queue: DispatchQueue(label: "Light.interfaces"))
    }

    func update(vpn: VPNController) {
        if vpn.selectedID != lastService || vpn.state != lastState {
            generation += 1
            lastService = vpn.selectedID
            lastState = vpn.state
            evidence = HealthEvidence()
            failed = false
            connectedAt = vpn.state == .connected ? Date() : nil
            lastCheck = .distantPast
            detail = vpn.state == .connected ? "Waiting for the tunnel to settle…" : vpn.state.description
            onChange?()
        }
        guard vpn.state == .connected, let connectedAt, Date().timeIntervalSince(connectedAt) >= 15,
              !checking, Date().timeIntervalSince(lastCheck) >= 15 else { return }
        guard let name = vpn.interfaceName, name.hasPrefix("utun"),
              let interface = interfaces.first(where: { $0.name == name }) else {
            evidence.record(nil)
            failed = false
            detail = "Connected; macOS has not exposed the tunnel interface for a health check."
            onChange?()
            return
        }
        checking = true
        lastCheck = Date()
        let epoch = generation
        Task {
            async let apple = TunnelProbe.check(host: "www.apple.com", path: "/library/test/success.html", interface: interface)
            async let cloudflare = TunnelProbe.check(host: "www.cloudflare.com", path: "/cdn-cgi/trace", interface: interface)
            let results = await (apple, cloudflare)
            checking = false
            guard epoch == generation else { return }
            evidence.record(results.0 || results.1)
            failed = evidence.failed
            detail = failed ? "Both HTTPS checks failed through the VPN three times in a row."
                : (results.0 || results.1 ? "HTTPS traffic succeeded through the VPN." : "Checking again before reporting a failure…")
            onChange?()
        }
    }
}

// Each probe owns one connection and a timeout on a serial queue. It cannot fall
// back to Wi-Fi/Ethernet: Network.framework requires the selected VPN interface.
private final class TunnelProbe: @unchecked Sendable {
    private let queue = DispatchQueue(label: "Light.health-probe")
    private let connection: NWConnection
    private var continuation: CheckedContinuation<Bool, Never>?
    private var received = Data()
    private var timeout: DispatchWorkItem?
    private let request: Data

    static func check(host: String, path: String, interface: NWInterface) async -> Bool {
        let probe = TunnelProbe(host: host, path: path, interface: interface)
        return await withCheckedContinuation { continuation in
            probe.queue.async {
                probe.continuation = continuation
                probe.start()
            }
        }
    }

    private init(host: String, path: String, interface: NWInterface) {
        let parameters = NWParameters.tls
        parameters.requiredInterface = interface
        parameters.prohibitExpensivePaths = false
        connection = NWConnection(host: NWEndpoint.Host(host), port: 443, using: parameters)
        request = Data("GET \(path) HTTP/1.1\r\nHost: \(host)\r\nConnection: close\r\nCache-Control: no-cache\r\n\r\n".utf8)
    }
    private func start() {
        let timeout = DispatchWorkItem { self.finish(false) }
        self.timeout = timeout
        queue.asyncAfter(deadline: .now() + 8, execute: timeout)
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                self.connection.send(content: self.request, completion: .contentProcessed { error in
                    if error != nil { self.finish(false) } else { self.receive() }
                })
            case .failed: self.finish(false)
            default: break
            }
        }
        connection.start(queue: queue)
    }
    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { data, _, complete, error in
            guard self.continuation != nil else { return }
            if let data { self.received.append(data) }
            if let header = String(data: self.received, encoding: .utf8), header.contains("\r\n") {
                let code = header.components(separatedBy: "\r\n")[0].split(separator: " ").dropFirst().first.flatMap { Int($0) }
                self.finish(code == 200 || code == 204)
            } else if complete || error != nil || self.received.count > 8192 { self.finish(false) }
            else { self.receive() }
        }
    }
    private func finish(_ success: Bool) {
        guard let continuation else { return }
        self.continuation = nil
        timeout?.cancel()
        timeout = nil
        connection.stateUpdateHandler = nil
        connection.cancel()
        continuation.resume(returning: success)
    }
}
