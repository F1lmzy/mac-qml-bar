import AppKit
import Foundation

final class WindowManagerIntegration: PillIntegration {
    private(set) var snapshot: WMSnapshot?
    private var revision: UInt64 = 0
    private var refreshPending = false
    private var eventRefreshPending = false
    private var focusEventRevision: UInt64 = 0
    private var backend = ""
    private var eventBuffer = Data()
    private var stream: CommandStream?
    private var streamGeneration = 0
    private var refreshAgain = false
    private var reconnectTimer: Timer?
    private var reconcileTimer: Timer?
    private var reconnectDelay: TimeInterval = 1
    private var lastManagedFocus = ""
    private var modelLease = IntegrationCancellation()
    private let aerospacePath: String
    private let omniPath: String
    private let backendResolver: () -> String
    private let runner: (String, [String], IntegrationCancellation) throws -> Data
    private let subscriptionsEnabled: Bool

    init(aerospacePath: String? = nil, omniPath: String? = nil,
         backendResolver: @escaping () -> String = WindowManagerIntegration.detectBackend,
         runner: @escaping (String, [String], IntegrationCancellation) throws -> Data = { path, args, cancel in try CommandRunner.run(path, args, timeout: 4, cancellation: cancel).stdout },
         subscriptionsEnabled: Bool = true) {
        self.backendResolver = backendResolver; self.runner = runner; self.subscriptionsEnabled = subscriptionsEnabled
        self.aerospacePath = aerospacePath ?? ["/opt/homebrew/bin/aerospace", "/usr/local/bin/aerospace"].first(where: FileManager.default.isExecutableFile(atPath:)) ?? "/opt/homebrew/bin/aerospace"
        self.omniPath = omniPath ?? ["/opt/homebrew/bin/omniwmctl", "/Applications/OmniWM.app/Contents/MacOS/omniwmctl"].first(where: FileManager.default.isExecutableFile(atPath:)) ?? "/opt/homebrew/bin/omniwmctl"
        super.init()
    }
    override func start(_ callback: @escaping ([String: Any]) -> Void) {
        precondition(Thread.isMainThread)
        backend = selectedBackend()
        super.start(callback)
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didLaunchApplicationNotification) { [weak self] _ in self?.selectBackend() }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didTerminateApplicationNotification) { [weak self] _ in self?.selectBackend() }
        reconcileTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in self?.selectBackend() }
        selectBackend()
    }
    private func selectedBackend() -> String {
        backendResolver()
    }
    static func detectBackend() -> String {
        !NSRunningApplication.runningApplications(withBundleIdentifier: "com.barut.OmniWM").isEmpty ? "OmniWM" : "AeroSpace"
    }
    private func selectBackend() {
        precondition(Thread.isMainThread)
        let next = selectedBackend()
        guard next != backend else {
            if next == "AeroSpace" && stream == nil { startAeroSpaceStream() }
            refresh(); return
        }
        modelLease.cancel(); modelLease = IntegrationCancellation()
        revision &+= 1; backend = next; refreshPending = false; eventRefreshPending = false
        lastManagedFocus = ""
        stream?.stop(); stream = nil; eventBuffer.removeAll(); reconnectTimer?.invalidate(); reconnectTimer = nil
        reconnectDelay = 1; snapshot = nil
        if next == "AeroSpace" { startAeroSpaceStream() }
        refresh()
    }
    override func refresh() {
        precondition(Thread.isMainThread)
        guard running else { return }
        if selectedBackend() != backend { selectBackend(); return }
        if refreshPending { refreshAgain = true; return }
        refreshPending = true; revision &+= 1
        let token = revision, focusToken = focusEventRevision, selected = backend, path = selected == "OmniWM" ? omniPath : aerospacePath, runner = self.runner
        guard FileManager.default.isExecutableFile(atPath: path) else {
            refreshPending = false; invalidateSnapshot(selected, "unavailable", "Window-manager CLI is unavailable."); return
        }
        perform("snapshot", work: { cancellation in
            func run(_ args: [String]) throws -> Data { try runner(path, args, cancellation) }
            let parsed: WMSnapshot
            if selected == "AeroSpace" {
                let ws = try run(["list-workspaces", "--all", "--format", "%{workspace} %{monitor-id} %{workspace-is-visible}", "--json"])
                let monitors = try run(["list-monitors", "--json"])
                let windows = try run(["list-windows", "--all", "--format", "%{window-id} %{workspace} %{app-name} %{window-layout}", "--json"])
                let focusedWS = try run(["list-workspaces", "--focused", "--json"])
                let focusedWindow = try run(["list-windows", "--focused", "--json"])
                guard let focus = try WindowManagerModels.rows(focusedWS).first?["workspace"] as? String else {
                    throw IntegrationFailure("invalidResponse", "No focused workspace returned.")
                }
                parsed = try WindowManagerModels.snapshot(workspaces: ws, monitors: monitors, windows: windows,
                    focusedWorkspace: Data(focus.utf8), focusedWindow: focusedWindow)
            } else {
                let ws = try run(["query", "workspaces", "--fields", "raw-name,display", "--format", "json"])
                let displays = try run(["query", "displays", "--format", "json"])
                let windows = try run(["query", "windows", "--fields", "workspace,app,mode", "--format", "json"])
                parsed = try WindowManagerModels.omniSnapshot(workspaces: ws, displays: displays, windows: windows)
            }
            return parsed.state
        }, receive: { [weak self] state in
            guard let self = self, self.revision == token, self.backend == selected else { return }
            self.refreshPending = false
            // A focus notification is newer than a snapshot already in flight.
            // Never let that older response flash the previous workspace again.
            if self.focusEventRevision != focusToken {
                self.refreshAgain = false; self.refresh(); return
            }
            let focused = state["focusedWindow"] as? String ?? ""
            if !focused.isEmpty { self.lastManagedFocus = focused }
            if let parsed = try? Self.decodeSnapshot(state) {
                if self.snapshot != parsed { self.modelLease.cancel(); self.modelLease = IntegrationCancellation() }
                self.snapshot = parsed
                var published = state
                if parsed.focusedWindow.isEmpty, !self.lastManagedFocus.isEmpty,
                   parsed.windows.contains(where: { $0.id == self.lastManagedFocus }) {
                    published["focusedWindow"] = self.lastManagedFocus
                }
                self.publish(published)
                if self.refreshAgain { self.refreshAgain = false; self.refresh() }
            } else {
                self.snapshot = nil
                self.invalidateSnapshot(selected, "invalidResponse", "Snapshot failed model validation.")
            }
        }, failure: { [weak self] error in
            guard let self = self, self.revision == token, self.backend == selected else { return }
            self.refreshPending = false
            if self.focusEventRevision != focusToken {
                self.refreshAgain = false; self.refresh(); return
            }
            self.snapshot = nil
            self.invalidateSnapshot(selected, error.code, error.message)
            if self.refreshAgain { self.refreshAgain = false; self.refresh() }
        })
    }
    private static func decodeSnapshot(_ state: [String: Any]) throws -> WMSnapshot {
        let workspaces = state["workspaces"] as? [[String: Any]] ?? []
        let monitors = state["monitors"] as? [[String: Any]] ?? []
        let windows = state["windows"] as? [[String: Any]] ?? []
        guard let backend = state["backend"] as? String,
              let focus = state["focusedWorkspace"] as? String,
              let focusedWindow = state["focusedWindow"] as? String else { throw WMParseError.malformed("Incomplete state") }
        return WMSnapshot(backend: backend, focusedWorkspace: focus, focusedWindow: focusedWindow,
            workspaces: workspaces.compactMap { row in
                guard let id = row["id"] as? String, let monitor = row["monitorId"] as? String,
                      let visible = row["visible"] as? Bool, let count = row["windowCount"] as? Int else { return nil }
                return WMWorkspace(id: id, monitorId: monitor, visible: visible, windowCount: count)
            }, monitors: monitors.compactMap { row in
                guard let id = row["id"] as? String, let name = row["name"] as? String,
                      let focused = row["focused"] as? Bool else { return nil }
                return WMMonitor(id: id, name: name, focused: focused)
            }, windows: windows.compactMap { row in
                guard let id = row["id"] as? String, let workspace = row["workspace"] as? String,
                      let app = row["appName"] as? String, let layout = row["layout"] as? String else { return nil }
                return WMWindow(id: id, workspace: workspace, appName: app, layout: layout)
            })
    }
    private func invalidateSnapshot(_ selected: String, _ code: String, _ message: String) {
        modelLease.cancel(); modelLease = IntegrationCancellation()
        snapshot = nil
        publish(["available": false, "backend": selected, "canSwitch": false, "canFocus": false,
                 "subscribeSupported": selected == "AeroSpace", "focusedWorkspace": "",
                 "focusedWindow": "", "workspaces": [], "monitors": [], "windows": [],
                 "lastErrorCode": code, "lastError": message])
    }
    private func startAeroSpaceStream() {
        guard running, subscriptionsEnabled, backend == "AeroSpace", stream == nil else { return }
        let child = CommandStream(path: aerospacePath, arguments: ["subscribe", "--all"])
        stream = child; eventBuffer.removeAll(); streamGeneration += 1
        let token = streamGeneration
        let onData: (Data) -> Void = { [weak self] chunk in
            guard let self = self, self.running, self.streamGeneration == token else { return }
            self.reconnectDelay = 1; self.receiveEvents(chunk)
        }
        let onTermination: () -> Void = { [weak self] in
            guard let self = self, self.running, self.streamGeneration == token else { return }
            self.stream = nil; self.scheduleReconnect()
        }
        child.start(onData: onData, onTermination: onTermination)
    }
    func receiveEvents(_ chunk: Data) {
        precondition(Thread.isMainThread)
        guard running, backend == "AeroSpace" else { return }
        do {
            let events = try WindowManagerModels.parseEventLines(&eventBuffer, chunk: chunk)
            var urgent = false
            for event in events where ["focused-workspace-changed", "focused-monitor-changed", "focus-changed"].contains(event["_event"] as? String ?? "") {
                urgent = true; focusEventRevision &+= 1
                // This is observed server state, not an optimistic click result.
                // Publish the highlight now; reconcile occupancy/monitors later.
                guard let id = event["workspace"] as? String, let current = snapshot,
                      WindowManagerModels.validatedWorkspace(id, in: current) else { continue }
                var window = id == current.focusedWorkspace ? current.focusedWindow : ""
                if let candidate = WindowManagerModels.numericID(event["windowId"]),
                   current.windows.contains(where: { $0.id == candidate && $0.workspace == id }) { window = candidate }
                if id != current.focusedWorkspace { lastManagedFocus = "" }
                let next = WMSnapshot(backend: current.backend, focusedWorkspace: id, focusedWindow: window,
                    workspaces: current.workspaces, monitors: current.monitors, windows: current.windows)
                if next != current {
                    modelLease.cancel(); modelLease = IntegrationCancellation()
                    snapshot = next; publish(next.state)
                }
            }
            if urgent { refresh() }
            else if !events.isEmpty { scheduleEventRefresh() }
        } catch {
            stream?.stop(); stream = nil; eventBuffer.removeAll(); scheduleReconnect()
        }
    }
    private func scheduleEventRefresh() {
        guard !eventRefreshPending else { return }
        eventRefreshPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(120)) { [weak self] in
            guard let self = self, self.running else { return }
            self.eventRefreshPending = false; self.refresh()
        }
    }
    private func streamEnded(_ ended: CommandStream) {
        precondition(Thread.isMainThread)
        guard stream === ended else { return }
        stream = nil; scheduleReconnect()
    }
    private func scheduleReconnect() {
        guard running, backend == "AeroSpace", reconnectTimer == nil else { return }
        let delay = reconnectDelay; reconnectDelay = min(30, reconnectDelay * 2)
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self else { return }; self.reconnectTimer = nil
            self.startAeroSpaceStream()
        }
    }
    override func invoke(_ action: String, _ argument: Any) {
        precondition(Thread.isMainThread)
        guard let model = snapshot, model.backend == backend else { fail(action, "unavailable", "No confirmed current manager snapshot."); return }
        let expectedBackend = backend, lease = modelLease
        let args: [String]
        switch action {
        case "switchWorkspace":
            guard let id = argument as? String, WindowManagerModels.validatedWorkspace(id, in: model) else {
                fail(action, "staleIdentifier", "Workspace is not in the current snapshot."); return
            }
            if backend == "AeroSpace" { args = ["workspace", "--", id] }
            else {
                do { args = ["workspace", "focus-name", try WindowManagerModels.omniWorkspaceArgument(id, in: model)] }
                catch let error as IntegrationFailure { fail(action, error.code, error.message); return }
                catch { fail(action, "invalidInput", String(describing: error)); return }
            }
        case "focusWindow":
            guard backend == "AeroSpace", let id = argument as? String,
                  WindowManagerModels.validatedWindow(id, in: model) else {
                fail(action, "unsupported", "Window focus is unavailable for this manager or stale ID."); return
            }
            args = ["focus", "--window-id", id]
        default: fail(action, "unsupported", "Unknown window-manager action."); return
        }
        let path = backend == "AeroSpace" ? aerospacePath : omniPath, runner = self.runner, resolver = backendResolver
        perform(action, work: { cancellation in
            guard resolver() == expectedBackend, !cancellation.isCanceled, !lease.isCanceled,
                  FileManager.default.isExecutableFile(atPath: path) else {
                throw IntegrationFailure("staleIdentifier", "Manager changed before action execution.")
            }
            // Revalidate against the manager immediately before executing, not
            // just the earlier UI model. A model change cancels this lease.
            if action == "focusWindow" {
                let data = try runner(path, ["list-windows", "--all", "--format", "%{window-id} %{workspace} %{app-name} %{window-layout}", "--json"], cancellation)
                let id = args.last!, expected = model.windows.first { $0.id == id }!
                guard let row = try WindowManagerModels.rows(data).first(where: { WindowManagerModels.numericID($0["window-id"]) == id }),
                      row["workspace"] as? String == expected.workspace, row["app-name"] as? String == expected.appName,
                      row["window-layout"] as? String == expected.layout else { throw IntegrationFailure("staleIdentifier", "Window identity changed before focus.") }
            } else if expectedBackend == "AeroSpace" {
                let data = try runner(path, ["list-workspaces", "--all", "--json"], cancellation)
                guard try WindowManagerModels.rows(data).contains(where: { $0["workspace"] as? String == args.last }) else { throw IntegrationFailure("staleIdentifier", "Workspace is no longer available.") }
            }
            guard !lease.isCanceled else { throw IntegrationFailure("staleIdentifier", "Snapshot changed before the action.") }
            _ = try runner(path, args, cancellation)
            return [:]
        }, receive: { [weak self] _ in
            guard let self = self, self.backend == expectedBackend else { return }
            self.refresh()
        })
    }
    override func stop() {
        precondition(Thread.isMainThread)
        stream?.stop(); stream = nil
        reconnectTimer?.invalidate(); reconnectTimer = nil
        reconcileTimer?.invalidate(); reconcileTimer = nil
        modelLease.cancel(); modelLease = IntegrationCancellation()
        snapshot = nil; refreshPending = false; eventRefreshPending = false; refreshAgain = false
        streamGeneration += 1
        eventBuffer.removeAll(); revision &+= 1
        super.stop()
    }
}
