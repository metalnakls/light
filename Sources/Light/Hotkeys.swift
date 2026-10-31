import AppKit
import Carbon.HIToolbox
import SwiftUI

struct KeyCombination: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var label: String
    static let toggle = KeyCombination(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | optionKey | controlKey), label: "⌃⌥⌘V")
    static let open = KeyCombination(keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | optionKey | controlKey | shiftKey), label: "⌃⌥⇧⌘V")
}

@MainActor
final class Hotkeys: ObservableObject {
    static let shared = Hotkeys()
    @Published private(set) var toggleKey: KeyCombination
    @Published private(set) var openKey: KeyCombination
    @Published var error: String?
    var onToggle: (() -> Void)?
    var onOpen: (() -> Void)?
    private var refs: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?

    private init() {
        toggleKey = Self.load("toggleKey") ?? .toggle
        openKey = Self.load("openKey") ?? .open
    }
    private static func load(_ key: String) -> KeyCombination? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(KeyCombination.self, from: $0) }
    }
    func start() {
        if handler == nil {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                guard let event else { return OSStatus(eventNotHandledErr) }
                var identifier = EventHotKeyID()
                GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &identifier)
                guard identifier.signature == 0x4C495447 else { return OSStatus(eventNotHandledErr) }
                let id = identifier.id
                Task { @MainActor in
                    if id == 1 { Hotkeys.shared.onToggle?() }
                    if id == 2 { Hotkeys.shared.onOpen?() }
                }
                return noErr
            }, 1, &type, nil, &handler)
        }
        register()
    }
    func suspend() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
    }
    func resume() { register() }
    func set(_ combination: KeyCombination, opening: Bool) {
        guard combination != (opening ? toggleKey : openKey) else {
            error = "Choose different shortcuts for toggling the VPN and opening Shadowrocket."
            return
        }
        let old = opening ? openKey : toggleKey
        if opening { openKey = combination } else { toggleKey = combination }
        if !register() {
            let failure = error
            if opening { openKey = old } else { toggleKey = old }
            register()
            error = failure
            return
        }
        UserDefaults.standard.set(try? JSONEncoder().encode(combination), forKey: opening ? "openKey" : "toggleKey")
    }
    @discardableResult private func register() -> Bool {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        error = nil
        for (index, key) in [toggleKey, openKey].enumerated() {
            var ref: EventHotKeyRef?
            let result = RegisterEventHotKey(key.keyCode, key.modifiers,
                EventHotKeyID(signature: 0x4C495447, id: UInt32(index + 1)), GetApplicationEventTarget(), 0, &ref)
            guard result == noErr, let ref else {
                error = "\(key.label) is already in use. Choose another shortcut or remove its assignment in the other app."
                return false
            }
            refs.append(ref)
        }
        return true
    }
}

struct ShortcutRecorder: NSViewRepresentable {
    let title: String
    let combination: KeyCombination
    let onChange: (KeyCombination) -> Void
    func makeNSView(context: Context) -> RecorderButton { RecorderButton() }
    func updateNSView(_ button: RecorderButton, context: Context) {
        button.savedTitle = combination.label
        button.onChange = onChange
        button.setAccessibilityLabel(title)
        if !button.recording { button.title = combination.label }
    }
}

final class RecorderButton: NSButton {
    var savedTitle = ""
    var onChange: ((KeyCombination) -> Void)?
    var recording = false
    override var acceptsFirstResponder: Bool { true }
    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded
        target = self
        action = #selector(beginRecording)
        setButtonType(.momentaryPushIn)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    @objc private func beginRecording() {
        Hotkeys.shared.suspend()
        recording = true
        title = "Press shortcut…"
        window?.makeFirstResponder(self)
    }
    override func resignFirstResponder() -> Bool {
        if recording { Hotkeys.shared.resume() }
        recording = false
        title = savedTitle
        return super.resignFirstResponder()
    }
    override func keyDown(with event: NSEvent) {
        guard recording else { super.keyDown(with: event); return }
        if event.keyCode == 53 { recording = false; title = savedTitle; Hotkeys.shared.resume(); return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.command, .control, .option]).isEmpty,
              let character = event.charactersIgnoringModifiers?.uppercased(), !character.isEmpty else { NSSound.beep(); return }
        var modifiers: UInt32 = 0
        var label = ""
        for (flag, carbon, symbol) in [(NSEvent.ModifierFlags.control, controlKey, "⌃"), (.option, optionKey, "⌥"), (.shift, shiftKey, "⇧"), (.command, cmdKey, "⌘")] {
            if flags.contains(flag) { modifiers |= UInt32(carbon); label += symbol }
        }
        recording = false
        Hotkeys.shared.resume()
        onChange?(KeyCombination(keyCode: UInt32(event.keyCode), modifiers: modifiers, label: label + character))
        title = savedTitle
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if recording { keyDown(with: event); return true }
        return super.performKeyEquivalent(with: event)
    }
}
