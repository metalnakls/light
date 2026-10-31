import AppKit
import ScreenCaptureKit

@MainActor
final class Indicator {
    private(set) var useWhite = false
    private var sampling = false

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

    func image(failed: Bool, transitioning: Bool) -> NSImage {
        let white = UserDefaults.standard.string(forKey: "indicatorColor") == "white" || useWhite
        let color: NSColor = failed ? .systemRed : (white ? .white : .systemYellow)
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()
        defer { image.unlockFocus() }
        color.setFill()
        color.setStroke()
        if failed {
            // A red diamond distinguishes failure even when colors are hard to distinguish.
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 9, y: 3))
            path.line(to: NSPoint(x: 15, y: 9))
            path.line(to: NSPoint(x: 9, y: 15))
            path.line(to: NSPoint(x: 3, y: 9))
            path.close()
            path.fill()
        } else {
            let path = NSBezierPath(ovalIn: NSRect(x: 5, y: 5, width: 8, height: 8))
            if transitioning { path.lineWidth = 2; path.stroke() } else { path.fill() }
        }
        image.isTemplate = false
        return image
    }
}
