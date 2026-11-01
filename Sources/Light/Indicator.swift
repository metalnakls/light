import AppKit
import ScreenCaptureKit

struct FailureTransition {
    static let duration: TimeInterval = 0.24
    let from: Double
    let to: Double
    let started: TimeInterval
    func value(at time: TimeInterval) -> Double {
        let progress = min(1, max(0, (time - started) / Self.duration))
        let eased = 1 - pow(1 - progress, 3)
        return from + (to - from) * eased
    }
}

@MainActor
final class Indicator {
    private(set) var useWhite = false
    private var sampling = false
    private var animation: FailureTransition?
    private var animationTimer: Timer?
    private var displayedFailure = 0.0
    private var failureTarget: Double?
    private weak var button: NSStatusBarButton?
    private var transitioning = false

    func update(button: NSStatusBarButton?, failed: Bool, transitioning: Bool, visible: Bool) {
        self.button = button
        self.transitioning = transitioning
        let target = failed ? 1.0 : 0.0
        let now = ProcessInfo.processInfo.systemUptime
        if let animation { displayedFailure = animation.value(at: now) }
        if !visible || failureTarget == nil || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            animationTimer?.invalidate()
            animationTimer = nil
            animation = nil
            displayedFailure = target
        } else if failureTarget != target {
            animation = FailureTransition(from: displayedFailure, to: target, started: now)
            animationTimer?.invalidate()
            let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.advanceAnimation() }
            }
            animationTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        failureTarget = target
        redraw()
    }

    private func advanceAnimation() {
        guard let animation else { return }
        let now = ProcessInfo.processInfo.systemUptime
        displayedFailure = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? animation.to : animation.value(at: now)
        if now - animation.started >= FailureTransition.duration || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            displayedFailure = animation.to
            animationTimer?.invalidate()
            animationTimer = nil
            self.animation = nil
        }
        redraw()
    }

    private func redraw() {
        button?.image = image(failed: failureTarget == 1, transitioning: transitioning, failureAmount: displayedFailure)
    }

    func sample(near button: NSStatusBarButton?) async {
        guard UserDefaults.standard.bool(forKey: "adaptiveColor"), CGPreflightScreenCaptureAccess(),
              !sampling, let button, let window = button.window, let screen = window.screen,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              #available(macOS 14, *) else { useWhite = false; return }
        sampling = true
        defer { sampling = false }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == number.uint32Value }) else { return }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
            let config = SCStreamConfiguration()
            // Sample a strip inside the button's empty left margin, away from the dot.
            config.sourceRect = CGRect(x: max(0, rect.minX - screen.frame.minX + 1),
                y: max(0, screen.frame.maxY - rect.midY - 1), width: 2, height: 2)
            config.width = 2
            config.height = 2
            config.showsCursor = false
            config.capturesAudio = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            let bitmap = NSBitmapImageRep(cgImage: image)
            guard let color = bitmap.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB) else { return }
            var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
            color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
            useWhite = Self.isYellow(hue: hue, saturation: saturation, brightness: brightness)
        } catch { useWhite = false }
    }

    static func isYellow(hue: CGFloat, saturation: CGFloat, brightness: CGFloat) -> Bool {
        (0.09...0.20).contains(hue) && saturation > 0.25 && brightness > 0.4
    }

    func image(failed: Bool, transitioning: Bool, failureAmount: Double? = nil) -> NSImage {
        let white = UserDefaults.standard.string(forKey: "indicatorColor") == "white" || useWhite
        let amount = CGFloat(min(1, max(0, failureAmount ?? (failed ? 1 : 0))))
        let healthy: NSColor = white ? .white : .systemYellow
        let color = healthy.blended(withFraction: amount, of: .systemRed) ?? .systemRed
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()
        defer { image.unlockFocus() }
        color.setFill()
        color.setStroke()
        if amount > 0 {
            color.withAlphaComponent(amount).setFill()
            // A red diamond distinguishes failure even when colors are hard to distinguish.
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 9, y: 3))
            path.line(to: NSPoint(x: 15, y: 9))
            path.line(to: NSPoint(x: 9, y: 15))
            path.line(to: NSPoint(x: 3, y: 9))
            path.close()
            path.fill()
        }
        if amount < 1 {
            color.withAlphaComponent(1 - amount).setFill()
            color.withAlphaComponent(1 - amount).setStroke()
            let path = NSBezierPath(ovalIn: NSRect(x: 5, y: 5, width: 8, height: 8))
            if transitioning { path.lineWidth = 2; path.stroke() } else { path.fill() }
        }
        image.isTemplate = false
        return image
    }
}
