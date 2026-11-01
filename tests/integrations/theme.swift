import Foundation
import Darwin

private func checkTheme(_ condition: @autoclosure () -> Bool, _ name: String) {
    precondition(condition(), "theme fixture failed: \(name)")
}

private func spinTheme(_ predicate: @autoclosure () -> Bool, _ name: String, timeout: TimeInterval = 3) {
    let deadline = Date().addingTimeInterval(timeout)
    while !predicate(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    precondition(predicate(), "theme fixture timed out: \(name)")
}

private func themeDoc(name: String = "Catppuccin Mocha", slug: String = "catppuccin", variant: String = "dark",
                      background: String = "#1e1e2e", foreground: String = "#cdd6f4") -> [String: Any] {
    var palette: [String: Any] = ["background": background, "foreground": foreground, "cursor": "#f5e0dc",
        "accent": "#cba6f7", "selection_background": "#585b70", "selection_foreground": foreground]
    for index in 0..<16 { palette["color\(index)"] = "#101010" }
    let tokens: [String: Any] = ["surface": background, "surface_container_low": "#28293a",
        "surface_container": "#313244", "surface_container_high": "#3a3b4e", "surface_container_highest": "#4c4e61",
        "on_surface": foreground, "on_surface_variant": "#9ca2bd", "outline": "#64687d", "outline_variant": "#44465a",
        "primary": "#cba6f7", "on_primary": background, "primary_container": "#cba6f7", "on_primary_container": background,
        "secondary": "#94e2d5", "info": "#89b4fa", "success": "#a6e3a1", "warning": "#f9e2af",
        "error": "#f38ba8", "muted": "#6c7086"]
    let bar: [String: Any] = ["background": background, "background_solid": background, "item_bg": "#313244",
        "accent": "#cba6f7", "label": foreground, "icon": foreground, "muted": "#6c7086",
        "red": "#f38ba8", "green": "#a6e3a1", "yellow": "#f9e2af"]
    return ["schema": 1, "generated_by": "mac-themer 0.1.0", "slug": slug, "name": name, "variant": variant,
        "pack": "themes/\(slug)", "backgrounds": "themes/\(slug)/backgrounds", "alpha_byte": 230,
        "palette": palette, "tokens": tokens,
        "border": ["active": "#cba6f7", "inactive": "#45475a"], "bar": bar]
}

private final class ThemeFixture {
    let root: URL
    let state: URL
    let palette: URL
    init() {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("pill-theme-\(UUID().uuidString)")
        state = root.appendingPathComponent("config/macthemer")
        palette = state.appendingPathComponent("current.json")
    }
    func makeStateDirectory() throws { try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true) }
    func write(_ doc: [String: Any]) throws { try JSONSerialization.data(withJSONObject: doc).write(to: palette, options: .atomic) }
    func writeRaw(_ string: String) throws { try Data(string.utf8).write(to: palette, options: .atomic) }
    func remove() { try? FileManager.default.removeItem(at: root) }
}

private func rejects(_ doc: [String: Any], _ name: String) {
    do { _ = try ThemePalette.validate(doc); preconditionFailure("theme fixture accepted \(name)") }
    catch let failure as IntegrationFailure { checkTheme(failure.code == "invalidResponse", "\(name) code") }
    catch { preconditionFailure("theme fixture threw unexpected error for \(name): \(error)") }
}

