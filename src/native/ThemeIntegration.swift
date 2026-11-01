import Foundation
import Darwin

// mac-themer publishes the active theme as a resolved palette any consumer can
// read: state_dir/current.json. See mac-themer's README.md and
// lib/macthemer/{paths,render}.py. This
// integration watches that file's directory, validates the document through
// ThemePalette, and republishes on change. It never runs a theme helper unless
// the user explicitly confirms one, and it never shells out to read state.
enum ThemePaths {
    static func home() -> String {
        if let value = environment("MACTHEMER_HOME") { return (value as NSString).expandingTildeInPath }
        return NSHomeDirectory()
    }
    static func stateDirectory() -> String {
        if let value = environment("MACTHEMER_STATE") { return (value as NSString).expandingTildeInPath }
        return home() + "/.config/macthemer"
    }
    static func runDirectory() -> String {
        if let value = environment("MACTHEMER_RUN") { return (value as NSString).expandingTildeInPath }
        return home() + "/.local/state/macthemer"
    }
    static func binDirectory() -> String {
        if let value = environment("MACTHEMER_BIN") { return (value as NSString).expandingTildeInPath }
        return home() + "/.local/bin"
    }
    static func paletteFile() -> URL { URL(fileURLWithPath: stateDirectory() + "/current.json") }
    static func nextHelper() -> URL? { executable(binDirectory() + "/mac-themer") }
    static func wallpaperHelper() -> URL? { executable(binDirectory() + "/macthemer-wallpaper") }
    static func currentThemeDirectory() -> URL? {
        let current = URL(fileURLWithPath: stateDirectory() + "/current")
        guard let destination = try? FileManager.default.destinationOfSymbolicLink(atPath: current.path) else { return nil }
        let path = destination.hasPrefix("/") ? destination : current.deletingLastPathComponent().appendingPathComponent(destination).path
        let directory = URL(fileURLWithPath: path).resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else { return nil }
        return directory
    }
    static func themesDirectory() -> URL? {
        if let value = environment("MACTHEMER_THEMES") {
            let url = URL(fileURLWithPath: (value as NSString).expandingTildeInPath)
            return isDirectory(url) ? url : nil
        }
        // The active pack is a symlink into the checkout's themes directory, so
        // its parent is where every sibling pack lives.
        guard let current = currentThemeDirectory() else { return nil }
        let parent = current.deletingLastPathComponent()
        return isDirectory(parent) ? parent : nil
    }
    static func backgroundSnapshot() -> (rows: [[String: String]], path: String) {
        let path = resolvedBackground() ?? ""
        return (backgroundCatalog(themeDirectory: currentThemeDirectory()), path)
    }
    static func backgroundCatalog(themeDirectory: URL?) -> [[String: String]] {
        guard let themeDirectory = themeDirectory else { return [] }
        let directory = themeDirectory.appendingPathComponent("backgrounds", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [], options: [.skipsHiddenFiles]) else { return [] }
        let extensions: Set<String> = ["jpg", "jpeg", "png", "webp", "heic", "tiff"]
        let cache = WallpaperThumbnails.cacheDirectory()
        return files.filter { url in
            guard extensions.contains(url.pathExtension.lowercased()) else { return false }
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
        }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .prefix(256)
            .map { url in
                // The cached preview is attached only when it already exists; the
                // carousel falls back to the full-size file until the generation
                // pass has caught up.
                let thumb = WallpaperThumbnails.existingThumb(for: url, directory: cache)
                return ["path": url.path, "url": url.absoluteString, "name": url.lastPathComponent,
                        "thumb": thumb?.absoluteString ?? ""]
            }
    }

    // Swatch colours for a pack's card. mac-themer resolves the palette from
    // theme.toml into colors.toml; prefer the source file and fall back to the
    // generated one. Missing or malformed colours return no entry rather than a
    // guessed value, and QML falls back to the live palette.
    static func themeSwatches(themeDirectory: URL?, slug: String) -> [String: String] {
        guard let themeDirectory = themeDirectory else { return [:] }
        let directory = themeDirectory.appendingPathComponent(slug, isDirectory: true)
        for name in ["theme.toml", "colors.toml"] {
            if let swatches = parseSwatches(directory.appendingPathComponent(name)) { return swatches }
        }
        return [:]
    }

