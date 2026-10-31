import Foundation
import Carbon.HIToolbox

@main
struct PolicyChecks {
    @MainActor static func main() {
        var health = HealthEvidence()
        precondition(!health.failed)
        health.record(false)
        health.record(false)
        precondition(!health.failed, "One or two failures must not report a dead tunnel")
        health.record(false)
        precondition(health.failed, "Three failed rounds must report a failure")
        health.record(true)
        precondition(!health.failed, "One successful round must recover")
        health.record(false)
        health.record(nil)
        health.record(false)
        health.record(false)
        precondition(!health.failed, "Inconclusive evidence breaks a failure streak")

        precondition(Indicator.isYellow(hue: 0.15, saturation: 0.8, brightness: 0.9))
        precondition(!Indicator.isYellow(hue: 0.15, saturation: 0.1, brightness: 0.9), "Neutral backgrounds stay yellow")
        precondition(!Indicator.isYellow(hue: 0.15, saturation: 0.8, brightness: 0.2), "Dark backgrounds stay yellow")
        precondition(!Indicator.isYellow(hue: 0.65, saturation: 0.8, brightness: 0.9), "Blue is not yellow")
        precondition(KeyCombination.toggle.keyCode == UInt32(kVK_ANSI_V))
        precondition(KeyCombination.toggle.modifiers == UInt32(cmdKey | optionKey | controlKey))
        precondition(KeyCombination.open.modifiers == UInt32(cmdKey | optionKey | controlKey | shiftKey))
        precondition(KeyCombination.open != KeyCombination.toggle)
        print("Passed: conservative health, recovery, unknown state, contrast, and default hotkeys")
    }
}