func runThemeParserTests() throws {
    let catalog = try ThemeIntegration.parseCatalog(Data("[{\"slug\":\"tokyo-night\",\"name\":\"Tokyo Night\"}]".utf8))
    checkTheme(catalog == [["slug": "tokyo-night", "name": "Tokyo Night",
                            "background": "", "foreground": "", "accent": "", "swatches": ""]],
               "catalog JSON shape")
    do {
        _ = try ThemeIntegration.parseCatalog(Data("[{\"slug\":\"../bad\",\"name\":\"Bad\"}]".utf8))
        preconditionFailure("unsafe catalog slug accepted")
    } catch let failure as IntegrationFailure { checkTheme(failure.code == "invalidResponse", "unsafe catalog slug rejected") }
    _ = try ThemePalette.validate(FakeIntegration.themePalette())
    let valid = try ThemePalette.validate(themeDoc())
    checkTheme(valid["name"] as? String == "Catppuccin Mocha", "valid name")
    checkTheme((valid["tokens"] as? [String: Any])?["muted"] as? String == "#6c7086", "valid token")

    var schemaTwo = themeDoc(); schemaTwo["schema"] = 2; rejects(schemaTwo, "schema 2")
    var schemaBool = themeDoc(); schemaBool["schema"] = true; rejects(schemaBool, "schema bool")
    var alphaBool = themeDoc(); alphaBool["alpha_byte"] = true; rejects(alphaBool, "alpha bool")
    var alphaFraction = themeDoc(); alphaFraction["alpha_byte"] = 230.5; rejects(alphaFraction, "alpha fraction")
    var alphaOverflow = themeDoc(); alphaOverflow["alpha_byte"] = 256; rejects(alphaOverflow, "alpha overflow")
    var nameNumber = themeDoc(); nameNumber["name"] = 7; rejects(nameNumber, "name number")
    var shortHex = themeDoc(); (shortHex["palette"] as? [String: Any]).map { var p = $0; p["background"] = "#12"; shortHex["palette"] = p }
    rejects(shortHex, "short hex")
    var wordColor = ["palette": (themeDoc()["palette"] as? [String: Any]).map { var p = $0; p["accent"] = "red"; return p } as Any]
    wordColor["schema"] = 1; wordColor["slug"] = "s"; wordColor["name"] = "n"; wordColor["variant"] = "dark"
    wordColor["alpha_byte"] = 230; wordColor["tokens"] = themeDoc()["tokens"] as Any
    wordColor["border"] = themeDoc()["border"] as Any; wordColor["bar"] = themeDoc()["bar"] as Any
    rejects(wordColor, "word color")
    var missingToken = themeDoc(); (missingToken["tokens"] as? [String: Any]).map { var t = $0; t.removeValue(forKey: "muted"); missingToken["tokens"] = t }
    rejects(missingToken, "missing token")
    var missingBar = themeDoc(); (missingBar["bar"] as? [String: Any]).map { var b = $0; b.removeValue(forKey: "yellow"); missingBar["bar"] = b }
    rejects(missingBar, "missing bar")
    var missingBorder = themeDoc(); (missingBorder["border"] as? [String: Any]).map { var b = $0; b.removeValue(forKey: "inactive"); missingBorder["border"] = b }
    rejects(missingBorder, "missing border")
    checkTheme((try? ThemePalette.validate(["schema": 1])) == nil, "missing fields")
    checkTheme((try? ThemePalette.validate("nope" as Any)) == nil, "non object root")

    let fixture = ThemeFixture()
    defer { fixture.remove() }
    try fixture.makeStateDirectory()
    try fixture.write(themeDoc(name: "Read fixture"))
    let read = try ThemePalette.read(url: fixture.palette, cancellation: IntegrationCancellation())
    checkTheme(read["slug"] as? String == "catppuccin", "read slug")
    try fixture.writeRaw("{not json")
    do { _ = try ThemePalette.read(url: fixture.palette, cancellation: IntegrationCancellation()); preconditionFailure("bad JSON accepted") }
    catch let failure as IntegrationFailure { checkTheme(failure.code == "invalidResponse", "bad JSON code") }
    try fixture.writeRaw("{\"pad\":\"" + String(repeating: "a", count: 70_000) + "\"}")
    do { _ = try ThemePalette.read(url: fixture.palette, cancellation: IntegrationCancellation()); preconditionFailure("oversize accepted") }
    catch let failure as IntegrationFailure { checkTheme(failure.code == "invalidResponse", "oversize code") }
    try FileManager.default.removeItem(at: fixture.palette)
    do { _ = try ThemePalette.read(url: fixture.palette, cancellation: IntegrationCancellation()); preconditionFailure("missing file accepted") }
    catch let failure as IntegrationFailure { checkTheme(failure.code == "unavailable", "missing file code") }
    let canceled = IntegrationCancellation(); canceled.cancel()
    do { _ = try ThemePalette.read(url: fixture.palette, cancellation: canceled); preconditionFailure("canceled read accepted") }
    catch let failure as IntegrationFailure { checkTheme(failure.code == "canceled", "canceled read code") }
}