    static func parseSwatches(_ url: URL) -> [String: String]? {
        guard let data = try? Data(contentsOf: url), data.count <= 65_536,
              let text = String(data: data, encoding: .utf8) else { return nil }
        var sections: [String: [String: String]] = [:]
        var section = ""
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line.hasPrefix("[") && line.hasSuffix("]") {
                section = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                continue
            }
            guard let separator = line.firstIndex(of: "=") else { continue }
            let key = line[line.startIndex..<separator].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty, let color = firstHexColor(String(line[line.index(after: separator)...])) else { continue }
            sections[section, default: [:]][key] = color
        }
        // colors.toml has no section header, so top-level keys count as palette.
        guard let palette = sections["palette"] ?? sections[""],
              let background = palette["background"], let foreground = palette["foreground"] else { return nil }
        let accent = palette["accent"] ?? palette["color4"] ?? foreground
        let swatches = [accent, palette["color1"], palette["color2"], palette["color4"], palette["color5"], palette["color6"]]
            .compactMap { $0 }
        guard swatches.count >= 3 else { return nil }
        return ["background": background, "foreground": foreground, "accent": accent,
                "swatches": swatches.joined(separator: ",")]
    }

    // Scans for the first #rrggbb run rather than splitting on the delimiter, so
    // both a quoted value and a bare value with a trailing comment resolve.
    private static func firstHexColor(_ value: String) -> String? {
        let characters = Array(value)
        var index = 0
        while index + 6 < characters.count {
            if characters[index] == "#" {
                let digits = characters[(index + 1)...(index + 6)]
                if digits.allSatisfy({ $0.isHexDigit }) { return "#" + String(digits).lowercased() }
            }
            index += 1
        }
        return nil
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
    static func resolvedBackground() -> String? {
        let resolved = URL(fileURLWithPath: runDirectory() + "/background").resolvingSymlinksInPath()
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else { return nil }
        return resolved.path
    }
    static func canRunNext() -> Bool { nextHelper() != nil }
    static func canResyncWallpaper() -> Bool { wallpaperHelper() != nil && resolvedBackground() != nil }

    private static func environment(_ name: String) -> String? {
        guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else { return nil }
        return value
    }
    private static func executable(_ path: String) -> URL? {
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }
}

final class ThemeIntegration: PillIntegration {
    private let paletteFile: URL
    private let pollingInterval: TimeInterval
    private var watcher: DispatchSourceFileSystemObject?
    private var lastGood: [String: Any]?
    private var readPending = false
    private var readAgain = false
    private var themes: [[String: String]] = []
    private var catalogLoading = false
    private var catalogError = ""
    private var actionError: IntegrationFailure?
    private var busy = false
    private var wallpapers: [[String: String]] = []
    private var backgroundPath = ""
    private var thumbsRunning = false
    private var thumbnailsReady = false
    private var thumbsAttempted = Set<String>()

    init(paletteFile: URL? = nil, pollingInterval: TimeInterval = 2) {
        self.paletteFile = paletteFile ?? ThemePaths.paletteFile()
        self.pollingInterval = max(0.05, pollingInterval)
        super.init()
    }

    override func start(_ callback: @escaping ([String: Any]) -> Void) {
        super.start(callback)
        armWatcher()
        // Reconciliation covers a directory that did not exist yet when the
        // watcher first tried to arm, and any event the kernel drops.
        every(pollingInterval) { [weak self] in self?.refresh() }
    }

    override func stop() {
        disarmWatcher()
        readPending = false
        readAgain = false
        catalogLoading = false
        busy = false
        thumbsRunning = false
        thumbnailsReady = false
        thumbsAttempted.removeAll()
        super.stop()
    }

    override func refresh() {
        guard running else { return }
        // Keep one read in flight. A burst of atomic-replace events coalesces
        // into a single follow-up read instead of racing deliveries.
        if readPending { readAgain = true; return }
        readPending = true
        armWatcher()
        let url = paletteFile
        perform("theme.read", work: { cancellation in
            let doc = try ThemePalette.read(url: url, cancellation: cancellation)
            let background = ThemePaths.backgroundSnapshot()
            return ["palette": doc, "wallpapers": background.rows, "backgroundPath": background.path]
        }, receive: { [weak self] next in
            guard let self = self else { return }
            self.readPending = false
            if let rows = next["wallpapers"] as? [[String: String]] { self.wallpapers = rows }
            if let path = next["backgroundPath"] as? String { self.backgroundPath = path }
            if let doc = next["palette"] as? [String: Any] {
                self.lastGood = ["name": doc["name"] ?? "", "slug": doc["slug"] ?? "",
                                 "variant": doc["variant"] ?? "", "palette": doc]
                self.publish(self.state(doc: doc, error: nil))
            }
            // Previews are warmed on the reconciliation path, not on surface
            // open, so the carousel is normally already cached when it appears.
            self.scheduleThumbnails()
            if self.readAgain { self.readAgain = false; self.refresh() }
        }, failure: { [weak self] error in
            guard let self = self else { return }
            self.readPending = false
            self.publish(self.state(doc: nil, error: error))
            if self.readAgain { self.readAgain = false; self.refresh() }
        })
    }

