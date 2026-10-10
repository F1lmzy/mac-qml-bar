import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments == ["--read-only"] || arguments == ["--write-and-restore"] else { exit(2) }
let writes = arguments == ["--write-and-restore"]
guard !writes || ProcessInfo.processInfo.environment["PILL_AUDIO_HARDWARE_TEST"] == "1" else {
    fputs("Writes require PILL_AUDIO_HARDWARE_TEST=1 and --write-and-restore.\n", stderr)
    exit(2)
}
let queue = DispatchQueue(label: "pill.audio.hardware-check")
let hardware = CoreAudioHardware(queue: queue)
let service = AudioController(hardware: hardware)
var state: [String: Any] = [:] // Access only on queue.
queue.sync { service.start { state = $0 } }
func snapshot() -> [String: Any] { queue.sync { state } }
func waitFor(_ predicate: ([String: Any]) -> Bool) -> Bool {
    for _ in 0..<100 {
        if predicate(snapshot()) { return true }
        Thread.sleep(forTimeInterval: 0.02)
    }
    return false
}
let initial = snapshot()
print("Audio available=\(initial["available"] ?? false) device=\(initial["outputDeviceId"] ?? "")"
    + " volume=\(initial["volume"] ?? Double.nan) canSetVolume=\(initial["canSetVolume"] ?? false)"
    + " muted=\(initial["muted"] ?? false) canMute=\(initial["canMute"] ?? false)"
    + " error=\(initial["lastError"] ?? "")")
var status: Int32 = 0
if writes {
    do {
        guard initial["volumeKnown"] as? Bool == true, initial["muteKnown"] as? Bool == true,
              initial["canSetVolume"] as? Bool == true, initial["canMute"] as? Bool == true,
              let id = UInt32(initial["outputDeviceId"] as? String ?? "") else {
            throw AudioFailure("unsupported", "Need readable/settable volume and mute for restoring test")
        }
        let saved: [(AudioProperty, Double)] = try queue.sync {
            let volumes: [AudioProperty] = hardware.has(id, .volume(0))
                ? [.volume(0)] : try hardware.channels(id).map { .volume($0) }
            return try (volumes + [.mute]).map { ($0, try hardware.read(id, $0)) }
        }
        // Restore the original device and individual channel values, not their average.
        // Defer runs on failures as well; no early exit is allowed inside this scope.
        defer {
            do {
                try queue.sync {
                    if hardware.has(id, .alive), try hardware.read(id, .alive) == 0 {
                        throw AudioFailure("Original device disconnected; cannot restore")
                    }
                    var firstFailure: Error?
                    for (property, value) in saved {
                        do { try hardware.write(id, property, value) }
                        catch { firstFailure = firstFailure ?? error }
                    }
                    if let failure = firstFailure { throw failure }
                }
                guard waitFor({ _ in
                    (try? queue.sync {
                        try saved.allSatisfy { abs(try hardware.read(id, $0.0) - $0.1) < 0.005 }
                    }) == true
                }) else { throw AudioFailure("Restored values were not observed") }
                print("PASS: original channel volume and mute restored")
            } catch { fputs("RESTORE FAILED: \(error)\n", stderr); status = 1 }
        }
        let target = max(0, (initial["volume"] as? Double ?? 0) - 0.05)
        queue.sync { service.setVolume(target, device: id) }
        guard waitFor({ abs(($0["volume"] as? Double ?? -1) - target) < 0.02
                        && $0["lastErrorCode"] as? String == "" }) else {
            throw AudioFailure("Volume write not confirmed")
        }
        let muted = !(initial["muted"] as? Bool ?? false)
        queue.sync { service.setMuted(muted, device: id) }
        guard waitFor({ $0["muted"] as? Bool == muted
                        && $0["lastErrorCode"] as? String == "" }) else {
            throw AudioFailure("Mute write not confirmed")
        }
        print("PASS: volume and mute writes observed")
    } catch { fputs("FAIL: \(error)\n", stderr); status = 1 }
} else if initial["lastErrorCode"] as? String != "" {
    status = 1
}
queue.sync { service.stop() }
exit(status)
