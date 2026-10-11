import Foundation

private final class EventFixture {
    let lock = NSLock(), blocked = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
    var hold = false, focus = "4", queryFocus = "4"
    func run(_ args: [String]) throws -> Data {
        if args.first == "list-workspaces", !args.contains("--focused") {
            lock.lock(); queryFocus = focus; let shouldBlock = hold; hold = false; lock.unlock()
            if shouldBlock { blocked.signal(); _ = release.wait(timeout: .now() + 2) }
        }
        lock.lock(); defer { lock.unlock() }
        let rows: [[String: Any]]
        switch args.first {
        case "list-workspaces":
            rows = args.contains("--focused") ? [["workspace": queryFocus]] :
                ["4", "web"].map { ["workspace": $0, "monitor-id": 1, "workspace-is-visible": $0 == queryFocus] }
        case "list-monitors": rows = [["monitor-id": 1, "monitor-name": "TEST"]]
        case "list-windows": rows = []
        default: fatalError("Unexpected fixture command")
        }
        return try JSONSerialization.data(withJSONObject: rows)
    }
}
func runWorkspaceEventTests() {
    let stream = CommandStream(path: "/usr/bin/python3", arguments: ["-u", "-c",
        "import sys,time; print('{\"_event\":\"focused-workspace-changed\"}', flush=True); time.sleep(3)"])
    var received = Data()
    stream.start(onData: { received.append($0) }, onTermination: {})
    let deadline = Date().addingTimeInterval(1)
    while received.isEmpty, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
    stream.stop()
    precondition(!received.isEmpty, "Workspace event buffered until pipe fill/child exit")
    precondition(String(data: received, encoding: .utf8)?.contains("focused-workspace-changed") == true)

    let driver = EventFixture()
    let service = WindowManagerIntegration(aerospacePath: "/bin/echo",
        backendResolver: { "AeroSpace" }, runner: { _, args, _ in try driver.run(args) }, subscriptionsEnabled: false)
    var state: [String: Any] = [:], observed: [String] = []
    service.start { state = $0; observed.append($0["focusedWorkspace"] as? String ?? "") }
    func spin(_ condition: () -> Bool) {
        let end = Date().addingTimeInterval(3)
        while !condition(), Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
        precondition(condition(), "Workspace event fixture timed out")
    }
    spin { state["focusedWorkspace"] as? String == "4" }
    driver.lock.lock(); driver.hold = true; driver.lock.unlock()
    service.refresh()
    precondition(driver.blocked.wait(timeout: .now() + 1) == .success)
    // A split NDJSON line must not publish until complete.
    service.receiveEvents(Data("{\"_event\":\"focused-workspace-changed\",\"workspace\":\"web\"}".utf8))
    precondition(state["focusedWorkspace"] as? String == "4")
    service.receiveEvents(Data("\n".utf8))
    precondition(state["focusedWorkspace"] as? String == "web", "Highlight waits for debounce/full snapshot")
    observed.removeAll()
    driver.lock.lock(); driver.focus = "web"; driver.lock.unlock()
    driver.release.signal()
    spin { service.snapshot?.focusedWorkspace == "web" && !observed.isEmpty }
    precondition(!observed.contains("4"), "Old in-flight snapshot reverted immediate workspace highlight")
    service.stop()
    service.receiveEvents(Data("{\"_event\":\"focused-workspace-changed\",\"workspace\":\"4\"}\n".utf8))
    precondition(state["focusedWorkspace"] as? String == "web", "Stopped subscription delivered")
    print("PASS: short subscription events, immediate highlight and stale snapshot suppression")
}