    override func invoke(_ action: String, _ argument: Any) {
        precondition(Thread.isMainThread)
        if action == "catalog" { loadCatalog(); return }
        guard let fields = argument as? [String: Any] else {
            fail(action, "invalidInput", "Expected action fields."); return
        }
        if action == "setBackground" {
            guard fields["confirmed"] as? Bool == true else { fail(action, "confirmationRequired", "Confirm the wallpaper action first."); return }
            guard !busy else { fail(action, "busy", "A theme action is already running."); return }
            guard let slug = fields["slug"] as? String, slug == (lastGood?["slug"] as? String),
                  let path = fields["path"] as? String,
                  wallpapers.contains(where: { $0["path"] == path }) else {
                fail(action, "staleIdentifier", "The wallpaper is no longer in the active theme."); return
            }
            guard let helper = ThemePaths.nextHelper() else { fail(action, "unsupported", "The mac-themer helper is not installed."); return }
            let selectedSlug = slug, selectedPath = path
            let validateSelection: () throws -> Void = {
                guard ThemePaths.currentThemeDirectory()?.lastPathComponent == selectedSlug,
                      ThemePaths.backgroundCatalog(themeDirectory: ThemePaths.currentThemeDirectory()).contains(where: {
                          URL(fileURLWithPath: $0["path"] ?? "").resolvingSymlinksInPath().path == URL(fileURLWithPath: selectedPath).resolvingSymlinksInPath().path
                      }) else { throw IntegrationFailure("staleIdentifier", "The wallpaper is no longer in the active theme.") }
            }
            runMutation(action, path: helper.path, args: ["bg-next", path], validate: validateSelection); return
        }
        guard fields["confirmed"] as? Bool == true else {
            fail(action, "confirmationRequired", "Confirm the theme action first."); return
        }
        guard !busy else { fail(action, "busy", "A theme action is already running."); return }
        let path: String, args: [String]
        switch action {
        case "select":
            guard let slug = fields["slug"] as? String, themes.contains(where: { $0["slug"] == slug }),
                  slug.range(of: "^[a-zA-Z0-9][a-zA-Z0-9._-]{0,127}$", options: .regularExpression) != nil else {
                fail(action, "staleIdentifier", "The selected theme is not in the loaded catalog."); return
            }
            guard let helper = ThemePaths.nextHelper() else {
                fail(action, "unsupported", "The mac-themer helper is not installed."); return
            }
            path = helper.path; args = ["set", slug]
        case "next", "nextBackground":
            if action == "nextBackground" && wallpapers.isEmpty {
                fail(action, "unavailable", "The active theme has no available backgrounds."); return
            }
            guard let helper = ThemePaths.nextHelper() else {
                fail(action, "unsupported", "The mac-themer helper is not installed."); return
            }
            path = helper.path; args = action == "next" ? ["next"] : ["bg-next"]
        case "resyncWallpaper":
            guard let helper = ThemePaths.wallpaperHelper(), let background = ThemePaths.resolvedBackground() else {
                fail(action, "unsupported", "The wallpaper helper or background is unavailable."); return
            }
            path = helper.path; args = ["resync", background]
        default:
            super.invoke(action, argument); return
        }
        runMutation(action, path: path, args: args)
    }

    // LaunchServices does not inherit the interactive shell's PATH. mac-themer
    // uses /usr/bin/env python3 and needs Python 3.11+, not Apple's Python 3.9.
    static func runHelper(_ path: String, _ args: [String], timeout: Double,
                          cancellation: IntegrationCancellation) throws -> CommandOutput {
        let inherited = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let searchPath = "/opt/homebrew/bin:/usr/local/bin:" + inherited
        return try CommandRunner.run("/usr/bin/env", ["PATH=" + searchPath, path] + args,
                                     timeout: timeout, cancellation: cancellation)
    }

