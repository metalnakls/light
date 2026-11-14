import Foundation
import Combine
import Carbon.HIToolbox

@main
struct PolicyChecks {
    @MainActor static func main() {
        let vpn = VPNController(monitoring: false)
        let health = TunnelHealth()
        var vpnChanges = 0
        var healthChanges = 0
        var indicatorChanges = 0
        let vpnToken = vpn.objectWillChange.sink { vpnChanges += 1 }
        let healthToken = health.objectWillChange.sink { healthChanges += 1 }
        health.onChange = { indicatorChanges += 1 }
        for _ in 0..<100_000 {
            vpn.refresh()
            health.publish(failed: false, detail: "Waiting for a VPN connection.")
        }
        precondition(vpnChanges == 0 && healthChanges == 0 && indicatorChanges == 0,
                     "Unchanged polls must not invalidate UI or indicator observations")
        health.publish(failed: true, detail: "Failed")
        precondition(health.failed && health.detail == "Failed" && indicatorChanges == 1)
        health.publish(failed: true, detail: "Failed")
        precondition(healthChanges == 2 && indicatorChanges == 1)
        health.publish(failed: false, detail: "Recovered")
        precondition(!health.failed && health.detail == "Recovered" && indicatorChanges == 2)
        withExtendedLifetime((vpnToken, healthToken)) {}
        let fade = FailureTransition(from: 0, to: 1, started: 10)
        precondition(fade.value(at: 10) == 0)
        precondition(fade.value(at: 11) == 1)
        let middle = fade.value(at: 10.12)
        precondition(middle > 0 && middle < 1)
        let interrupted = FailureTransition(from: middle, to: 0, started: 10.12)
        precondition(interrupted.value(at: 10.12) == middle, "Recovery must continue from the current frame")
        precondition(interrupted.value(at: 11) == 0)
        precondition(ProxyHealthClient.classify(NSError(domain: "kCFErrorDomainCFNetwork", code: 310)) == .failed)
        precondition(ProxyHealthClient.classify(NSError(domain: "kCFErrorDomainCFNetwork", code: 307)) == .inconclusive)
        precondition(ProxyHealthClient.classify(URLError(.cancelled)) == .inconclusive)
        precondition(ProxyHealthClient.classify(URLError(.timedOut)) == .failed)
        var evidence = HealthEvidence()
        evidence.record(.failed)
        evidence.record(.failed)
        precondition(!evidence.failed, "Isolated failures must not turn red")
        evidence.record(.failed)
        precondition(evidence.failed, "Three confirmed failed rounds must turn red")
        evidence.record(.reachable)
        precondition(!evidence.failed, "A successful response recovers immediately")
        evidence.record(.failed)
        evidence.record(.inconclusive)
        evidence.record(.failed)
        evidence.record(.failed)
        precondition(!evidence.failed, "Inconclusive evidence breaks a failure streak")
        precondition(HealthEvidence.combine(.failed, .reachable) == .reachable)
        precondition(HealthEvidence.combine(.failed, .inconclusive) == .inconclusive)
        precondition(HealthEvidence.combine(.failed, .failed) == .failed)
        precondition(HealthProxy(settings: ["HTTPSEnable": 1, "HTTPSProxy": "127.0.0.1", "HTTPSPort": 1082]) != nil)
        precondition(HealthProxy(settings: ["HTTPSEnable": 0, "HTTPSProxy": "127.0.0.1", "HTTPSPort": 1082]) == nil)
        precondition(HealthProxy(settings: ["HTTPSEnable": 1, "HTTPSProxy": "example.com", "HTTPSPort": 1082]) == nil)
        precondition(HealthProxy(settings: ["HTTPSEnable": 1, "HTTPSProxy": "127.0.0.1", "HTTPSPort": 70000]) == nil)
        precondition(Indicator.isYellow(hue: 0.15, saturation: 0.8, brightness: 0.9))
        precondition(!Indicator.isYellow(hue: 0.15, saturation: 0.1, brightness: 0.9), "Neutral backgrounds stay yellow")
        precondition(!Indicator.isYellow(hue: 0.15, saturation: 0.8, brightness: 0.2), "Dark backgrounds stay yellow")
        precondition(!Indicator.isYellow(hue: 0.65, saturation: 0.8, brightness: 0.9), "Blue is not yellow")
        precondition(KeyCombination.toggle.keyCode == UInt32(kVK_ANSI_V))
        precondition(KeyCombination.toggle.modifiers == UInt32(cmdKey | optionKey | controlKey))
        precondition(KeyCombination.open.modifiers == UInt32(cmdKey | optionKey | controlKey | shiftKey))
        precondition(KeyCombination.open != KeyCombination.toggle)
        print("Passed: failure confirmation, recovery, proxy validation, contrast, and default hotkeys")
    }
}
