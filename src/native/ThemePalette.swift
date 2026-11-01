import Foundation

// Reads and validates the mac-themer resolved palette (state_dir/current.json).
// mac-themer writes that file atomically and documents it as the interface for
// every app-facing consumer: https://github.com/F1lmzy/mac-themer (README.md
// "What gets written", lib/macthemer/render.py resolved()). This boundary is
// deliberately strict: a palette is published only when every colour an app
// consumes is present and a plain #rrggbb string, so a malformed or partial
// document can never reach QML.
enum ThemePalette {
    // current.json is small (under 2 KiB today). Cap the read so a runaway file
    // cannot make the worker allocate without bound.
    static let maxBytes = 65_536

    private static let paletteKeys = ["background", "foreground", "cursor", "accent",
        "selection_background", "selection_foreground"] + (0..<16).map { "color\($0)" }

    // Derived semantic roles from lib/macthemer/tokens.py TOKEN_ORDER.
    private static let tokenKeys = ["surface", "surface_container_low", "surface_container",
        "surface_container_high", "surface_container_highest", "on_surface", "on_surface_variant",
        "outline", "outline_variant", "primary", "on_primary", "primary_container",
        "on_primary_container", "secondary", "info", "success", "warning", "error", "muted"]

    // lib/macthemer/tokens.py bar_for() / palette.py BAR_COLOR_KEYS.
    private static let barKeys = ["background", "background_solid", "item_bg", "accent",
        "label", "icon", "muted", "red", "green", "yellow"]

    static func read(url: URL, cancellation: IntegrationCancellation) throws -> [String: Any] {
        guard !cancellation.isCanceled else { throw IntegrationFailure("canceled", "Operation canceled.") }
        if let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber,
           size.intValue > maxBytes {
            throw IntegrationFailure("invalidResponse", "Palette exceeds \(maxBytes) bytes.")
        }
        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: url) }
        catch { throw IntegrationFailure("unavailable", "No mac-themer palette published.") }
        defer { try? handle.close() }
        let data: Data
        do {
            guard let chunk = try handle.read(upToCount: maxBytes + 1) else {
                throw IntegrationFailure("invalidResponse", "Palette read returned no data.")
            }
            data = chunk
        } catch let failure as IntegrationFailure { throw failure }
        catch { throw IntegrationFailure("invalidResponse", "Palette read failed.") }
        guard data.count <= maxBytes else {
            throw IntegrationFailure("invalidResponse", "Palette exceeds \(maxBytes) bytes.")
        }
        guard !cancellation.isCanceled else { throw IntegrationFailure("canceled", "Operation canceled.") }
        let json: Any
        do { json = try JSONSerialization.jsonObject(with: data) }
        catch { throw IntegrationFailure("invalidResponse", "Palette is not valid JSON.") }
        return try validate(json)
    }

    static func validate(_ json: Any) throws -> [String: Any] {
        guard let root = json as? [String: Any] else {
            throw IntegrationFailure("invalidResponse", "Palette root must be an object.")
        }
        guard integer(root["schema"]) == 1 else {
            throw IntegrationFailure("invalidResponse", "Unsupported mac-themer palette schema.")
        }
        guard let name = root["name"] as? String, !name.isEmpty,
              let slug = root["slug"] as? String, !slug.isEmpty,
              let variant = root["variant"] as? String, variant == "dark" || variant == "light" else {
            throw IntegrationFailure("invalidResponse", "Palette identity is invalid.")
        }
        guard let alpha = integer(root["alpha_byte"]), alpha >= 0, alpha <= 255 else {
            throw IntegrationFailure("invalidResponse", "Palette alpha_byte is invalid.")
        }
        guard let palette = root["palette"] as? [String: Any] else {
            throw IntegrationFailure("invalidResponse", "Palette is missing its ANSI layer.")
        }
        for key in paletteKeys { _ = try color(palette[key], "palette.\(key)") }
        guard let tokens = root["tokens"] as? [String: Any] else {
            throw IntegrationFailure("invalidResponse", "Palette is missing its semantic tokens.")
        }
        for key in tokenKeys { _ = try color(tokens[key], "tokens.\(key)") }
        guard let border = root["border"] as? [String: Any] else {
            throw IntegrationFailure("invalidResponse", "Palette is missing its border colours.")
        }
        _ = try color(border["active"], "border.active")
        _ = try color(border["inactive"], "border.inactive")
        guard let bar = root["bar"] as? [String: Any] else {
            throw IntegrationFailure("invalidResponse", "Palette is missing its bar colours.")
        }
        for key in barKeys { _ = try color(bar[key], "bar.\(key)") }
        // Published metadata is optional, but when present it must be the type
        // the schema documents so a consumer never renders a stray object.
        for key in ["generated_by", "pack", "backgrounds"] {
            if let value = root[key], !(value is String) {
                throw IntegrationFailure("invalidResponse", "Palette \(key) must be a string.")
            }
        }
        return root
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        guard double.isFinite, double.rounded() == double,
              double >= Double(Int.min), double <= Double(Int.max) else { return nil }
        return number.intValue
    }

    private static func color(_ value: Any?, _ where_: String) throws -> String {
        guard let string = value as? String,
              string.range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil else {
            throw IntegrationFailure("invalidResponse", "\(where_) must be #rrggbb.")
        }
        return string
    }
}