    private func runMutation(_ action: String, path: String, args: [String], validate: (() throws -> Void)? = nil) {
        busy = true
        publish(state(doc: lastGood?["palette"] as? [String: Any], error: nil))
        perform(action, work: { cancellation in
            try validate?()
            _ = try Self.runHelper(path, args, timeout: 15, cancellation: cancellation); return [:]
        }, receive: { [weak self] _ in
            guard let self = self else { return }
            self.busy = false
            self.actionError = nil
            self.refresh()
        }, failure: { [weak self] error in
            guard let self = self else { return }
            self.busy = false
            self.actionError = error
            self.publish(self.state(doc: self.lastGood?["palette"] as? [String: Any], error: nil))
            self.fail(action, error.code, error.message)
        })
    }

    private func loadCatalog() {
        guard running, !catalogLoading else { return }
        guard let helper = ThemePaths.nextHelper() else {
            catalogError = "The mac-themer helper is not installed."
            catalogLoading = false
            publish(state(doc: lastGood?["palette"] as? [String: Any], error: nil))
            fail("catalog", "unsupported", catalogError); return
        }
        catalogLoading = true
        catalogError = ""
        publish(state(doc: lastGood?["palette"] as? [String: Any], error: nil))
        let path = helper.path
        perform("catalog", work: { cancellation in
            let output = try Self.runHelper(path, ["list", "--json"], timeout: 10, cancellation: cancellation)
            return ["themes": try Self.parseCatalog(output.stdout, themesDirectory: ThemePaths.themesDirectory())]
        }, receive: { [weak self] result in
            guard let self = self else { return }
            self.catalogLoading = false
            self.themes = result["themes"] as? [[String: String]] ?? []
            self.catalogError = ""
            self.publish(self.state(doc: self.lastGood?["palette"] as? [String: Any], error: nil))
        }, failure: { [weak self] error in
            guard let self = self else { return }
            self.catalogLoading = false
            self.catalogError = error.message
            self.publish(self.state(doc: self.lastGood?["palette"] as? [String: Any], error: nil))
            self.fail("catalog", error.code, error.message)
        })
    }

    static func parseCatalog(_ data: Data, themesDirectory: URL? = nil) throws -> [[String: String]] {
        guard data.count <= 65_536, let json = try? JSONSerialization.jsonObject(with: data),
              let rows = json as? [[String: Any]], rows.count <= 512 else {
            throw IntegrationFailure("invalidResponse", "mac-themer theme catalog is invalid.")
        }
        var seen = Set<String>()
        return try rows.map { row in
            guard let slug = row["slug"] as? String,
                  slug.range(of: "^[a-zA-Z0-9][a-zA-Z0-9._-]{0,127}$", options: .regularExpression) != nil,
                  let name = row["name"] as? String, !name.isEmpty, name.count <= 256, !seen.contains(slug) else {
                throw IntegrationFailure("invalidResponse", "mac-themer theme catalog contains an invalid entry.")
            }
            seen.insert(slug)
            var entry: [String: String] = ["slug": slug, "name": name]
            entry.merge(ThemePaths.themeSwatches(themeDirectory: themesDirectory, slug: slug)) { _, new in new }
            // Always present, so QML never has to guard a missing key; an empty
            // string means "no colour read" and the card falls back to Theme.
            for key in ["background", "foreground", "accent", "swatches"] where entry[key] == nil { entry[key] = "" }
            return entry
        }
    }

