import Cocoa
import CoreGraphics

// Real WindowServer input, only with permission already granted. Restores focus
// and pointer. A fixture below the hovered pill records clicks passed through.
guard CGPreflightPostEventAccess() else {
    fputs("Native input check unavailable: runner lacks event-posting permission.\n", stderr)
    exit(77)
}
guard CommandLine.arguments.count == 2 else { exit(2) }
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let previousApp = NSWorkspace.shared.frontmostApplication
let previousPointer = CGEvent(source: nil)!.location
let screen = NSScreen.screens[0]
let leftArea = screen.auxiliaryTopLeftArea
let centreX = screen.safeAreaInsets.top > 0 && leftArea != nil
    ? leftArea!.maxX - 12 - 125 : screen.frame.midX
let topY = NSScreen.screens[0].frame.height - screen.frame.maxY

final class ClickView: NSView {
    var clicks = 0
    override func mouseDown(with event: NSEvent) { clicks += 1 }
}
final class FixtureWindow: NSWindow {
    override func constrainFrameRect(_ rect: NSRect, to screen: NSScreen?) -> NSRect { rect }
}
let fixtureView = ClickView()
let fixture = FixtureWindow(contentRect: NSRect(x: centreX - 320,
    y: screen.frame.maxY - 360, width: 640, height: 360),
    styleMask: [.borderless], backing: .buffered, defer: false)
fixture.title = "Pill input test fixture"
fixture.backgroundColor = NSColor(calibratedWhite: 0.12, alpha: 1)
fixture.level = NSWindow.Level(rawValue: 1)
fixture.contentView = fixtureView
fixture.isReleasedWhenClosed = false
fixture.orderFrontRegardless()

let child = Process()
child.executableURL = URL(fileURLWithPath: CommandLine.arguments[1])
try child.run()
var failures = 0
@MainActor func check(_ valid: Bool, _ text: String) {
    print("\(valid ? "PASS" : "FAIL"): \(text)")
    if !valid { failures += 1 }
}
@MainActor func windows() -> [[String: Any]] {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
    return (list as? [[String: Any]] ?? []).filter {
        ($0[kCGWindowOwnerPID as String] as? Int) == Int(child.processIdentifier)
    }
}
@MainActor func pillBounds() -> CGRect? {
    // Negative-level idle windows are absent from CGWindowList. Observe the
    // real positive-level hovered/open panel, not Qt's invisible placeholders.
    guard let window = windows().first(where: {
        ($0[kCGWindowLayer as String] as? Int) == 3
    }), let bounds = window[kCGWindowBounds as String] as? NSDictionary else { return nil }
    return CGRect(dictionaryRepresentation: bounds)
}
@MainActor func hasCatcher() -> Bool {
    windows().contains { ($0[kCGWindowLayer as String] as? Int) == 2 }
}
@MainActor func move(_ point: CGPoint) {
    CGWarpMouseCursorPosition(point)
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
        mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
}
@MainActor func click(_ point: CGPoint) {
    for type in [CGEventType.leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: nil, mouseType: type,
            mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    }
}
@MainActor func finish() -> Never {
    child.terminate()
    child.waitUntilExit()
    fixture.close()
    CGWarpMouseCursorPosition(previousPointer)
    previousApp?.activate(options: [])
    exit(failures == 0 ? 0 : 1)
}
let outside = CGPoint(x: centreX - 290, y: topY + 320)
let centre = CGPoint(x: centreX, y: topY + 17)
var phase = 0
var started = Date()
@MainActor func next() { phase += 1; started = Date() }
move(outside)

@MainActor final class InputDriver: NSObject {
    @objc func tick(_ timer: Timer) {
    let elapsed = Date().timeIntervalSince(started)
    if elapsed > 5 {
        check(false, "input phase \(phase) timed out, bounds=\(String(describing: pillBounds())), catcher=\(hasCatcher()), fixtureClicks=\(fixtureView.clicks), windows=\(windows())")
        timer.invalidate()
        finish()
    }
    switch phase {
    case 0:
        guard elapsed > 1 else { return }
        click(outside); next()
    case 1:
        guard elapsed > 0.2 else { return }
        check(fixtureView.clicks == 1, "idle outside click reaches underlying native fixture")
        move(centre); next()
    case 2:
        guard let bounds = pillBounds(), bounds.width == 360, bounds.height == 44 else { return }
        check(bounds.minY == topY, "real hovered panel aligns with omacosy strip")
        move(CGPoint(x: bounds.minX + 1, y: bounds.minY + 1)); next()
    case 3:
        // Sample after 3 polling intervals, before the 180 ms hover-leave delay.
        guard elapsed > 0.05 else { return }
        guard let bounds = pillBounds() else {
            check(false, "corner probe must overlap a raised pill"); finish()
        }
        check(bounds.width == 360, "corner probe runs while pill is above fixture")
        click(CGPoint(x: bounds.minX + 1, y: bounds.minY + 1)); next()
    case 4:
        guard elapsed > 0.1 else { return }
        check(fixtureView.clicks == 2, "transparent rounded corner passes real click through")
        move(centre); next()
    case 5:
        guard elapsed > 0.06, pillBounds()?.width == 360 else { return }
        click(centre); next()
    case 6:
        guard pillBounds()?.height == 264 else { return }
        check(hasCatcher(), "real click pins mixer and enables catcher")
        move(outside); next()
    case 7:
        guard elapsed > 0.1 else { return }
        click(outside); next()
    case 8:
        guard pillBounds() == nil, !hasCatcher() else { return }
        check(fixtureView.clicks == 2, "outside dismissal consumes click")
        check(true, "real outside click closes panel and removes catcher")
        click(outside); next()
    case 9:
        guard elapsed > 0.2 else { return }
        check(fixtureView.clicks == 3, "desktop input resumes after dismissal")
        move(centre); next()
    case 10:
        guard elapsed > 0.06, pillBounds()?.width == 360 else { return }
        click(centre); next()
    case 11:
        guard pillBounds()?.height == 264 else { return }
        CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: true)?.post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: nil, virtualKey: 53, keyDown: false)?.post(tap: .cghidEventTap)
        move(outside); next()
    default:
        guard pillBounds() == nil, !hasCatcher() else { return }
        check(true, "real Escape closes focused mixer")
        timer.invalidate()
        finish()
    }
    }
}
let driver = InputDriver()
Timer.scheduledTimer(timeInterval: 0.01, target: driver, selector: #selector(InputDriver.tick(_:)), userInfo: nil, repeats: true)
app.run()
