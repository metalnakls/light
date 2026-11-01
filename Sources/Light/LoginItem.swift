import AppKit
import Combine
import ServiceManagement

@MainActor
final class LoginItem: ObservableObject {
    static let shared = LoginItem()
    @Published private(set) var status = SMAppService.mainApp.status
    @Published private(set) var error: String?
    private let defaults: UserDefaults
    private let service: SMAppService
    private static let configuredKey = "loginItemConfigured"

    init(service: SMAppService = .mainApp, defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults
        status = service.status
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: NSApplication.didBecomeActiveNotification, object: nil)
    }

    var enabled: Bool { status == .enabled || status == .requiresApproval }

    func start() {
        #if !DEBUG
        refresh()
        // Configure once. A later choice in Light or System Settings is authoritative.
        guard !defaults.bool(forKey: Self.configuredKey) else { return }
        defaults.set(true, forKey: Self.configuredKey)
        if !enabled { setEnabled(true) }
        #endif
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(true, forKey: Self.configuredKey)
        error = nil
        do {
            if enabled { try service.register() }
            else { try service.unregister() }
        } catch {
            self.error = "Could not update Launch at Login: \(error.localizedDescription)"
        }
        refresh()
    }

    @objc func refresh() {
        status = service.status
        if status == .enabled { error = nil }
    }

    func openApprovalSettings() { SMAppService.openSystemSettingsLoginItems() }
}
