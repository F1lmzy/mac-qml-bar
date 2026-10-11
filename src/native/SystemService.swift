import Foundation

@objc(PillSystemService)
public final class SystemService: NSObject {
    @objc public private(set) static var liveInstanceCount = 0
    private let fake: Bool
    private var integrations: [String: PillIntegration] = [:]
    private var callback: ((String, NSDictionary) -> Void)?
    private var pendingBrightness: DispatchWorkItem?
    @objc public init(fake: Bool) {
        precondition(Thread.isMainThread); self.fake = fake; super.init(); Self.liveInstanceCount += 1
    }
    @objc public func start(callback: @escaping (String, NSDictionary) -> Void) {
        precondition(Thread.isMainThread); stop(); self.callback = callback
        if fake {
            for domain in FakeIntegration.domains { integrations[domain] = FakeIntegration(domain) }
        } else {
            integrations = ["brightness": BrightnessIntegration(), "display": DisplayIntegration(), "battery": BatteryIntegration(),
                            "wifi": WifiIntegration(), "bluetooth": BluetoothIntegration(), "spotify": SpotifyIntegration(),
                            "desktop": DesktopIntegration(), "menus": MenuIntegration(), "weather": WeatherIntegration(),
                            "theme": ThemeIntegration(), "outputDevices": OutputDevicesIntegration(), "windowManager": WindowManagerIntegration()]
        }
        for (domain, service) in integrations {
            service.start { [weak self] state in
                precondition(Thread.isMainThread)
                self?.callback?(domain, state as NSDictionary)
            }
        }
    }
    @objc public func invoke(domain: String, action: String, argument: Any) {
        precondition(Thread.isMainThread)
        guard callback != nil else { return }
        guard let service = integrations[domain] else {
            callback?(domain, ["available": false, "lastErrorCode": "unsupported", "lastError": "Unknown integration.", "errorOperation": action]); return
        }
        if domain == "brightness", action == "set",
           let fields = argument as? [String: Any], (fields["value"] as? NSNumber)?.doubleValue.isFinite == true {
            pendingBrightness?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.integrations[domain]?.invoke(action, argument) }
            pendingBrightness = work
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(20), execute: work)
        } else if action == "refresh", domain != "spotify" && domain != "weather" { service.refresh() }
        else { service.invoke(action, argument) }
    }
    @objc public func prepareForExit() {
        precondition(Thread.isMainThread)
        let queues = integrations.values.map(\.worker)
        stop()
        // At application exit only, give queued gamma restoration/canceled
        // operations a bounded drain before the process exits. Normal teardown
        // remains nonblocking and generation-safe.
        let group = DispatchGroup()
        queues.forEach { queue in queue.async(group: group) {} }
        if group.wait(timeout: .now() + 2) == .timedOut {
            NSLog("Pill native cleanup timed out; display restoration may be incomplete.")
        }
    }
    @objc public func stop() {
        precondition(Thread.isMainThread); callback = nil
        pendingBrightness?.cancel(); pendingBrightness = nil
        integrations.values.forEach { $0.stop() }; integrations.removeAll()
    }
    deinit { precondition(Thread.isMainThread); stop(); Self.liveInstanceCount -= 1 }
}
