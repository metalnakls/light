import AppKit
import CFNetwork
import Combine
import Foundation
import Network

struct HealthProxy: Equatable, Sendable {
    let host: String
    let port: Int

    init?(settings: [String: Any]) {
        guard (settings["HTTPSEnable"] as? NSNumber)?.boolValue == true,
              let host = settings["HTTPSProxy"] as? String,
              ["127.0.0.1", "::1", "localhost"].contains(host.lowercased()),
              let port = (settings["HTTPSPort"] as? NSNumber)?.intValue,
              (1...65535).contains(port) else { return nil }
        self.host = host
        self.port = port
    }

    var dictionary: [AnyHashable: Any] {
        ["HTTPEnable": 1, "HTTPProxy": host, "HTTPPort": port,
         "HTTPSEnable": 1, "HTTPSProxy": host, "HTTPSPort": port,
         "ExceptionsList": [String](), "ExcludeSimpleHostnames": 0,
         "ProxyAutoConfigEnable": 0, "ProxyAutoDiscoveryEnable": 0]
    }
}

struct HealthContext: Equatable {
    let serviceID: String
    let interface: String
    let proxy: HealthProxy
}

enum ProbeResult: Equatable { case reachable, failed, inconclusive }

struct HealthEvidence {
    private(set) var failures = 0
    var failed: Bool { failures >= 3 }
    mutating func record(_ result: ProbeResult) {
        switch result {
        case .reachable, .inconclusive: failures = 0
        case .failed: failures += 1
        }
    }
    static func combine(_ first: ProbeResult, _ second: ProbeResult) -> ProbeResult {
        if first == .reachable || second == .reachable { return .reachable }
        return first == .failed && second == .failed ? .failed : .inconclusive
    }
}

final class ProxyHealthClient: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private var session: URLSession!
    init(proxy: HealthProxy) {
        super.init()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = proxy.dictionary
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        configuration.waitsForConnectivity = false
        configuration.timeoutIntervalForRequest = 3
        configuration.timeoutIntervalForResource = 3
        configuration.httpMaximumConnectionsPerHost = 1
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }
    func cancel() { session.invalidateAndCancel() }
    func check(_ url: URL) async -> ProbeResult {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 3)
        request.httpMethod = "HEAD"
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        do {
            let (_, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse, response.statusCode != 407 else { return .inconclusive }
            // Even a remote 403/500 proves that HTTPS traffic received a response.
            return .reachable
        } catch { return Self.classify(error) }
    }
    static func classify(_ error: Error) -> ProbeResult {
        let error = error as NSError
        if error.domain == kCFErrorDomainCFNetwork as String {
            switch error.code {
            case 306, 310, 311: return .failed // Proxy connection or CONNECT failure.
            default: return .inconclusive
            }
        }
        guard error.domain == NSURLErrorDomain else { return .inconclusive }
        switch URLError.Code(rawValue: error.code) {
        case .timedOut, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed, .networkConnectionLost: return .failed
        default: return .inconclusive
        }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil) // A redirect is already a response; don't follow it or add requests.
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust {
            completionHandler(.performDefaultHandling, nil)
        } else { completionHandler(.cancelAuthenticationChallenge, nil) }
    }
}

@MainActor
final class TunnelHealth: ObservableObject {
    @Published private(set) var failed = false
    @Published private(set) var detail = "Waiting for a VPN connection."
    var onChange: (() -> Void)?
    private var evidence = HealthEvidence()
    private var context: HealthContext?
    private var client: ProxyHealthClient?
    private var task: Task<Void, Never>?
    private var generation = 0
    private var readyAt: TimeInterval = 0
    private var lastStarted = -Double.infinity
    private var timer: Timer?
    private var sleeping = false
    private var offline = true
    private var pathIdentity = ""
    private let monitor = NWPathMonitor()
    private weak var vpn: VPNController?
    private let targets = [URL(string: "https://www.gstatic.com/generate_204")!, URL(string: "https://cp.cloudflare.com/generate_204")!]
    private var targetIndex = 0

    func start(vpn: VPNController) {
        self.vpn = vpn
        monitor.pathUpdateHandler = { [weak self] path in
            let key = "\(path.status):\(path.isExpensive):\(path.availableInterfaces.map(\.name).sorted())"
            Task { @MainActor in
                guard let self else { return }
                self.offline = path.status != .satisfied
                if key != self.pathIdentity { self.pathIdentity = key; self.reset() }
                self.refresh()
            }
        }
        monitor.start(queue: DispatchQueue(label: "Light.health-path"))
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        timer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        refresh()
    }
    @objc private func willSleep() { sleeping = true; reset() }
    @objc private func didWake() { sleeping = false; reset(); refresh() }
    private func reset() {
        generation += 1
        task?.cancel()
        task = nil
        client?.cancel()
        client = nil
        evidence = HealthEvidence()
        failed = false
        readyAt = ProcessInfo.processInfo.systemUptime + 8
        lastStarted = -Double.infinity
        onChange?()
    }
    func refresh() {
        guard let vpn else { return }
        let next = vpn.state == .connected ? vpn.healthContext : nil
        if next != context { context = next; reset() }
        guard vpn.state == .connected else {
            detail = vpn.state.description
            onChange?()
            return
        }
        guard !sleeping, !offline else { detail = "Health check paused while the network is unavailable."; return }
        guard let context else { detail = "Connected; no supported local proxy is available for health checks."; return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now >= readyAt else { detail = "Connected; waiting for the tunnel to settle…"; return }
        guard task == nil, now - lastStarted >= 4 else { return }
        if client == nil { client = ProxyHealthClient(proxy: context.proxy) }
        guard let client else { return }
        lastStarted = now
        let epoch = generation
        let firstURL = targets[targetIndex]
        let secondURL = targets[1 - targetIndex]
        targetIndex = 1 - targetIndex
        task = Task { [weak self] in
            let first = await client.check(firstURL)
            let result: ProbeResult
            if first == .failed && !Task.isCancelled {
                result = HealthEvidence.combine(first, await client.check(secondURL))
            } else { result = first }
            guard let self, !Task.isCancelled, epoch == self.generation else { return }
            // Re-read the connection and proxy before accepting an in-flight result.
            guard self.vpn?.state == .connected, self.vpn?.healthContext == context else { self.task = nil; self.refresh(); return }
            self.task = nil
            self.evidence.record(result)
            self.failed = self.evidence.failed
            switch result {
            case .reachable: self.detail = "HTTPS responded through the VPN’s local proxy."
            case .failed: self.detail = self.failed ? "VPN connected, but HTTPS checks repeatedly timed out or failed through its proxy." : "A check failed; confirming before showing red…"
            case .inconclusive: self.detail = "Connected; health check inconclusive."
            }
            self.onChange?()
        }
    }
}
