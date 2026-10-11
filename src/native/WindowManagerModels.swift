import Foundation
import CoreFoundation

struct WMWorkspace: Equatable {
    let id: String
    let monitorId: String
    let visible: Bool
    let windowCount: Int
}
struct WMMonitor: Equatable { let id: String; let name: String; let focused: Bool }
struct WMWindow: Equatable { let id: String; let workspace: String; let appName: String; let layout: String }
struct WMSnapshot: Equatable {
    let backend: String
    let focusedWorkspace: String
    let focusedWindow: String
    let workspaces: [WMWorkspace]
    let monitors: [WMMonitor]
    let windows: [WMWindow]
    var state: [String: Any] {
        ["available": true, "backend": backend, "canSwitch": backend == "AeroSpace" || backend == "OmniWM",
         "canFocus": backend == "AeroSpace", "focusedWorkspace": focusedWorkspace,
         "focusedWindow": focusedWindow,
         "workspaces": workspaces.map { ["id": $0.id, "monitorId": $0.monitorId, "visible": $0.visible, "windowCount": $0.windowCount] },
         "monitors": monitors.map { ["id": $0.id, "name": $0.name, "focused": $0.focused] },
         "windows": windows.map { ["id": $0.id, "workspace": $0.workspace, "appName": $0.appName, "layout": $0.layout] }]
    }
}