func runThemeLifecycleTests() throws {
    let fixture = ThemeFixture()
    defer { fixture.remove() }
    var state: [String: Any] = [:]
    let service = ThemeIntegration(paletteFile: fixture.palette, pollingInterval: 0.05)
    service.start { state = $0 }

    spinTheme(state["available"] as? Bool == false, "cold missing unavailable")
    checkTheme(state["lastErrorCode"] as? String == "unavailable", "cold missing code")

    // The parent directory starts absent; polling arms the directory watcher.
    try fixture.makeStateDirectory()
    try fixture.write(themeDoc())
    spinTheme(state["available"] as? Bool == true && state["name"] as? String == "Catppuccin Mocha", "valid palette")
    checkTheme(state["slug"] as? String == "catppuccin", "published slug")
    checkTheme(state["variant"] as? String == "dark", "published variant")
    let published = state["palette"] as? [String: Any]
    checkTheme(published?["slug"] as? String == "catppuccin", "nested slug")
    checkTheme((published?["tokens"] as? [String: Any])?["surface"] as? String == "#1e1e2e", "nested token")
    checkTheme(state["canNext"] is Bool, "canNext is boolean")
    checkTheme(state["themes"] is [[String: String]], "themes catalog is present")
    checkTheme(state["wallpapers"] is [[String: String]], "wallpaper catalog is present")
    checkTheme(state["backgroundPath"] is String && state["backgroundUrl"] is String, "background identity is present")
    checkTheme(state["catalogLoading"] as? Bool == false && state["busy"] as? Bool == false, "initial catalog flags")

    // A malformed replacement must keep the last good palette rather than publish a partial one.
    var broken = themeDoc(name: "Broken")
    (broken["tokens"] as? [String: Any]).map { var t = $0; t.removeValue(forKey: "muted"); broken["tokens"] = t }
    try fixture.write(broken)
    spinTheme(!((state["lastErrorCode"] as? String) ?? "").isEmpty, "invalid replacement error")
    checkTheme(state["available"] as? Bool == true, "invalid replacement keeps available")
    checkTheme(state["name"] as? String == "Catppuccin Mocha", "invalid replacement keeps name")
    checkTheme((state["palette"] as? [String: Any])?["name"] as? String == "Catppuccin Mocha", "invalid replacement keeps palette")

    // An atomic replacement must refresh without an explicit refresh call.
    try fixture.write(themeDoc(name: "Light fixture", background: "#fafafa", foreground: "#222222"))
    spinTheme(state["name"] as? String == "Light fixture", "auto update")
    checkTheme((state["palette"] as? [String: Any])?["tokens"].flatMap { ($0 as? [String: Any])?["surface"] as? String } == "#fafafa", "auto update token")
    checkTheme(((state["lastErrorCode"] as? String) ?? "").isEmpty, "auto update clears error")

    service.stop()
    let stopped = state["name"] as? String
    try fixture.write(themeDoc(name: "After stop"))
    RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    checkTheme(state["name"] as? String == stopped, "stopped service delivered")

    service.start { state = $0 }
    spinTheme(state["name"] as? String == "After stop", "restart refresh")
    service.stop()
}

func runThemeWatcherTests() throws {
    let fixture = ThemeFixture()
    defer { fixture.remove() }
    try fixture.makeStateDirectory()
    try fixture.write(themeDoc())
    // Polling cannot rescue the watcher within this test's three-second deadline.
    let service = ThemeIntegration(paletteFile: fixture.palette, pollingInterval: 30)
    defer { service.stop() }
    var state: [String: Any] = [:]
    service.start { state = $0 }
    spinTheme(state["name"] as? String == "Catppuccin Mocha", "initial watched palette")
    try fixture.write(themeDoc(name: "Atomic replacement"))
    spinTheme(state["name"] as? String == "Atomic replacement", "directory watcher atomic replacement")

    let oldState = fixture.root.appendingPathComponent("old-state")
    try FileManager.default.moveItem(at: fixture.state, to: oldState)
    try fixture.makeStateDirectory()
    try fixture.write(themeDoc(name: "Recreated directory"))
    spinTheme(state["name"] as? String == "Recreated directory", "directory watcher rearm")
}

