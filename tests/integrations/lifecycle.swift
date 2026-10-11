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
