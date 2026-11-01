import Foundation
import CoreGraphics
import CryptoKit
import ImageIO

// Persistent preview cache for the wallpaper carousel.
//
// Binding an Image straight to the wallpaper file made every tile decode a
// 300-500 KB WebP/HEIC, which is slow enough to see as a stall on the first
// paint. Measured on the installed Osaka Jade pack, a 512 px JPEG preview is
// 27-42 KB and decodes in a few milliseconds, so the strip can render from
// cache the moment it opens.
//
// The key covers the source path, mtime and size, so replacing a wallpaper in
// place yields a new key instead of serving a stale preview. Everything here is
// best-effort: an unreadable or unsupported image is skipped, never thrown, so
// one bad file cannot stop the carousel from opening.
enum WallpaperThumbnails {
    // A wallpaper larger than this is not worth decoding for a preview; the
    // carousel falls back to the full-size file for that row.
    static let maxSourceBytes = 64 << 20
    static let maxPixel = 512
    static let quality = 0.82
    static let maxCacheBytes = 128 << 20

    // Matches CFBundleIdentifier in Info.plist. Spelled out rather than read
    // from Bundle.main, because the fixture test binary has no bundle and would
    // otherwise cache under a different directory than the app.
    static let cacheFolder = "local.pill.macos-spike/wallpaper-thumbs"

    struct Signature {
        let mtime: Double
        let size: Int
    }

    static func cacheDirectory() -> URL {
        if let value = ProcessInfo.processInfo.environment["PILL_THUMB_CACHE"], !value.isEmpty {
            return URL(fileURLWithPath: (value as NSString).expandingTildeInPath)
        }
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Caches")
        return base.appendingPathComponent(cacheFolder, isDirectory: true)
    }

    // attributesOfItem, not URL.resourceValues: NSURL caches resource values on
    // the instance, so a repeated call on the same URL can report a stale mtime
    // after a wallpaper is replaced in place.
    static func signature(of url: URL) -> Signature? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = (attributes[.size] as? NSNumber)?.intValue, size > 0, size <= maxSourceBytes else { return nil }
        let modified = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return Signature(mtime: modified, size: size)
    }

    // SHA256 rather than Swift's Hasher: Hasher is seeded per process, so a key
    // built from it would miss the cache on every launch.
    static func key(path: String, mtime: Double, size: Int) -> String {
        var material = Data(path.utf8)
        material.append(0)
        material.append(contentsOf: Array(String(format: "%.3f", mtime).utf8))
        material.append(0)
        material.append(contentsOf: Array(String(size).utf8))
        return SHA256.hash(data: material).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    static func cacheURL(for source: URL, directory: URL) -> URL? {
        guard let signature = signature(of: source) else { return nil }
        let digest = key(path: source.path, mtime: signature.mtime, size: signature.size)
        let stem = (source.lastPathComponent as NSString).deletingPathExtension
            .replacingOccurrences(of: "/", with: "_")
        return directory.appendingPathComponent("\(stem.prefix(48))-\(digest).jpg")
    }

    // Used while building the wallpaper snapshot: cheap enough to call per row
    // on every reconciliation pass, since it only stats the cache file.
    static func existingThumb(for source: URL, directory: URL) -> URL? {
        guard let destination = cacheURL(for: source, directory: directory) else { return nil }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: destination.path),
              ((attributes[.size] as? NSNumber)?.intValue ?? 0) > 0 else { return nil }
        return destination
    }

    // Identifies one generation attempt. Keyed by the cache file name so a
    // wallpaper replaced in place (new mtime, new key) is retried, and by the
    // source path when no key can be derived, so an unreadable file is not
    // re-decoded on every reconciliation pass.
    static func attemptKey(for source: URL, directory: URL) -> String {
        if let destination = cacheURL(for: source, directory: directory) { return destination.lastPathComponent }
        return "unreadable:" + source.path
    }

    // Returns whether a file was written, so the caller knows to republish the
    // snapshot with the new thumb URL.
    @discardableResult
    static func writeIfNeeded(source: URL, directory: URL) -> Bool {
        guard let destination = cacheURL(for: source, directory: directory) else { return false }
        if let attributes = try? FileManager.default.attributesOfItem(atPath: destination.path),
           ((attributes[.size] as? NSNumber)?.intValue ?? 0) > 0 {
            return false
        }
        guard let data = render(source: source) else { return false }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // .atomic writes to a sibling temp file and renames, so a concurrent
            // reader never sees a half-written preview.
            try data.write(to: destination, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    // ImageIO decodes every format the catalogue accepts, WebP and HEIC
    // included. JPEG drops alpha, which is fine for wallpapers and keeps the
    // cache roughly a third the size of PNG.
    static func render(source: URL, maxPixel: Int = maxPixel, quality: Double = quality) -> Data? {
        guard let imageSource = CGImageSourceCreateWithURL(source as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }

    // Drops previews the current theme no longer references, then trims oldest
    // first until the directory is back under the cap. Called after each
    // generation pass so a deleted pack's previews are reclaimed.
    static func prune(directory: URL, keeping: Set<String>, maxBytes: Int = maxCacheBytes) {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys)) else { return }
        var kept: [(url: URL, modified: Date, size: Int)] = []
        for entry in entries {
            guard let values = try? entry.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            let name = entry.lastPathComponent
            if !keeping.contains(name) {
                try? FileManager.default.removeItem(at: entry)
                continue
            }
            kept.append((entry, values.contentModificationDate ?? .distantPast, values.fileSize ?? 0))
        }
        var total = kept.reduce(0) { $0 + $1.size }
        guard total > maxBytes else { return }
        for item in kept.sorted(by: { $0.modified < $1.modified }) {
            guard total > maxBytes else { break }
            try? FileManager.default.removeItem(at: item.url)
            total -= item.size
        }
    }
}
