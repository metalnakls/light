import AppKit
import Combine
import Sparkle

@MainActor
final class Updates: ObservableObject {
    static let shared = Updates()
    @Published var checks = true
    @Published var downloads = true
    @Published var canCheck = false
    @Published var error: String?
    private let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    private var observations: [NSKeyValueObservation] = []

    func start() {
        #if !DEBUG
        do { try controller.updater.start() }
        catch { self.error = error.localizedDescription }
        observations = [
            controller.updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { updater, _ in
                Task { @MainActor in self.checks = updater.automaticallyChecksForUpdates }
            },
            controller.updater.observe(\.automaticallyDownloadsUpdates, options: [.initial, .new]) { updater, _ in
                Task { @MainActor in self.downloads = updater.automaticallyDownloadsUpdates }
            },
            controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { updater, _ in
                Task { @MainActor in self.canCheck = updater.canCheckForUpdates }
            }
        ]
        #endif
    }
    func setChecks(_ enabled: Bool) { controller.updater.automaticallyChecksForUpdates = enabled }
    func setDownloads(_ enabled: Bool) { controller.updater.automaticallyDownloadsUpdates = enabled }
    func check() {
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }
}