enum WMParseError: Error { case malformed(String) }
enum WindowManagerModels {
    static func json(_ data: Data) throws -> Any {
        do { return try JSONSerialization.jsonObject(with: data) }
        catch { throw WMParseError.malformed("Invalid JSON") }
    }
    static func rows(_ data: Data) throws -> [[String: Any]] {
        guard let rows = try json(data) as? [[String: Any]] else { throw WMParseError.malformed("Expected a JSON array") }
        return rows
    }
    static func numericID(_ value: Any?) -> String? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double.isFinite, double > 0, double.rounded(.towardZero) == double, double <= Double(UInt32.max) else { return nil }
        return String(UInt32(double))
    }
    static func snapshot(workspaces workspaceData: Data, monitors monitorData: Data,
                         windows windowData: Data, focusedWorkspace focusData: Data,
                         focusedWindow focusedWindowData: Data) throws -> WMSnapshot {
        let wsRows = try rows(workspaceData), monitorRows = try rows(monitorData), winRows = try rows(windowData)
        guard let focus = String(data: focusData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !focus.isEmpty,
              let focusedRows = try? rows(focusedWindowData), focusedRows.count <= 1 else { throw WMParseError.malformed("Invalid focused state") }
        let focusedId = focusedRows.first.flatMap { numericID($0["window-id"]) }
        var monitors: [String: WMMonitor] = [:]
        for row in monitorRows {
            guard let id = numericID(row["monitor-id"]), monitors[id] == nil,
                  let name = row["monitor-name"] as? String else { throw WMParseError.malformed("Invalid monitor row") }
            monitors[id] = WMMonitor(id: id, name: name, focused: false)
        }
        guard !monitors.isEmpty else { throw WMParseError.malformed("No monitors") }
        guard winRows.allSatisfy({ numericID($0["window-id"]) != nil && $0["workspace"] is String && $0["app-name"] is String && $0["window-layout"] is String }) else {
            throw WMParseError.malformed("Invalid window row")
        }
        guard Set(winRows.compactMap { numericID($0["window-id"]) }).count == winRows.count else { throw WMParseError.malformed("Duplicate window IDs") }
        let own = Set(["PillSpike", "omacosy-bar"])
        let windows = winRows.compactMap { row -> WMWindow? in
            let app = row["app-name"] as! String
            guard !own.contains(app) else { return nil }
            return WMWindow(id: numericID(row["window-id"])!, workspace: row["workspace"] as! String,
                            appName: app, layout: row["window-layout"] as! String)
        }
        guard workspacesContain(focus, wsRows) else { throw WMParseError.malformed("Focused workspace is missing") }
        if let focusedId = focusedId {
            guard let focusedRow = winRows.first(where: { numericID($0["window-id"]) == focusedId }),
                  focusedRow["workspace"] as? String == focus else { throw WMParseError.malformed("Focused window/workspace mismatch") }
        }
        let counts = Dictionary(grouping: windows, by: \.workspace).mapValues(\.count)
        var seen = Set<String>()
        let workspaces = try wsRows.map { row -> WMWorkspace in
            guard let id = row["workspace"] as? String, !id.isEmpty,
                  let monitor = numericID(row["monitor-id"]), monitors[monitor] != nil,
                  let visible = row["workspace-is-visible"] as? Bool, seen.insert(id).inserted else { throw WMParseError.malformed("Invalid or duplicate workspace") }
            return WMWorkspace(id: id, monitorId: monitor, visible: visible, windowCount: counts[id, default: 0])
        }
        guard workspaces.contains(where: { $0.id == focus && $0.visible }) else { throw WMParseError.malformed("Focused workspace is not visible") }
        let visibleByMonitor = Dictionary(workspaces.filter(\.visible).map { ($0.monitorId, $0.id) }, uniquingKeysWith: { first, _ in first })
        monitors = monitors.mapValues { monitor in WMMonitor(id: monitor.id, name: monitor.name, focused: visibleByMonitor[monitor.id] == focus) }
        let managedFocus = focusedId.flatMap { id in windows.first(where: { $0.id == id })?.id } ?? ""
        return WMSnapshot(backend: "AeroSpace", focusedWorkspace: focus, focusedWindow: managedFocus,
                          workspaces: workspaces, monitors: monitors.values.sorted { $0.id < $1.id }, windows: windows)
    }
    private static func workspacesContain(_ focus: String, _ rows: [[String: Any]]) -> Bool {
        rows.contains { $0["workspace"] as? String == focus }
    }
    static func omniSnapshot(workspaces workspaceData: Data, displays displayData: Data, windows windowData: Data,
                             focusedWorkspace explicitFocus: String? = nil) throws -> WMSnapshot {
        func payload(_ data: Data, key: String) throws -> [[String: Any]] {
            guard let envelope = try json(data) as? [String: Any], envelope["ok"] as? Bool == true,
                  let result = envelope["result"] as? [String: Any],
                  let body = result["payload"] as? [String: Any], let rows = body[key] as? [[String: Any]] else {
                throw WMParseError.malformed("Invalid OmniWM \(key) envelope")
            }
            return rows
        }
        let workspaceRows = try payload(workspaceData, key: "workspaces")
        let displayRows = try payload(displayData, key: "displays")
        let windowRows = try payload(windowData, key: "windows")
        var monitorMap: [String: WMMonitor] = [:], focus = explicitFocus ?? "", focusedMonitor = ""
        var workspaces: [WMWorkspace] = [], workspaceSeen = Set<String>()
        for display in displayRows {
            guard let monitor = display["id"] as? String, !monitor.isEmpty,
                  let active = (display["activeWorkspace"] as? [String: Any])?["rawName"] as? String else { throw WMParseError.malformed("Invalid OmniWM display") }
            if display["isCurrent"] as? Bool == true { focus = active; focusedMonitor = monitor }
            monitorMap[monitor] = WMMonitor(id: monitor, name: monitor, focused: display["isCurrent"] as? Bool == true)
            for row in workspaceRows {
                guard let name = row["rawName"] as? String,
                      let association = (row["display"] as? [String: Any])?["id"] as? String else { throw WMParseError.malformed("Invalid OmniWM workspace") }
                guard association == monitor else { continue }
                let id = monitor + "/" + name
                guard workspaceSeen.insert(id).inserted else { throw WMParseError.malformed("Duplicate OmniWM workspace") }
                workspaces.append(WMWorkspace(id: id, monitorId: monitor, visible: name == active, windowCount: 0))
            }
        }
        guard !focus.isEmpty, !workspaces.isEmpty,
              workspaceSeen.contains(where: { $0.hasSuffix("/" + focus) }) else { throw WMParseError.malformed("OmniWM focus is unknown") }
        let focusedWorkspaceId = focusedMonitor.isEmpty ? (workspaces.first(where: { $0.id.hasSuffix("/" + focus) })?.id ?? "") : "\(focusedMonitor)/\(focus)"
        var windows: [WMWindow] = [], counts: [String: Int] = [:]
        for row in windowRows {
            guard let workspace = (row["workspace"] as? [String: Any])?["rawName"] as? String,
                  let app = (row["app"] as? [String: Any])?["name"] as? String,
                  let mode = row["mode"] as? String else { throw WMParseError.malformed("Invalid OmniWM window") }
            // Floating is intentionally counted; it is managed and occupies its workspace.
            _ = mode
            if ["PillSpike", "omacosy-bar"].contains(app) { continue }
            let association = ((row["workspace"] as? [String: Any])?["display"] as? [String: Any])?["id"] as? String
            let scoped = workspaces.filter { $0.id.hasSuffix("/" + workspace) && (association == nil || $0.monitorId == association) }
            guard scoped.count == 1 else { throw WMParseError.malformed("Ambiguous OmniWM window display association") }
            guard !scoped.isEmpty else { throw WMParseError.malformed("Window workspace is unknown") }
            for item in scoped { counts[item.id, default: 0] += 1 }
            if let rawID = row["id"] as? String, !rawID.isEmpty, rawID.utf8.count <= 128,
               rawID.rangeOfCharacter(from: .controlCharacters) == nil, !["PillSpike", "omacosy-bar"].contains(app) {
                windows.append(WMWindow(id: rawID, workspace: workspace, appName: app, layout: mode))
            }
        }
        workspaces = workspaces.map { WMWorkspace(id: $0.id, monitorId: $0.monitorId, visible: $0.visible, windowCount: counts[$0.id, default: 0]) }
        return WMSnapshot(backend: "OmniWM", focusedWorkspace: focusedWorkspaceId, focusedWindow: "", workspaces: workspaces,
                          monitors: monitorMap.values.sorted { $0.id < $1.id }, windows: windows)
    }
    static func parseEventLines(_ buffer: inout Data, chunk: Data, maxBytes: Int = 1_048_576) throws -> [[String: Any]] {
        guard buffer.count + chunk.count <= maxBytes else { buffer.removeAll(); throw WMParseError.malformed("Event buffer limit exceeded") }
        buffer.append(chunk); var events: [[String: Any]] = []
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[..<newline]); buffer.removeSubrange(...newline)
            if line.isEmpty { continue }
            guard let event = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any], event["_event"] is String else {
                throw WMParseError.malformed("Invalid subscription event")
            }
            events.append(event)
        }
        return events
    }
    static func validatedWorkspace(_ id: String, in snapshot: WMSnapshot) -> Bool {
        snapshot.workspaces.contains(where: { $0.id == id })
    }
    static func omniWorkspaceArgument(_ id: String, in snapshot: WMSnapshot) throws -> String {
        guard snapshot.backend == "OmniWM", let workspace = snapshot.workspaces.first(where: { $0.id == id }) else {
            throw IntegrationFailure("staleIdentifier", "Workspace is not in the current OmniWM snapshot.")
        }
        let prefix = workspace.monitorId + "/"
        guard id.hasPrefix(prefix) else { throw IntegrationFailure("invalidInput", "Invalid OmniWM workspace identifier.") }
        let name = String(id.dropFirst(prefix.count))
        guard !name.isEmpty, name.utf8.count <= 256, name.rangeOfCharacter(from: .controlCharacters) == nil else {
            throw IntegrationFailure("invalidInput", "Invalid OmniWM workspace name.")
        }
        return name
    }
    static func validatedWindow(_ id: String, in snapshot: WMSnapshot) -> Bool { snapshot.backend == "AeroSpace" && numericID(NSNumber(value: Int64(id) ?? 0)) == id && snapshot.windows.contains { $0.id == id } }
}

