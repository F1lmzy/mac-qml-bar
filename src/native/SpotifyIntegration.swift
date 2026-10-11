import AppKit
import Foundation

enum SpotifyMetadata {
    static func parse(_ fields: [String: Any]) -> [String: Any] {
        let status = fields["Player State"] as? String ?? ""
        let title = fields["Name"] as? String ?? "", artist = fields["Artist"] as? String ?? ""
        return ["available": true, "running": true, "known": !title.isEmpty,
                "title": title, "artist": artist, "album": fields["Album"] as? String ?? "",
                "playing": status == "Playing", "playbackKnown": ["Playing", "Paused", "Stopped"].contains(status),
                "canControl": true, "canRequestPermission": true]
    }
}
final class SpotifyIntegration: PillIntegration {
    private var permission = "notDetermined"
    override func start(_ callback: @escaping ([String: Any]) -> Void) {
        super.start(callback)
        observe(DistributedNotificationCenter.default(), Notification.Name("com.spotify.client.PlaybackStateChanged")) { [weak self] notification in
            guard let self = self, self.isRunningSpotify, let fields = notification.userInfo as? [String: Any] else { return }
            var next = SpotifyMetadata.parse(fields); next["permission"] = self.permission; self.publish(next)
        }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observe(NSWorkspace.shared.notificationCenter, name) { [weak self] _ in self?.refresh() }
        }
        every(5) { [weak self] in if self?.isRunningSpotify == false { self?.refresh() } }
    }
    private var isRunningSpotify: Bool { !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty }
    override func refresh() {
        if !isRunningSpotify {
            publish(["available": false, "running": false, "known": false, "title": "", "artist": "", "playing": false,
                     "canControl": false, "canRequestPermission": false, "permission": permission])
        } else if state["running"] as? Bool != true {
            publish(["available": true, "running": true, "known": false, "title": "", "artist": "", "playing": false,
                     "canControl": true, "canRequestPermission": true, "permission": permission])
        }
        // Never send an Apple Event merely to prime metadata at startup.
    }
    override func invoke(_ action: String, _ argument: Any) {
        guard ["requestPermission", "refresh", "previous", "playPause", "next"].contains(action) else { super.invoke(action, argument); return }
        guard isRunningSpotify else { fail(action, "unavailable", "Spotify is not running."); return }
        guard Bundle.main.object(forInfoDictionaryKey: "NSAppleEventsUsageDescription") != nil else { fail(action, "configuration", "Automation usage description is missing."); return }
        let command = ["previous": "previous track", "playPause": "playpause", "next": "next track"][action]
        let script = """
        if application id "com.spotify.client" is not running then error "Spotify is not running"
        tell application id "com.spotify.client"
        \(command ?? "")
        set t to ""
        set a to ""
        set al to ""
        try
        set t to name of current track
        set a to artist of current track
        set al to album of current track
        end try
        return t & (ASCII character 31) & a & (ASCII character 31) & al & (ASCII character 31) & (player state as string)
        end tell
        """
        perform(action, work: { cancellation in
            let output = try CommandRunner.run("/usr/bin/osascript", ["-e", script], timeout: 8, cancellation: cancellation)
            let lines = (String(data: output.stdout, encoding: .utf8) ?? "").trimmingCharacters(in: .newlines).components(separatedBy: "\u{001f}")
            guard lines.count == 4 else { throw IntegrationFailure("invalidResponse", "Spotify returned incomplete metadata.") }
            var next = SpotifyMetadata.parse(["Name": lines[0], "Artist": lines[1], "Album": lines[2],
                                              "Player State": ["playing": "Playing", "paused": "Paused", "stopped": "Stopped"][lines[3].lowercased()] ?? ""])
            next["permission"] = "authorized"; return next
        }, receive: { [weak self] next in self?.permission = "authorized"; self?.publish(next) })
    }
}