func runThemeSwatchTests() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("pill-swatches-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let themes = root.appendingPathComponent("themes")
    func pack(_ slug: String) throws -> URL {
        let directory = themes.appendingPathComponent(slug)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
    // A pack in the shape mac-themer writes: palette under [palette], with a
    // trailing [bar] section that must not leak into the card colours.
    let osaka = try pack("osaka-jade")
    try Data("""
    name = "Osaka Jade"
    variant = "dark"

    [palette]
    background = "#111c18"
    foreground = "#c1c497"
    accent = "#509475"
    color1 = "#ff5345"
    color2 = "#549e6a"
    color4 = "#509475"
    color5 = "#d2689c"
    color6 = "#2dd5b7"

    [bar]
    background_alpha = 0.902
    red = "#ff5345"
    """.utf8).write(to: osaka.appendingPathComponent("theme.toml"))
    // A pack with only the generated colors.toml, which has no section header.
    let catppuccin = try pack("catppuccin")
    try Data("""
    accent = "#cba6f7"
    background = "#1e1e2e"
    foreground = "#cdd6f4"
    color1 = "#f38ba8"
    color2 = "#a6e3a1"
    color4 = "#cba6f7"
    color5 = "#f5c2e7"
    color6 = "#94e2d5"
    """.utf8).write(to: catppuccin.appendingPathComponent("colors.toml"))
    // A pack whose palette cannot be read at all.
    _ = try pack("empty")

    let rows = try ThemeIntegration.parseCatalog(Data("""
    [{"slug":"osaka-jade","name":"Osaka Jade"},{"slug":"catppuccin","name":"Catppuccin Mocha"},{"slug":"empty","name":"Empty"}]
    """.utf8), themesDirectory: themes)
    checkTheme(rows.count == 3, "swatch catalog keeps every row")
    checkTheme(rows[0]["background"] == "#111c18" && rows[0]["foreground"] == "#c1c497" && rows[0]["accent"] == "#509475",
               "palette section colours are read")
    checkTheme(rows[0]["swatches"] == "#509475,#ff5345,#549e6a,#509475,#d2689c,#2dd5b7",
               "swatch order and join, got \(rows[0]["swatches"] ?? "nil")")
    checkTheme(rows[1]["background"] == "#1e1e2e", "colors.toml without a section header is read")
    checkTheme(rows[2]["background"] == "" && rows[2]["swatches"] == "", "unreadable palette yields empty fields")

    // A malformed or absent file must yield nothing rather than a half palette.
    checkTheme(ThemePaths.parseSwatches(root.appendingPathComponent("absent.toml")) == nil, "absent palette")
    let junk = root.appendingPathComponent("junk.toml")
    try Data("[palette]\nbackground = \"nope\"\nforeground = #12\n".utf8).write(to: junk)
    checkTheme(ThemePaths.parseSwatches(junk) == nil, "junk palette is rejected")

    print("PASS: mac-themer theme swatch parsing fixtures")
}

// End-to-end preview pipeline: a real image in a fixture pack must gain a
// cached preview through the ordinary reconciliation path, with no explicit
// surface open and no manual cache warm-up.
func runThemeThumbnailTests() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("pill-thumb-pipeline-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let cache = root.appendingPathComponent("cache")
    let state = root.appendingPathComponent("state")
    let pack = root.appendingPathComponent("themes/catppuccin")
    let backgrounds = pack.appendingPathComponent("backgrounds")
    try FileManager.default.createDirectory(at: backgrounds, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: state, withIntermediateDirectories: true)
    let source = backgrounds.appendingPathComponent("one.png")
    try writeFixturePNG(source, width: 1400, height: 900)
    try FileManager.default.createSymbolicLink(at: state.appendingPathComponent("current"), withDestinationURL: pack)
    // refresh() reads the palette and the background catalogue in one pass, so a
    // missing palette would mask the wallpapers entirely.
    try JSONSerialization.data(withJSONObject: themeDoc()).write(to: state.appendingPathComponent("current.json"), options: .atomic)

    let savedState = ProcessInfo.processInfo.environment["MACTHEMER_STATE"]
    let savedCache = ProcessInfo.processInfo.environment["PILL_THUMB_CACHE"]
    setenv("MACTHEMER_STATE", state.path, 1)
    setenv("PILL_THUMB_CACHE", cache.path, 1)
    defer {
        if let savedState { setenv("MACTHEMER_STATE", savedState, 1) } else { unsetenv("MACTHEMER_STATE") }
        if let savedCache { setenv("PILL_THUMB_CACHE", savedCache, 1) } else { unsetenv("PILL_THUMB_CACHE") }
    }

    let service = ThemeIntegration(paletteFile: state.appendingPathComponent("current.json"), pollingInterval: 5)
    defer { service.stop() }
    var observed: [String: Any] = [:]
    service.start { observed = $0 }
    spinTheme((observed["wallpapers"] as? [[String: String]])?.count == 1, "fixture pack enumerates its background")
    let first = (observed["wallpapers"] as? [[String: String]])?.first
    checkTheme((first?["thumb"] ?? "") == "", "a cold cache has no preview to attach")

    // The pass runs off the reconciliation path, so readiness arrives without
    // anyone opening the carousel.
    spinTheme(!(((observed["wallpapers"] as? [[String: String]])?.first?["thumb"] ?? "").isEmpty),
              "preview is generated and republished")
    spinTheme(observed["thumbnailsReady"] as? Bool == true, "preview readiness is published")
    guard let thumbURL = (observed["wallpapers"] as? [[String: String]])?.first?["thumb"],
          let thumb = URL(string: thumbURL) else {
        preconditionFailure("theme fixture failed: preview URL is not parseable")
    }
    checkTheme(thumb.isFileURL, "preview URL is a file URL")
    checkTheme(FileManager.default.fileExists(atPath: thumb.path), "preview exists on disk")
    guard let size = fixtureImageSize(thumb) else {
        preconditionFailure("theme fixture failed: preview is not decodable")
    }
    checkTheme(size.width <= WallpaperThumbnails.maxPixel && size.height <= WallpaperThumbnails.maxPixel,
               "preview is capped, got \(size)")
    checkTheme(thumb.path.hasPrefix(cache.path), "preview honours the cache override")

    print("PASS: wallpaper preview pipeline fixtures")
}

func runThemeHelperTests() throws {
    let fixture = ThemeFixture()
    defer { fixture.remove() }
    let emptyBin = fixture.root.appendingPathComponent("bin")
    let emptyRun = fixture.root.appendingPathComponent("run")
    try? FileManager.default.createDirectory(at: emptyBin, withIntermediateDirectories: true)
    try? FileManager.default.createDirectory(at: emptyRun, withIntermediateDirectories: true)
    let savedBin = ProcessInfo.processInfo.environment["MACTHEMER_BIN"]
    let savedRun = ProcessInfo.processInfo.environment["MACTHEMER_RUN"]
    let savedState = ProcessInfo.processInfo.environment["MACTHEMER_STATE"]
    setenv("MACTHEMER_BIN", emptyBin.path, 1)
    setenv("MACTHEMER_RUN", emptyRun.path, 1)
    setenv("MACTHEMER_STATE", fixture.state.path, 1)
    defer {
        if let savedBin { setenv("MACTHEMER_BIN", savedBin, 1) } else { unsetenv("MACTHEMER_BIN") }
        if let savedRun { setenv("MACTHEMER_RUN", savedRun, 1) } else { unsetenv("MACTHEMER_RUN") }
        if let savedState { setenv("MACTHEMER_STATE", savedState, 1) } else { unsetenv("MACTHEMER_STATE") }
    }
    try fixture.makeStateDirectory()
    try fixture.write(themeDoc())
    var state: [String: Any] = [:]
    let service = ThemeIntegration(paletteFile: fixture.palette, pollingInterval: 5)
    service.start { state = $0 }
    spinTheme(state["canNext"] as? Bool == false, "missing helper canNext")
    checkTheme(state["canResyncWallpaper"] as? Bool == false, "missing helper canResyncWallpaper")

    service.invoke("next", ["confirmed": false])
    checkTheme(state["lastErrorCode"] as? String == "confirmationRequired", "confirmation required")
    service.invoke("next", ["confirmed": true])
    checkTheme(state["lastErrorCode"] as? String == "unsupported", "missing next helper unsupported")
    checkTheme(((state["lastError"] as? String) ?? "").contains("helper"), "missing next helper message")
    service.invoke("resyncWallpaper", ["confirmed": true])
    checkTheme(state["lastErrorCode"] as? String == "unsupported", "missing wallpaper helper unsupported")
    service.invoke("bogus", ["confirmed": true])
    checkTheme(state["lastError"] as? String == "This action is unavailable.", "unknown action fallback")
    // Harmless owned helpers log argv in the temp tree. Never run real desktop helpers.
    func logHelper(_ name: String, to log: URL) throws {
        let script = "#!/bin/sh\nprintf '%s\\n' \"$@\" > '\(log.path)'\n"
        let path = emptyBin.appendingPathComponent(name)
        try Data(script.utf8).write(to: path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
    }
    let nextLog = fixture.root.appendingPathComponent("next-args")
    let wallpaperLog = fixture.root.appendingPathComponent("wallpaper-args")
    let catalogLog = fixture.root.appendingPathComponent("catalog-args")
    let selectLog = fixture.root.appendingPathComponent("select-args")
    let setBackgroundLog = fixture.root.appendingPathComponent("set-background-args")
    let nextBackgroundLog = fixture.root.appendingPathComponent("next-background-args")
    let catalogScript = "#!/bin/sh\ncase \"$1\" in\n list) printf '%s\\n' \"$@\" > '\(catalogLog.path)'; printf '%s\\n' '[{\"slug\":\"catppuccin\",\"name\":\"Catppuccin Mocha\"}]' ;;\n set) printf '%s\\n' \"$@\" > '\(selectLog.path)' ;;\n next) printf '%s\\n' \"$@\" > '\(nextLog.path)' ;;\n bg-next) if [ -n \"$2\" ]; then printf '%s\\n' \"$@\" > '\(setBackgroundLog.path)'; else printf '%s\\n' \"$@\" > '\(nextBackgroundLog.path)'; fi ;;\nesac\nsleep 0.1\n"
    let catalogPath = emptyBin.appendingPathComponent("mac-themer")
    try Data(catalogScript.utf8).write(to: catalogPath)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: catalogPath.path)
    try logHelper("macthemer-wallpaper", to: wallpaperLog)
    let picture = fixture.root.appendingPathComponent("fixture.png")
    try Data().write(to: picture)
    try FileManager.default.createSymbolicLink(at: emptyRun.appendingPathComponent("background"), withDestinationURL: picture)
    service.refresh()
    spinTheme(state["canNext"] as? Bool == true && state["canResyncWallpaper"] as? Bool == true, "owned helper capabilities")
    service.invoke("catalog", NSNull())
    spinTheme((state["themes"] as? [[String: String]])?.first?["slug"] == "catppuccin", "catalog helper response")
    checkTheme((try? String(contentsOf: catalogLog, encoding: .utf8)) == "list\n--json\n", "read-only catalog argv")
    let backgroundSlug = fixture.root.appendingPathComponent("theme/catppuccin")
    let backgrounds = backgroundSlug.appendingPathComponent("backgrounds")
    try FileManager.default.createDirectory(at: backgrounds, withIntermediateDirectories: true)
    let wallpaper = backgrounds.appendingPathComponent("one.png")
    let wallpaperTwo = backgrounds.appendingPathComponent("two.png")
    try Data().write(to: wallpaper)
    try Data().write(to: wallpaperTwo)
    let themeLink = fixture.state.appendingPathComponent("current")
    try FileManager.default.createSymbolicLink(at: themeLink, withDestinationURL: backgroundSlug)
    let runBackground = emptyRun.appendingPathComponent("background")
    try FileManager.default.removeItem(at: runBackground)
    try FileManager.default.createSymbolicLink(at: runBackground, withDestinationURL: wallpaper)
    checkTheme(ThemePaths.currentThemeDirectory()?.path == backgroundSlug.path, "current pack symlink resolves")
    let enumerated = ThemePaths.backgroundCatalog(themeDirectory: ThemePaths.currentThemeDirectory())
    checkTheme(!enumerated.isEmpty, "pack background enumerates")
    checkTheme(enumerated.allSatisfy { $0["thumb"] != nil }, "wallpaper rows carry a thumb field")
    checkTheme(enumerated.allSatisfy { ($0["thumb"] ?? "").isEmpty }, "empty fixtures have no preview yet")
    let cataloguedPath = enumerated.first?["path"] ?? ""
    checkTheme(URL(fileURLWithPath: cataloguedPath).lastPathComponent == "one.png", "expected wallpaper path")
    service.refresh()
    spinTheme((state["wallpapers"] as? [[String: String]])?.first?["path"] == cataloguedPath, "background catalog: \(state["wallpapers"] ?? []) expected \(cataloguedPath)")
    checkTheme(state["thumbnailsReady"] is Bool, "thumbnail readiness is published")
    checkTheme(URL(fileURLWithPath: state["backgroundPath"] as? String ?? "").lastPathComponent == "one.png", "active background path")
    service.invoke("setBackground", ["path": cataloguedPath, "slug": "stale", "confirmed": true])
    checkTheme(state["lastErrorCode"] as? String == "staleIdentifier", "stale wallpaper theme rejected")
    service.invoke("setBackground", ["path": cataloguedPath, "slug": "catppuccin", "confirmed": false])
    checkTheme(state["lastErrorCode"] as? String == "confirmationRequired", "wallpaper selection confirmation required")
    service.invoke("setBackground", ["path": fixture.root.appendingPathComponent("outside.png").path, "slug": "catppuccin", "confirmed": true])
    checkTheme(state["lastErrorCode"] as? String == "staleIdentifier", "outside wallpaper rejected")
    service.invoke("setBackground", ["path": cataloguedPath, "slug": "catppuccin", "confirmed": true])
    spinTheme((try? String(contentsOf: setBackgroundLog, encoding: .utf8)) == "bg-next\n\(cataloguedPath)\n", "selected wallpaper helper argv")
    spinTheme(state["busy"] as? Bool == false, "selected wallpaper action finished")
    try FileManager.default.removeItem(at: wallpaperTwo)
    service.refresh()
    spinTheme((state["wallpapers"] as? [[String: String]])?.count == 1, "wallpaper catalog reflects removal")
    service.invoke("setBackground", ["path": wallpaperTwo.path, "slug": "catppuccin", "confirmed": true])
    checkTheme(state["lastErrorCode"] as? String == "staleIdentifier", "removed wallpaper rejected")
    try Data().write(to: wallpaperTwo)
    service.refresh()
    spinTheme((state["wallpapers"] as? [[String: String]])?.count == 2, "wallpaper catalog refreshed")
    try? FileManager.default.removeItem(at: catalogLog)
    service.invoke("next", ["confirmed": false])
    checkTheme(!FileManager.default.fileExists(atPath: catalogLog.path), "unconfirmed helper ran")
    service.invoke("select", ["slug": "catppuccin", "confirmed": true])
    spinTheme((try? String(contentsOf: selectLog, encoding: .utf8)) == "set\ncatppuccin\n", "theme selection helper argv")
    spinTheme(state["busy"] as? Bool == false, "theme selection finished")
    service.invoke("next", ["confirmed": true])
    service.invoke("nextBackground", ["confirmed": true])
    checkTheme(state["lastErrorCode"] as? String == "busy", "overlapping mutation rejected")
    spinTheme((try? String(contentsOf: nextLog, encoding: .utf8)) == "next\n", "next helper argv")
    spinTheme(state["busy"] as? Bool == false, "next action finished")
    service.invoke("nextBackground", ["confirmed": true])
    spinTheme((try? String(contentsOf: nextBackgroundLog, encoding: .utf8)) == "bg-next\n", "next background helper argv")
    spinTheme(state["busy"] as? Bool == false, "next background finished")
    service.invoke("resyncWallpaper", ["confirmed": true])
    spinTheme((try? String(contentsOf: wallpaperLog, encoding: .utf8))?.hasPrefix("resync\n") == true, "wallpaper helper argv")
    spinTheme(state["busy"] as? Bool == false, "resync action finished")
    service.invoke("nextBackground", ["confirmed": false])
    checkTheme(state["lastErrorCode"] as? String == "confirmationRequired", "background action confirmation required")
    service.invoke("select", ["slug": "missing", "confirmed": true])
    checkTheme(state["lastErrorCode"] as? String == "staleIdentifier", "unknown theme rejected")

    let brokenHelper = "#!/bin/sh\necho fixture failure >&2\nexit 1\n"
    try Data(brokenHelper.utf8).write(to: catalogPath)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: catalogPath.path)
    service.invoke("catalog", NSNull())
    spinTheme(state["catalogLoading"] as? Bool == false && !(state["catalogError"] as? String ?? "").isEmpty, "catalog failure clears loading and publishes error")
    service.invoke("next", ["confirmed": true])
    spinTheme(state["busy"] as? Bool == false && state["lastErrorCode"] as? String == "nativeFailure", "failed mutation publishes error")
    service.refresh()
    spinTheme(state["available"] as? Bool == true && state["lastErrorCode"] as? String == "nativeFailure", "mutation error retained through refresh")
    service.stop()
    checkTheme(state["busy"] as? Bool == false, "stop clears busy")
}

