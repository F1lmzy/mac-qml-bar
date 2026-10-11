import ApplicationServices
import AppKit
import Foundation

final class MenuIntegration: PillIntegration {
    static func menuItemEnabledForTest(attributeAvailable: Bool, enabled: Bool) -> Bool { attributeAvailable && enabled }
    private var frontPID: pid_t = 0
    private var path: [Int] = []
    private var permission = AXIsProcessTrusted()

    override func start(_ callback: @escaping ([String: Any]) -> Void) {
        precondition(Thread.isMainThread)
        super.start(callback)
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didActivateApplicationNotification) { [weak self] _ in
            guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            self?.path.removeAll(); self?.refresh()
        }
        refresh()
    }

    override func refresh() {
        precondition(Thread.isMainThread)
        permission = AXIsProcessTrusted()
        let app = NSWorkspace.shared.frontmostApplication
        if let app = app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier { frontPID = app.processIdentifier }
        guard frontPID > 0, NSRunningApplication(processIdentifier: frontPID)?.isTerminated == false else {
            frontPID = 0
            publish(["available": false, "permission": permission ? "authorized" : "notDetermined",
                     "canRequestPermission": !permission, "frontPid": 0, "items": [], "breadcrumb": []]); return
        }
        let pid = frontPID, menuPath = path, permitted = permission
        perform("refresh", work: { _ in
            guard permitted else { return ["available": false, "permission": "notDetermined", "frontPid": Int(pid), "items": [], "breadcrumb": [], "canRequestPermission": true] }
            let tree = try AXMenuReader.read(pid: pid, path: menuPath)
            return ["available": true, "permission": "authorized", "frontPid": Int(pid), "items": tree.items,
                    "breadcrumb": tree.breadcrumb, "canRequestPermission": false]
        }, receive: { [weak self] state in
            guard let self = self, self.frontPID == pid, self.path == menuPath else { return }
            self.publish(state)
        }, failure: { [weak self] error in
            guard let self = self, self.frontPID == pid, self.path == menuPath else { return }
            self.publish(["available": false, "permission": permitted ? "authorized" : "notDetermined",
                          "frontPid": Int(pid), "items": [], "breadcrumb": [], "canRequestPermission": !permitted,
                          "lastErrorCode": error.code, "lastError": error.message])
        })
    }

    override func invoke(_ action: String, _ argument: Any) {
        precondition(Thread.isMainThread)
        switch action {
        case "requestPermission":
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            permission = AXIsProcessTrustedWithOptions(options)
            if !permission { fail(action, "permissionPending", "Enable Accessibility access in System Settings, then retry.") }
            else { refresh() }
        case "open":
            guard let fields = argument as? [String: Any], fields["pid"] as? Int == Int(frontPID),
                  let index = fields["index"] as? Int, index >= 0 else { fail(action, "invalidInput", "Invalid menu item."); return }
            path.append(index); refresh()
        case "back":
            guard !path.isEmpty else { return }; path.removeLast(); refresh()
        case "press":
            guard let args = argument as? [String: Any], let index = args["index"] as? Int,
                  let title = args["title"] as? String, !title.isEmpty,
                  index >= 0, args["pid"] as? Int == Int(frontPID), args["confirmed"] as? Bool == true else {
                fail(action, "confirmationRequired", "Choose a current menu item and confirm its action."); return
            }
            let pid = frontPID, parent = path
            perform(action, work: { _ in
                try AXMenuReader.press(pid: pid, path: parent, index: index, expectedTitle: title)
                return ["available": true, "permission": "authorized", "frontPid": Int(pid)]
            }, receive: { [weak self] _ in self?.refresh() })
        default: super.invoke(action, argument)
        }
    }

    override func stop() { path.removeAll(); super.stop() }
}

private enum AXMenuReader {
    struct Result { let items: [[String: Any]]; let breadcrumb: [String] }
    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let items = value as? [AXUIElement] else { return [] }
        return items
    }
    private static func string(_ element: AXUIElement, _ key: String) -> String {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return "" }
        return value as? String ?? ""
    }
    private static func menuChildren(_ item: AXUIElement) -> [AXUIElement] {
        let nodes = children(item)
        if nodes.count == 1, string(nodes[0], kAXRoleAttribute as String) == kAXMenuRole as String { return children(nodes[0]) }
        return nodes
    }
    private static func app(pid: pid_t) throws -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        guard AXUIElementSetMessagingTimeout(app, 1) == .success else { throw IntegrationFailure("timeout", "Accessibility target did not respond.") }
        return app
    }
    static func read(pid: pid_t, path: [Int]) throws -> Result {
        let app = try app(pid: pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &value) == .success,
              let value = value else { throw IntegrationFailure("unavailable", "The front app has no accessible menu bar.") }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { throw IntegrationFailure("invalidResponse", "Invalid AX menu element.") }
        let menuBar = value as! AXUIElement
        let top = children(menuBar)
        var current = top
        var breadcrumb: [String] = []
        for index in path {
            guard current.indices.contains(index) else { throw IntegrationFailure("stale", "Menu changed; refresh and retry.") }
            let item = current[index]; breadcrumb.append(string(item, kAXTitleAttribute as String))
            current = menuChildren(item)
        }
        let items = current.enumerated().compactMap { index, item -> [String: Any]? in
            let title = string(item, kAXTitleAttribute as String)
            guard !title.isEmpty else { return nil }
            var enabledValue: CFTypeRef?
            let hasEnabled = AXUIElementCopyAttributeValue(item, kAXEnabledAttribute as CFString, &enabledValue) == .success
            let enabled = (enabledValue as? NSNumber)?.boolValue ?? false
            return ["id": path.map(String.init).joined(separator: ".") + ".\(index)", "index": index,
                    "title": title, "hasChildren": !menuChildren(item).isEmpty,
                    "enabled": MenuIntegration.menuItemEnabledForTest(attributeAvailable: hasEnabled, enabled: enabled)]
        }
        return Result(items: items, breadcrumb: breadcrumb)
    }
    static func press(pid: pid_t, path: [Int], index: Int, expectedTitle: String) throws {
        guard let running = NSRunningApplication(processIdentifier: pid), !running.isTerminated else {
            throw IntegrationFailure("stale", "The target app has exited.")
        }
        let app = try app(pid: pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMenuBarAttribute as CFString, &value) == .success,
              let value = value else { throw IntegrationFailure("stale", "The app menu is no longer available.") }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { throw IntegrationFailure("invalidResponse", "Invalid AX menu element.") }
        let menuBar = value as! AXUIElement
        var current = children(menuBar)
        for part in path {
            guard current.indices.contains(part) else { throw IntegrationFailure("stale", "Menu changed; refresh and retry.") }
            current = menuChildren(current[part])
        }
        guard current.indices.contains(index) else { throw IntegrationFailure("stale", "Menu changed; refresh and retry.") }
        guard string(current[index], kAXTitleAttribute as String) == expectedTitle else {
            throw IntegrationFailure("stale", "Menu item changed; refresh and retry.")
        }
        var enabledValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(current[index], kAXEnabledAttribute as CFString, &enabledValue) == .success,
              (enabledValue as? NSNumber)?.boolValue == true else { throw IntegrationFailure("unsupported", "Menu item is disabled or its state is unknown.") }
        guard AXUIElementPerformAction(current[index], kAXPressAction as CFString) == .success else {
            throw IntegrationFailure("nativeFailure", "Accessibility could not activate this item.")
        }
    }
}
