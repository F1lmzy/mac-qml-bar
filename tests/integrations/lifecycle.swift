import Foundation

private final class WMFixture {
    private let lock = NSLock()
    private var selected = "AeroSpace", windowApp = "Ghostty"
    var backend: String { get { lock.lock(); defer { lock.unlock() }; return selected } set { lock.lock(); selected = newValue; lock.unlock() } }
    private(set) var focusWrites = 0
    var blockWindowRead = false
    let blocked = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
    func changeWindowIdentity() { lock.lock(); windowApp = "Finder"; lock.unlock() }
    func run(_ path: String, _ args: [String], _ cancel: IntegrationCancellation) throws -> Data {
        if args.first == "list-windows" && !args.contains("--focused"), blockWindowRead {
            blocked.signal(); _ = release.wait(timeout: .now() + 2)
        }
        lock.lock(); defer { lock.unlock() }
        func json(_ object: Any) throws -> Data { try JSONSerialization.data(withJSONObject: object) }
        func envelope(_ key: String, _ value: Any) throws -> Data { try json(["ok": true, "result": ["payload": [key: value]]]) }
        switch args.first {
        case "list-workspaces":
            if args.contains("--focused") { return try json([["workspace": "4"]]) }
            return try json([["workspace": "4", "monitor-id": 1, "workspace-is-visible": true]])
        case "list-monitors": return try json([["monitor-id": 1, "monitor-name": "TEST"]])
        case "list-windows":
            if args.contains("--focused") { return try json([["window-id": 12]]) }
            return try json([["window-id": 12, "workspace": "4", "app-name": windowApp, "window-layout": "floating"]])
        case "focus": focusWrites += 1; return Data()
        case "query":
            if args[1] == "workspaces" { return try envelope("workspaces", [["rawName": "empty", "display": ["id": "m1"]]]) }
            if args[1] == "displays" { return try envelope("displays", [["id": "m1", "isCurrent": true, "activeWorkspace": ["rawName": "empty"]]]) }
            return try envelope("windows", [])
        default: throw IntegrationFailure("testFailure", "Unexpected fixture command.")
        }
    }
}
// Mirrors AeroSpace's empty-workspace CLI behavior, not the parser-only [] fixture.
private final class EmptyWorkspaceFixture {
    private let lock = NSLock()
    private var focus = "4"
    private var focusedError: IntegrationFailure?
    private var ownUtilityFocused = false
    func setFocus(_ workspace: String, error: IntegrationFailure? = nil, ownUtility: Bool = false) {
        lock.lock(); defer { lock.unlock() }
        focus = workspace; focusedError = error; ownUtilityFocused = ownUtility
    }
    func run(_ args: [String]) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        let rows: [[String: Any]]
        switch args.first {
        case "list-workspaces":
            rows = args.contains("--focused") ? [["workspace": focus]] :
                ["4", "empty"].map { ["workspace": $0, "monitor-id": 1, "workspace-is-visible": $0 == focus] }
        case "list-monitors": rows = [["monitor-id": 1, "monitor-name": "TEST"]]
        case "list-windows":
            if args.contains("--focused") {
                if let error = focusedError { throw error }
                if focus == "empty" { throw IntegrationFailure("nativeFailure", "No window is focused\n") }
                rows = [["window-id": ownUtilityFocused ? 14 : 12]]
            } else {
                rows = [["window-id": 12, "workspace": "4", "app-name": "Ghostty", "window-layout": "h_tiles"]]
                    + (ownUtilityFocused ? [["window-id": 14, "workspace": "4", "app-name": "PillSpike", "window-layout": "floating"]] : [])
            }
        default: throw IntegrationFailure("testFailure", "Unexpected fixture command.")
        }
        return try JSONSerialization.data(withJSONObject: rows)
    }
}

