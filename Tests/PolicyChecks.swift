import Foundation
import Carbon.HIToolbox

@main
struct PolicyChecks {
    @MainActor static func main() {
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
