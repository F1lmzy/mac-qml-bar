import Foundation

final class FakeIntegration: PillIntegration {
    let domain: String
    init(_ domain: String) { self.domain = domain; super.init(); state = Self.initial(domain) }
    static let domains = ["brightness", "display", "battery", "wifi", "bluetooth", "spotify", "desktop", "menus", "weather", "theme", "outputDevices", "windowManager"]
    static func initial(_ domain: String) -> [String: Any] {
        var state: [String: Any] = ["available": true, "lastErrorCode": "", "lastError": ""]
        switch domain {
        case "brightness": state.merge(["displayId": "42", "known": true, "value": 0.7, "canSet": true]) { _, new in new }
        case "display": state.merge(["screens": [["id": "42", "name": "TEST display", "builtin": true]], "nightShiftKnown": true, "nightShiftEnabled": false, "canSetNightShift": true, "shade": 0.0, "canShade": true]) { _, new in new }
        case "battery": state.merge(["known": true, "charge": 0.8, "charging": false, "onAC": false]) { _, new in new }
        case "wifi": state.merge(["permission": "notDetermined", "powered": true, "ssidKnown": false, "ssid": "", "canRequestPermission": true]) { _, new in new }
        case "bluetooth": state.merge(["permission": "notDetermined", "devices": [], "canConnect": false, "canRequestPermission": true]) { _, new in new }
        case "spotify": state.merge(["running": true, "known": true, "title": "TEST track", "artist": "Fixture", "playing": false, "canControl": true, "permission": "notDetermined", "canRequestPermission": true]) { _, new in new }
        case "desktop": state.merge(["frontAppKnown": true, "frontApp": "TEST app", "frontPid": 123, "canLock": true, "canSleep": true, "canRestart": true, "canShutDown": true]) { _, new in new }
        case "menus": state.merge(["permission": "notDetermined", "items": [], "breadcrumb": [], "frontPid": 123, "canRequestPermission": true]) { _, new in new }
        case "weather": state["available"] = false; state["enabled"] = false
        case "theme": state.merge(["name": "TEST theme", "canNext": true, "canResyncWallpaper": true]) { _, new in new }
        case "outputDevices": state.merge(["devices": [["id": "1", "name": "TEST speakers", "default": true]], "canSelect": true]) { _, new in new }
        case "windowManager": state.merge(["backend": "TEST", "canSwitch": true, "canFocus": true, "focusedWorkspace": "1", "focusedWindow": "11", "workspaces": [["id": "1", "monitorId": "1", "visible": true, "windowCount": 1], ["id": "web", "monitorId": "1", "visible": false, "windowCount": 0]], "monitors": [["id": "1", "name": "TEST display", "focused": true]], "windows": [["id": "11", "workspace": "1", "appName": "TEST app", "layout": "floating"]]]) { _, new in new }
        default: state["available"] = false
        }
        return state
    }
    override func refresh() { let copy = state; perform("refresh", work: { _ in copy }) }
    override func invoke(_ action: String, _ argument: Any) {
        var next = state; next["lastError"] = ""; next["lastErrorCode"] = ""; next.removeValue(forKey: "errorOperation")
        let allowed: [String: [String]] = [
            "brightness": ["set"], "display": ["setNightShift", "setShade"],
            "wifi": ["requestPermission", "openSettings"], "bluetooth": ["requestPermission", "openSettings", "connect", "disconnect"],
            "spotify": ["requestPermission", "refresh", "playPause", "previous", "next"],
            "desktop": ["openSettings", "lock", "sleep", "restart", "shutDown"],
            "menus": ["requestPermission", "refresh", "open", "back", "press"], "weather": ["refresh", "enable"],
            "theme": ["next", "resyncWallpaper"], "outputDevices": ["select"],
            "windowManager": ["switchWorkspace", "focusWindow"]
        ]
        guard allowed[domain, default: []].contains(action) else { fail(action, "unsupported", "Unknown fixture action."); return }
        do {
            if domain == "brightness" {
                let fields = argument as? [String: Any] ?? [:]
                guard fields["displayId"] as? String == state["displayId"] as? String else { throw IntegrationFailure("unavailable", "Display changed.") }
                next["value"] = try finiteUnit(fields["value"] ?? NSNull())
            } else if domain == "display", action == "setShade" { next["shade"] = try finiteUnit(argument) }
            else if domain == "display", action == "setNightShift" {
                guard let value = argument as? Bool else { throw IntegrationFailure("invalidInput", "Expected boolean.") }
                next["nightShiftEnabled"] = value
            } else if action == "requestPermission" {
                next["permission"] = "authorized"
                if domain == "wifi" { next["ssidKnown"] = true; next["ssid"] = "TEST network" }
                if domain == "menus" { next["items"] = [["index": 0, "id": "0", "title": "File", "hasChildren": true, "enabled": true]] }
                if domain == "bluetooth" { next["canConnect"] = true; next["devices"] = [["id": "TEST-device", "name": "TEST headphones", "connected": false]] }
            } else if domain == "spotify", action == "playPause" { next["playing"] = !(state["playing"] as? Bool ?? false) }
            else if domain == "weather" { next.merge(["available": true, "known": true, "enabled": true, "temperatureC": "20", "description": "TEST weather"]) { _, new in new } }
            else if domain == "windowManager", action == "switchWorkspace" {
                guard let id = argument as? String, (state["workspaces"] as? [[String: Any]])?.contains(where: { $0["id"] as? String == id }) == true else { throw IntegrationFailure("staleIdentifier", "Unknown workspace.") }
                next["focusedWorkspace"] = id
                next["workspaces"] = (state["workspaces"] as? [[String: Any]])?.map { row in var row = row; row["visible"] = row["id"] as? String == id; return row }
            } else if (domain == "desktop" && action != "openSettings") || domain == "theme" || (domain == "menus" && action == "press") {
                guard (argument as? [String: Any])?["confirmed"] as? Bool == true else { throw IntegrationFailure("confirmationRequired", "Confirmation required.") }
            }
            let copy = next; perform(action, work: { _ in copy })
        } catch let error as IntegrationFailure { fail(action, error.code, error.message) }
        catch { fail(action, "nativeFailure", String(describing: error)) }
    }
}
