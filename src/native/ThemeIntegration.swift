import Foundation

final class ThemeIntegration: PillIntegration {
    private let themeFile = NSHomeDirectory() + "/.config/omarchy/current/theme/sketchybar.sh"
    private let nextHelper = NSHomeDirectory() + "/.local/bin/theme-next"
    private let wallpaperHelper = NSHomeDirectory() + "/.local/bin/omacosy-helper"
    private var watcher: DispatchSourceFileSystemObject?
    override func start(_ callback: @escaping ([String: Any]) -> Void) {
        super.start(callback)
        // Low-rate reconciliation handles replacement/symlink changes without
        // creating or writing the donor-owned configuration path.
        every(10) { [weak self] in self?.refresh() }
    }
    override func refresh() {
        let file = themeFile, next = nextHelper, wallpaper = wallpaperHelper
        perform("theme.read", work: { _ in
            let exists = FileManager.default.fileExists(atPath: file)
            return ["available": exists, "name": exists ? URL(fileURLWithPath: file).resolvingSymlinksInPath().deletingLastPathComponent().lastPathComponent : "",
                    "canNext": FileManager.default.isExecutableFile(atPath: next),
                    "canResyncWallpaper": FileManager.default.isExecutableFile(atPath: wallpaper)]
        })
    }
    override func invoke(_ action: String, _ argument: Any) {
        guard let fields = argument as? [String: Any], fields["confirmed"] as? Bool == true else {
            fail(action, "confirmationRequired", "Confirm the donor helper action first."); return
        }
        let path: String, args: [String]
        switch action {
        case "next": path = nextHelper; args = []
        case "resyncWallpaper": path = wallpaperHelper; args = ["wallpaper", "resync"]
        default: super.invoke(action, argument); return
        }
        perform(action, work: { cancellation in
            _ = try CommandRunner.run(path, args, timeout: 15, cancellation: cancellation); return [:]
        }, receive: { [weak self] _ in self?.refresh() })
    }
}