    // Preview generation rides the reconciliation path rather than surface open,
    // so the strip is normally warm before anyone looks at it. Attempts are
    // remembered by cache key, so a repeat pass is stats and no writes and an
    // unreadable file is not re-decoded on every poll.
    private func scheduleThumbnails() {
        guard running, !thumbsRunning else { return }
        let rows = wallpapers
        guard !rows.isEmpty else { thumbnailsReady = false; return }
        let directory = WallpaperThumbnails.cacheDirectory()
        let pending = rows.filter { row in
            guard (row["thumb"] ?? "").isEmpty, let path = row["path"] else { return false }
            return !thumbsAttempted.contains(WallpaperThumbnails.attemptKey(for: URL(fileURLWithPath: path), directory: directory))
        }
        if pending.isEmpty {
            if !thumbnailsReady {
                thumbnailsReady = true
                publish(state(doc: lastGood?["palette"] as? [String: Any], error: nil))
            }
            return
        }
        thumbsRunning = true
        let pendingPaths = Set(pending.compactMap { $0["path"] })
        perform("theme.thumbs", work: { cancellation in
            var written = 0
            var attempted: [String] = []
            var keeping = Set<String>()
            for row in rows {
                if cancellation.isCanceled { break }
                guard let path = row["path"] else { continue }
                let source = URL(fileURLWithPath: path)
                if pendingPaths.contains(path) {
                    if WallpaperThumbnails.writeIfNeeded(source: source, directory: directory) { written += 1 }
                    attempted.append(WallpaperThumbnails.attemptKey(for: source, directory: directory))
                }
                if let fresh = WallpaperThumbnails.existingThumb(for: source, directory: directory) {
                    keeping.insert(fresh.lastPathComponent)
                }
            }
            // Reclaim previews this theme no longer references, plus any temp
            // file a killed pass left behind.
            WallpaperThumbnails.prune(directory: directory, keeping: keeping)
            return ["written": written, "attempted": attempted]
        }, receive: { [weak self] result in
            guard let self = self else { return }
            self.thumbsRunning = false
            self.thumbsAttempted.formUnion(result["attempted"] as? [String] ?? [])
            if (result["written"] as? Int ?? 0) > 0 { self.refresh() }
        }, failure: { [weak self] _ in
            guard let self = self else { return }
            self.thumbsRunning = false
        })
    }

    private func state(doc: [String: Any]?, error: IntegrationFailure?) -> [String: Any] {
        var fields: [String: Any] = ["canNext": ThemePaths.canRunNext(),
                                     "canResyncWallpaper": ThemePaths.canResyncWallpaper(),
                                     "canSelect": ThemePaths.canRunNext(),
                                     "canNextBackground": ThemePaths.canRunNext() && !wallpapers.isEmpty,
                                     "canSetBackground": ThemePaths.canRunNext() && !wallpapers.isEmpty,
                                     "themes": themes, "wallpapers": wallpapers,
                                     "backgroundPath": backgroundPath,
                                     "backgroundUrl": backgroundPath.isEmpty ? "" : URL(fileURLWithPath: backgroundPath).absoluteString,
                                     "catalogLoading": catalogLoading, "catalogError": catalogError,
                                     "thumbnailsReady": thumbnailsReady,
                                     "busy": busy]
        if let doc = doc {
            fields["available"] = true
            fields["name"] = doc["name"] ?? ""
            fields["slug"] = doc["slug"] ?? ""
            fields["variant"] = doc["variant"] ?? ""
            fields["palette"] = doc
            fields["lastErrorCode"] = ""
            fields["lastError"] = ""
        } else if let good = lastGood {
            // A malformed replacement keeps the last palette the user saw.
            fields["available"] = true
            fields["name"] = good["name"] ?? ""
            fields["slug"] = good["slug"] ?? ""
            fields["variant"] = good["variant"] ?? ""
            fields["palette"] = good["palette"] ?? [String: Any]()
            fields["lastErrorCode"] = error?.code ?? ""
            fields["lastError"] = error?.message ?? ""
        } else {
            fields["available"] = false
            fields["palette"] = [String: Any]()
            fields["lastErrorCode"] = error?.code ?? ""
            fields["lastError"] = error?.message ?? ""
        }
        if let actionError = actionError {
            fields["lastErrorCode"] = actionError.code
            fields["lastError"] = actionError.message
        }
        return fields
    }

    // Watch the directory, not the file: mac-themer writes through a temp file
    // and os.replace(), so the current.json vnode is swapped on every apply.
    private func armWatcher() {
        guard running, watcher == nil else { return }
        let directory = paletteFile.deletingLastPathComponent().path
        let fd = open(directory, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend, .attrib, .link],
            queue: .main)
        source.setEventHandler { [weak self] in self?.watcherFired() }
        source.setCancelHandler { close(fd) }
        watcher = source
        source.resume()
    }

    private func disarmWatcher() {
        watcher?.cancel()
        watcher = nil
    }

    private func watcherFired() {
        guard running else { return }
        // Reopen the directory in case this event was its replacement.
        disarmWatcher()
        refresh()
    }
}