func runThemeFakeTests() {
    let fake = FakeIntegration("theme")
    var state: [String: Any] = [:]
    fake.start { state = $0 }
    spinTheme(state["available"] as? Bool == true, "fake theme initial state")
    fake.invoke("select", ["slug": "fixture-next", "confirmed": false])
    checkTheme(state["lastErrorCode"] as? String == "confirmationRequired", "fake selection requires confirmation")
    fake.invoke("select", ["slug": "fixture-next", "confirmed": true])
    spinTheme(state["slug"] as? String == "fixture-next", "fake theme selection updates observed slug")
    checkTheme((state["palette"] as? [String: Any])?["slug"] as? String == "fixture-next", "fake palette follows selected slug")
    fake.invoke("nextBackground", ["confirmed": true])
    spinTheme(state["backgroundPath"] as? String == "/TEST/backgrounds/two.jpg", "fake next background updates observed path")
    fake.invoke("setBackground", ["slug": "fixture-next", "path": "/TEST/backgrounds/one.jpg", "confirmed": true])
    spinTheme(state["backgroundPath"] as? String == "/TEST/backgrounds/one.jpg", "fake selected background updates observed path")
    fake.stop()
}

func runThemeLaunchEnvironmentTests() throws {
    let savedPath = ProcessInfo.processInfo.environment["PATH"]
    setenv("PATH", "/usr/bin:/bin:/usr/sbin:/sbin", 1)
    defer { if let savedPath { setenv("PATH", savedPath, 1) } else { unsetenv("PATH") } }
    let result = try ThemeIntegration.runHelper("/usr/bin/printenv", ["PATH"], timeout: 2,
                                                cancellation: IntegrationCancellation())
    checkTheme(String(data: result.stdout, encoding: .utf8) == "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin\n",
               "GUI helper PATH includes modern Homebrew Python")
}

func runThemeTests() throws {
    try runThemeLaunchEnvironmentTests()
    try runThemeParserTests()
    try runThemeLifecycleTests()
    try runThemeWatcherTests()
    try runThemeSwatchTests()
    try runThemeThumbnailTests()
    try runThemeHelperTests()
    runThemeFakeTests()
    print("PASS: mac-themer palette validation, watcher, last-good retention and helper capability fixtures")
}