#if WINDOW_MANAGER_TESTS
func runWindowManagerTests() throws {
    func check(_ condition: @autoclosure () -> Bool, _ message: String) throws { if !condition() { throw NSError(domain: "WMTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) } }
    let ws = Data(#"[{"workspace":"4","monitor-id":1,"workspace-is-visible":true},{"workspace":"web","monitor-id":1,"workspace-is-visible":false},{"workspace":"empty","monitor-id":1,"workspace-is-visible":false}]"#.utf8)
    let monitors = Data(#"[{"monitor-id":1,"monitor-name":"Built-in Retina Display"}]"#.utf8)
    let windows = Data(#"[{"window-id":12,"workspace":"4","app-name":"Ghostty","window-layout":"h_tiles"},{"window-id":13,"workspace":"web","app-name":"Finder","window-layout":"floating"},{"window-id":14,"workspace":"web","app-name":"PillSpike","window-layout":"floating"}]"#.utf8)
    let focusWindow = Data(#"[{"window-id":12,"app-name":"Ghostty","window-title":"terminal"}]"#.utf8)
    let snapshot = try WindowManagerModels.snapshot(workspaces: ws, monitors: monitors, windows: windows, focusedWorkspace: Data("4\n".utf8), focusedWindow: focusWindow)
    try check(snapshot.workspaces.count == 3 && snapshot.workspaces.last?.id == "empty", "named and empty workspace IDs preserved")
    try check(snapshot.workspaces[1].windowCount == 1, "floating window counted, own utility excluded")
    try check(snapshot.windows.count == 2 && snapshot.focusedWindow == "12", "window model and focus parsed")
    try check(WindowManagerModels.numericID("12") == nil && WindowManagerModels.numericID(NSNumber(value: 12.5)) == nil
              && WindowManagerModels.numericID(NSNumber(value: true)) == nil, "window IDs must be positive integral JSON numbers")
    let ownFocus = Data(#"[{"window-id":14,"app-name":"PillSpike"}]"#.utf8)
    let ownFocusedWS = Data(#"[{"workspace":"4","monitor-id":1,"workspace-is-visible":false},{"workspace":"web","monitor-id":1,"workspace-is-visible":true},{"workspace":"empty","monitor-id":1,"workspace-is-visible":false}]"#.utf8)
    let ownFocusedSnapshot = try WindowManagerModels.snapshot(workspaces: ownFocusedWS, monitors: monitors, windows: windows,
        focusedWorkspace: Data("web".utf8), focusedWindow: ownFocus)
    try check(ownFocusedSnapshot.focusedWindow.isEmpty && ownFocusedSnapshot.windows.allSatisfy { $0.appName != "PillSpike" }, "own focused utility is not exposed as managed focus")
    try check(WindowManagerModels.validatedWorkspace("web", in: snapshot) && !WindowManagerModels.validatedWorkspace("missing", in: snapshot), "workspace actions validated")
    try check(!WindowManagerModels.validatedWindow("14", in: snapshot) && !WindowManagerModels.validatedWindow("../x", in: snapshot), "stale and malformed windows rejected")
    var buffer = Data()
    let firstEvents = try WindowManagerModels.parseEventLines(&buffer, chunk: Data("{\"_event\":\"focus-changed\"}\n{\"_event\":\"mode-changed\"}".utf8))
    try check(firstEvents.count == 1 && !buffer.isEmpty, "split event frame buffered")
    let secondEvents = try WindowManagerModels.parseEventLines(&buffer, chunk: Data("\n".utf8))
    try check(secondEvents.count == 1 && buffer.isEmpty, "combined event lines parsed")
    let emptyFocused = try WindowManagerModels.snapshot(workspaces: Data(#"[{"workspace":"empty","monitor-id":1,"workspace-is-visible":true}]"#.utf8), monitors: monitors, windows: Data("[]".utf8), focusedWorkspace: Data("empty".utf8), focusedWindow: Data("[]".utf8))
    try check(emptyFocused.focusedWorkspace == "empty" && emptyFocused.focusedWindow.isEmpty && emptyFocused.workspaces[0].windowCount == 0, "empty focused workspace without invented window")
    let omniWorkspaces = Data(#"{"ok":true,"result":{"payload":{"workspaces":[{"rawName":"work","display":{"id":"m1"}},{"rawName":"empty","display":{"id":"m1"}}]}}}"#.utf8)
    let omniDisplays = Data(#"{"ok":true,"result":{"payload":{"displays":[{"id":"m1","isCurrent":true,"activeWorkspace":{"rawName":"empty"}}]}}}"#.utf8)
    let omniWindows = Data(#"{"ok":true,"result":{"payload":{"windows":[{"id":"window:any/id","workspace":{"rawName":"work"},"app":{"name":"Ghostty"},"mode":"floating"},{"workspace":{"rawName":"work"},"app":{"name":"Finder"},"mode":"tiled"}]}}}"#.utf8)
    let omni = try WindowManagerModels.omniSnapshot(workspaces: omniWorkspaces, displays: omniDisplays, windows: omniWindows)
    try check(omni.focusedWorkspace == "m1/empty" && omni.workspaces.count == 2, "OmniWM named and empty workspaces")
    try check(omni.workspaces.first(where: { $0.id == "m1/work" })?.windowCount == 2 && omni.windows.count == 1, "OmniWM counts floating and allows missing IDs")
    try check(omni.state["canFocus"] as? Bool == false && WindowManagerModels.validatedWorkspace("m1/work", in: omni), "OmniWM only validates workspace action")
    let rawWorkspace = try WindowManagerModels.omniWorkspaceArgument("m1/work", in: omni)
    try check(rawWorkspace == "work", "OmniWM raw name remains one argument")
    let injected = "work; touch /tmp/pill-test"
    let injectedSnapshot = try WindowManagerModels.omniSnapshot(workspaces: Data("{\"ok\":true,\"result\":{\"payload\":{\"workspaces\":[{\"rawName\":\"\(injected)\",\"display\":{\"id\":\"m1\"}}]}}}".utf8), displays: Data("{\"ok\":true,\"result\":{\"payload\":{\"displays\":[{\"id\":\"m1\",\"isCurrent\":true,\"activeWorkspace\":{\"rawName\":\"\(injected)\"}}]}}}".utf8), windows: Data("{\"ok\":true,\"result\":{\"payload\":{\"windows\":[]}}}".utf8))
    let injectedArgument = try WindowManagerModels.omniWorkspaceArgument("m1/\(injected)", in: injectedSnapshot)
    try check(injectedArgument == injected, "arbitrary workspace text remains a single validated argument")
    for bad in [Data("[]".utf8), Data("oops".utf8)] {
        do { _ = try WindowManagerModels.snapshot(workspaces: bad, monitors: monitors, windows: windows, focusedWorkspace: Data("4".utf8), focusedWindow: focusWindow); throw NSError(domain: "WMTests", code: 2) }
        catch is WMParseError { }
    }
}
#endif
