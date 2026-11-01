import CoreGraphics
import Foundation
import ImageIO

// Fixtures for WallpaperThumbnails. These never read personal wallpaper files:
// every source image is generated here, and the cache lives in a temp dir.

private func checkThumb(_ condition: @autoclosure () -> Bool, _ name: String) {
    precondition(condition(), "thumbnail fixture failed: \(name)")
}

// Shared by the theme fixtures, which need a real decodable image to exercise
// the preview pipeline end to end.
func writeFixturePNG(_ url: URL, width: Int, height: Int) throws {
    let space = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw IntegrationFailure("fixture", "cannot allocate an image context")
    }
    context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        throw IntegrationFailure("fixture", "cannot encode a PNG fixture")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw IntegrationFailure("fixture", "cannot finalize a PNG fixture")
    }
}

func fixtureImageSize(_ url: URL) -> (width: Int, height: Int)? {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
          let width = properties[kCGImagePropertyPixelWidth] as? Int,
          let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
    return (width, height)
}

private func makeSparseFile(_ url: URL, bytes: Int) throws {
    guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
        throw IntegrationFailure("fixture", "cannot create a sparse file")
    }
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.truncate(atOffset: UInt64(bytes))
}

func runThumbnailTests() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("pill-thumbs-\(UUID().uuidString)")
    let cache = root.appendingPathComponent("cache")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

    // Cross-process stability matters more than determinism within one run: the
    // key must survive an app restart or the cache is dead weight. Pinning the
    // exact digest is what rules out Swift's per-process-seeded Hasher.
    checkThumb(WallpaperThumbnails.key(path: "/tmp/a.png", mtime: 1_700_000_000, size: 1234) == "bb8c3d54825f739c",
               "key is stable for known input")
    checkThumb(WallpaperThumbnails.key(path: "/tmp/a.png", mtime: 1_700_000_000, size: 1234)
               == WallpaperThumbnails.key(path: "/tmp/a.png", mtime: 1_700_000_000, size: 1234), "key repeats")
    checkThumb(WallpaperThumbnails.key(path: "/tmp/b.png", mtime: 1_700_000_000, size: 1234) != "bb8c3d54825f739c",
               "key covers the path")
    checkThumb(WallpaperThumbnails.key(path: "/tmp/a.png", mtime: 1_700_000_001, size: 1234) != "bb8c3d54825f739c",
               "key covers the mtime")
    checkThumb(WallpaperThumbnails.key(path: "/tmp/a.png", mtime: 1_700_000_000, size: 1235) != "bb8c3d54825f739c",
               "key covers the size")

    // A real, larger-than-preview image must downscale to the pixel cap.
    let source = root.appendingPathComponent("wide.png")
    try writeFixturePNG(source, width: 1200, height: 800)
    let sourceSize = (try? source.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    checkThumb(sourceSize > 0, "fixture has bytes")
    checkThumb(WallpaperThumbnails.signature(of: source) != nil, "signature reads")
    checkThumb(WallpaperThumbnails.existingThumb(for: source, directory: cache) == nil, "cold cache has no thumb")

    checkThumb(WallpaperThumbnails.writeIfNeeded(source: source, directory: cache), "first pass writes")
    guard let thumb = WallpaperThumbnails.existingThumb(for: source, directory: cache) else {
        preconditionFailure("thumbnail fixture failed: cache file missing after write")
    }
    guard let size = fixtureImageSize(thumb) else {
        preconditionFailure("thumbnail fixture failed: cache file is not decodable")
    }
    checkThumb(size.width == 512 && size.height <= 512, "thumb is capped at 512 px, got \(size)")
    let thumbBytes = (try? thumb.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    checkThumb(thumbBytes > 0 && thumbBytes < sourceSize, "thumb is smaller than the source")

    // A warm cache must not re-encode: the second pass is a stat and a skip.
    let firstModified = try FileManager.default.attributesOfItem(atPath: thumb.path)[.modificationDate] as? Date
    checkThumb(!WallpaperThumbnails.writeIfNeeded(source: source, directory: cache), "second pass skips")
    let secondModified = try FileManager.default.attributesOfItem(atPath: thumb.path)[.modificationDate] as? Date
    checkThumb(firstModified == secondModified, "warm cache is untouched")

    // Replacing the source in place changes mtime, so the key changes too.
    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: source.path)
    checkThumb(WallpaperThumbnails.cacheURL(for: source, directory: cache) != thumb, "replaced source yields a new key")
    checkThumb(WallpaperThumbnails.existingThumb(for: source, directory: cache) == nil, "stale thumb is not served")

    // Missing and oversize sources are skipped, not thrown.
    let missing = root.appendingPathComponent("absent.png")
    checkThumb(!WallpaperThumbnails.writeIfNeeded(source: missing, directory: cache), "missing source is skipped")
    checkThumb(WallpaperThumbnails.cacheURL(for: missing, directory: cache) == nil, "missing source has no key")
    checkThumb(WallpaperThumbnails.render(source: missing) == nil, "missing source does not render")
    let oversize = root.appendingPathComponent("huge.png")
    try makeSparseFile(oversize, bytes: WallpaperThumbnails.maxSourceBytes + 1)
    checkThumb(WallpaperThumbnails.signature(of: oversize) == nil, "oversize source is rejected")
    checkThumb(!WallpaperThumbnails.writeIfNeeded(source: oversize, directory: cache), "oversize source is skipped")

    // A file with an image extension that is not an image must not throw.
    let corrupt = root.appendingPathComponent("corrupt.png")
    try Data("not an image".utf8).write(to: corrupt)
    checkThumb(!WallpaperThumbnails.writeIfNeeded(source: corrupt, directory: cache), "corrupt source is skipped")

    // Prune drops unreferenced previews and keeps the referenced ones.
    let keepSource = root.appendingPathComponent("keep.png")
    try writeFixturePNG(keepSource, width: 640, height: 480)
    checkThumb(WallpaperThumbnails.writeIfNeeded(source: keepSource, directory: cache), "keep source writes")
    guard let keep = WallpaperThumbnails.existingThumb(for: keepSource, directory: cache) else {
        preconditionFailure("thumbnail fixture failed: keep cache file missing")
    }
    let stray = cache.appendingPathComponent("stray-deadbeef.jpg")
    try Data("stray".utf8).write(to: stray)
    WallpaperThumbnails.prune(directory: cache, keeping: [keep.lastPathComponent], maxBytes: WallpaperThumbnails.maxCacheBytes)
    checkThumb(FileManager.default.fileExists(atPath: keep.path), "prune keeps referenced previews")
    checkThumb(!FileManager.default.fileExists(atPath: stray.path), "prune removes unreferenced previews")
    checkThumb(!FileManager.default.fileExists(atPath: thumb.path), "prune removes the stale preview")

    // The cap trims oldest-first once the directory is over budget.
    let older = cache.appendingPathComponent("older.jpg")
    let newer = cache.appendingPathComponent("newer.jpg")
    try Data(repeating: 0x41, count: 4096).write(to: older)
    try Data(repeating: 0x42, count: 4096).write(to: newer)
    try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-600)], ofItemAtPath: older.path)
    try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: newer.path)
    WallpaperThumbnails.prune(directory: cache, keeping: [older.lastPathComponent, newer.lastPathComponent], maxBytes: 6000)
    checkThumb(!FileManager.default.fileExists(atPath: older.path), "cap trims the oldest first")
    checkThumb(FileManager.default.fileExists(atPath: newer.path), "cap keeps the newest")

    // The env override is how tests and any future relocation point the cache.
    setenv("PILL_THUMB_CACHE", cache.path, 1)
    checkThumb(WallpaperThumbnails.cacheDirectory().path == cache.path, "env override is honoured")
    unsetenv("PILL_THUMB_CACHE")
    checkThumb(WallpaperThumbnails.cacheDirectory().path.hasSuffix(WallpaperThumbnails.cacheFolder), "default cache path")

    print("PASS: wallpaper thumbnail cache fixtures")
}
