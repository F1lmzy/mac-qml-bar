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
        case "theme": state.merge(["name": "TEST theme", "slug": "fixture", "variant": "dark",
            "palette": themePalette(), "canNext": true, "canResyncWallpaper": true,
            "canSelect": true, "canNextBackground": true, "canSetBackground": true,
            "themes": [
                ["slug": "fixture", "name": "TEST theme", "background": "#1e1e2e", "foreground": "#cdd6f4",
                 "accent": "#cba6f7", "swatches": "#cba6f7,#94e2d5,#89b4fa,#a6e3a1,#f38ba8,#f9e2af"],
                // Second row carries no colours, so the card fallback is exercised.
                ["slug": "fixture-next", "name": "TEST next theme", "background": "", "foreground": "",
                 "accent": "", "swatches": ""]],
            "wallpapers": [["path": "/TEST/backgrounds/one.jpg", "url": "", "name": "one.jpg", "thumb": ""],
                          ["path": "/TEST/backgrounds/two.jpg", "url": "", "name": "two.jpg", "thumb": ""]],
            "backgroundPath": "/TEST/backgrounds/one.jpg", "backgroundUrl": "", "catalogLoading": false,
            "catalogError": "", "thumbnailsReady": false, "busy": false]) { _, new in new }
        case "outputDevices": state.merge(["devices": [["id": "1", "name": "TEST speakers", "default": true]], "canSelect": true]) { _, new in new }
        case "windowManager": state.merge(["backend": "TEST", "canSwitch": true, "canFocus": true, "focusedWorkspace": "1", "focusedWindow": "11", "workspaces": [["id": "1", "monitorId": "1", "visible": true, "windowCount": 1], ["id": "web", "monitorId": "1", "visible": false, "windowCount": 0]], "monitors": [["id": "1", "name": "TEST display", "focused": true]], "windows": [["id": "11", "workspace": "1", "appName": "TEST app", "layout": "floating"]]]) { _, new in new }
        default: state["available"] = false
        }
        return state
    }
    // Deterministic mac-themer-shaped fixture, never read personal theme files.
    static func themePalette() -> [String: Any] {
        var ansi: [String: Any] = ["background": "#1e1e2e", "foreground": "#cdd6f4",
            "cursor": "#cdd6f4", "accent": "#cba6f7", "selection_background": "#585b70", "selection_foreground": "#cdd6f4"]
        for i in 0..<16 { ansi["color\(i)"] = "#6c7086" }
        let tokens = ["surface": "#1e1e2e", "surface_container_low": "#28293a", "surface_container": "#313244",
            "surface_container_high": "#3a3b4e", "surface_container_highest": "#4c4e61",
            "on_surface": "#cdd6f4", "on_surface_variant": "#9ca2bd", "outline": "#64687d", "outline_variant": "#44465a",
            "primary": "#cba6f7", "on_primary": "#1e1e2e", "primary_container": "#cba6f7", "on_primary_container": "#1e1e2e",
            "secondary": "#94e2d5", "info": "#89b4fa", "success": "#a6e3a1", "warning": "#f9e2af", "error": "#f38ba8", "muted": "#6c7086"]
        let bar = ["background": "#1e1e2e", "background_solid": "#1e1e2e", "item_bg": "#313244",
            "accent": "#cba6f7", "label": "#cdd6f4", "icon": "#cdd6f4", "muted": "#6c7086",
            "red": "#f38ba8", "green": "#a6e3a1", "yellow": "#f9e2af"]
        return ["schema": 1, "name": "TEST theme", "slug": "fixture", "variant": "dark", "alpha_byte": 230,
            "palette": ansi, "tokens": tokens, "bar": bar, "border": ["active": "#cba6f7", "inactive": "#45475a"]]
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
            "theme": ["next", "resyncWallpaper", "catalog", "select", "nextBackground", "setBackground"], "outputDevices": ["select"],
            "windowManager": ["switchWorkspace", "focusWindow"]
        ]
        guard allowed[domain, default: []].contains(action) else { fail(action, "unsupported", "Unknown fixture action."); return }
        if domain == "theme", action != "catalog",
           (argument as? [String: Any])?["confirmed"] as? Bool != true {
            fail(action, "confirmationRequired", "Confirmation required."); return
        }
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
            } else if domain == "theme", action == "catalog" {
                next["catalogLoading"] = false
            } else if domain == "theme", action == "select" {
                guard let slug = (argument as? [String: Any])?["slug"] as? String,
                      (state["themes"] as? [[String: String]])?.contains(where: { $0["slug"] == slug }) == true else {
                    throw IntegrationFailure("staleIdentifier", "The selected theme is unavailable.")
                }
                let theme = (state["themes"] as? [[String: String]])?.first(where: { $0["slug"] == slug }) ?? [:]
                next["slug"] = slug
                next["name"] = theme["name"] ?? "TEST theme"
                if var palette = next["palette"] as? [String: Any] {
                    palette["slug"] = slug; palette["name"] = theme["name"] ?? "TEST theme"; next["palette"] = palette
                }
            } else if domain == "theme", action == "next" {
                let themes = state["themes"] as? [[String: String]] ?? []
                if let activeSlug = state["slug"] as? String,
                   let index = themes.firstIndex(where: { $0["slug"] == activeSlug }), !themes.isEmpty {
                    let theme = themes[(index + 1) % themes.count]
                    next["slug"] = theme["slug"]; next["name"] = theme["name"]
                    if var palette = next["palette"] as? [String: Any] { palette["slug"] = theme["slug"]; palette["name"] = theme["name"]; next["palette"] = palette }
                }
            } else if domain == "theme", action == "nextBackground" {
                let wallpapers = state["wallpapers"] as? [[String: String]] ?? []
                guard !wallpapers.isEmpty else { throw IntegrationFailure("unavailable", "No test backgrounds.") }
                let current = state["backgroundPath"] as? String ?? ""
                let index = wallpapers.firstIndex(where: { $0["path"] == current }) ?? -1
                let nextBackground = wallpapers[(index + 1) % wallpapers.count]
                next["backgroundPath"] = nextBackground["path"]
                next["backgroundUrl"] = nextBackground["url"]
            } else if domain == "theme", action == "setBackground" {
                let fields = argument as? [String: Any] ?? [:]
                guard fields["slug"] as? String == state["slug"] as? String,
                      let path = fields["path"] as? String,
                      let row = (state["wallpapers"] as? [[String: String]])?.first(where: { $0["path"] == path }) else {
                    throw IntegrationFailure("staleIdentifier", "The selected test background is unavailable.")
                }
                next["backgroundPath"] = row["path"]; next["backgroundUrl"] = row["url"]
            } else if (domain == "desktop" && action != "openSettings") || (domain == "menus" && action == "press") {
                guard (argument as? [String: Any])?["confirmed"] as? Bool == true else { throw IntegrationFailure("confirmationRequired", "Confirmation required.") }
            }
            let copy = next; perform(action, work: { _ in copy })
        } catch let error as IntegrationFailure { fail(action, error.code, error.message) }
        catch { fail(action, "nativeFailure", String(describing: error)) }
    }
}
