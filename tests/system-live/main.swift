import AppKit
import Foundation

// Read-only probe. No invoke calls, permission requests, helpers, weather
// HTTP, display writes, Bluetooth actions or workspace changes.
let application = NSApplication.shared
let service = SystemService(fake: false)
var seen = Set<String>()
service.start { domain, snapshot in
    seen.insert(domain)
    let fields: [String: Any] = ["domain": domain,
        "available": snapshot["available"] as? Bool ?? false,
        "known": snapshot["known"] as? Bool ?? false,
        "permission": snapshot["permission"] as? String ?? "",
        "error": snapshot["lastErrorCode"] as? String ?? ""]
    let data = try! JSONSerialization.data(withJSONObject: fields, options: .sortedKeys)
    print(String(data: data, encoding: .utf8)!)
}
let deadline = Date().addingTimeInterval(25)
while seen.count < FakeIntegration.domains.count && Date() < deadline {
    RunLoop.main.run(until: Date().addingTimeInterval(0.02))
}
service.stop()
precondition(PillIntegration.liveInstanceCount == 0, "Native integrations retained after stop.")
precondition(seen.count == FakeIntegration.domains.count, "Some native services did not publish within the probe deadline.")
print("PASS: every integration published read-only state; no actions or permission requests")