func runEmptyWorkspaceTests() {
    func spin(_ predicate: () -> Bool) {
        let deadline = Date().addingTimeInterval(3)
        while !predicate(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
        precondition(predicate(), "empty workspace fixture timed out")
    }
    let driver = EmptyWorkspaceFixture()
    let service = WindowManagerIntegration(aerospacePath: "/bin/echo", backendResolver: { "AeroSpace" },
        runner: { _, args, _ in try driver.run(args) }, subscriptionsEnabled: false)
    defer { service.stop() }
    var state: [String: Any] = [:]
    service.start { state = $0 }
    spin { state["focusedWindow"] as? String == "12" }
    driver.setFocus("4", ownUtility: true); service.refresh()
    spin { service.snapshot?.focusedWindow == "" }
    precondition(state["focusedWindow"] as? String == "12", "Same-workspace utility focus lost the previous app")
    // No subscription event: polling must not carry focus from the old workspace.
    driver.setFocus("empty"); service.refresh()
    spin { state["focusedWorkspace"] as? String == "empty" && state["available"] as? Bool == true }
    precondition((state["workspaces"] as? [[String: Any]])?.count == 2)
    precondition(state["focusedWindow"] as? String == "", "Window focus leaked from another workspace")
    precondition(service.snapshot?.workspaces.first(where: { $0.id == "empty" })?.windowCount == 0)
    precondition(service.snapshot?.windows.count == 1, "Windows on other workspaces were discarded")
    precondition(state["lastErrorCode"] as? String == "")

    driver.setFocus("4"); service.refresh()
    spin { state["focusedWindow"] as? String == "12" }
    for failure in [IntegrationFailure("timeout", "Command timed out."),
                    IntegrationFailure("permissionDenied", "No window is focused"),
                    IntegrationFailure("nativeFailure", "Server is not running")] {
        driver.setFocus("empty", error: failure); service.refresh()
        spin { state["available"] as? Bool == false && state["lastErrorCode"] as? String == failure.code }
        precondition(service.snapshot == nil, "Real CLI failure was ignored")
        driver.setFocus("4"); service.refresh()
        spin { state["focusedWindow"] as? String == "12" }
    }
    // Startup on an empty workspace must also retain workspace rows.
    service.stop()
    driver.setFocus("empty"); service.start { state = $0 }
    spin { state["focusedWorkspace"] as? String == "empty" && state["available"] as? Bool == true }
    precondition((state["workspaces"] as? [[String: Any]])?.count == 2)
    print("PASS: empty AeroSpace workspace retains dots, clears window focus and preserves real failures")
}

func runLifecycleTests() throws {
    func spin(_ predicate: () -> Bool) {
        let deadline = Date().addingTimeInterval(4)
        while !predicate(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        precondition(predicate(), "native lifecycle fixture timed out")
    }
    let driver = WMFixture()
    let service = WindowManagerIntegration(aerospacePath: "/bin/echo", omniPath: "/bin/echo",
        backendResolver: { driver.backend }, runner: { try driver.run($0, $1, $2) }, subscriptionsEnabled: false)
    var state: [String: Any] = [:]
    service.start { state = $0 }
    spin { state["backend"] as? String == "AeroSpace" && state["available"] as? Bool == true }
    driver.blockWindowRead = true
    service.invoke("focusWindow", "12")
    precondition(driver.blocked.wait(timeout: .now() + 2) == .success)
    driver.changeWindowIdentity(); driver.release.signal()
    spin { state["lastErrorCode"] as? String == "staleIdentifier" }
    precondition(driver.focusWrites == 0, "stale window focus was executed")
    driver.blockWindowRead = false
    driver.backend = "OmniWM"; service.refresh()
    spin { state["backend"] as? String == "OmniWM" && state["available"] as? Bool == true }
    precondition(state["focusedWorkspace"] as? String == "m1/empty")
    service.stop()
    let cancellation = IntegrationCancellation()
    var canceled = false
    cancellation.install { canceled = true }; cancellation.cancel()
    precondition(canceled && cancellation.isCanceled)
    print("PASS: WM backend replacement and stale-action lifecycle fixtures")
}
