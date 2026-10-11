import AppKit
import Foundation

final class DesktopIntegration: PillIntegration {
    static func requiresConfirmationForTest(_ action: String) -> Bool { ["lock", "sleep", "restart", "shutDown"].contains(action) }
    private let ownPID = ProcessInfo.processInfo.processIdentifier
    private let lockHelper: String
    private var frontApp = ""
    private var frontPid: pid_t = 0

    init(lockHelper: String = NSHomeDirectory() + "/.local/bin/omacosy-helper") {
        self.lockHelper = lockHelper
        super.init()
    }

    override func start(_ callback: @escaping ([String: Any]) -> Void) {
        precondition(Thread.isMainThread)
        super.start(callback)
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didActivateApplicationNotification) { [weak self] _ in self?.refresh() }
        refresh()
    }

    override func refresh() {
        precondition(Thread.isMainThread)
        let app = NSWorkspace.shared.frontmostApplication
        if let app = app, app.processIdentifier != ownPID {
            frontApp = app.localizedName ?? ""; frontPid = app.processIdentifier
        }
        if NSRunningApplication(processIdentifier: frontPid)?.isTerminated != false { frontApp = ""; frontPid = 0 }
        publish(["available": true, "frontAppKnown": frontPid > 0,
                 "frontApp": frontApp, "frontPid": frontPid,
                 "canLock": FileManager.default.isExecutableFile(atPath: lockHelper),
                 "canSleep": true, "canRestart": true, "canShutDown": true])
    }

    override func invoke(_ action: String, _ argument: Any) {
        precondition(Thread.isMainThread)
        let confirmed = (argument as? [String: Any])?["confirmed"] as? Bool == true
        switch action {
        case "openSettings": NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:")!)
        case "lock": run(action, confirmed: confirmed, path: lockHelper, args: ["lock"])
        case "sleep": run(action, confirmed: confirmed, path: "/usr/bin/pmset", args: ["sleepnow"])
        case "restart": run(action, confirmed: confirmed, path: "/usr/bin/osascript", args: ["-e", "tell application \"System Events\" to restart"])
        case "shutDown": run(action, confirmed: confirmed, path: "/usr/bin/osascript", args: ["-e", "tell application \"System Events\" to shut down"])
        default: super.invoke(action, argument)
        }
    }

    private func run(_ action: String, confirmed: Bool, path: String, args: [String]) {
        guard Self.requiresConfirmationForTest(action), confirmed else { fail(action, "confirmationRequired", "Confirm this power action first."); return }
        perform(action, work: { cancellation in
            _ = try CommandRunner.run(path, args, timeout: 10, cancellation: cancellation)
            return [:]
        }, receive: { [weak self] _ in self?.refresh() })
    }
}
