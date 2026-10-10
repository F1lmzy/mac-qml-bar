import Foundation
import CoreAudio

var assertions = 0
func check(_ ok: @autoclosure () -> Bool, _ name: String) {
    assertions += 1
    if !ok() { fputs("FAIL: \(name)\n", stderr); exit(1) }
}
typealias Key = FakeAudioHardware.Key
func scenario(_ body: (FakeAudioHardware, AudioController, () -> [String: Any]) -> Void) {
    let fake = FakeAudioHardware()
    var snapshot: [String: Any] = [:]
    let controller = AudioController(hardware: fake)
    controller.start { snapshot = $0 }
    body(fake, controller, { snapshot })
    controller.stop()
    check(fake.listeners.isEmpty, "exact listener removal")
}
scenario { fake, service, state in
    check(state()["available"] as? Bool == true, "device available")
    check(state()["volume"] as? Double == 0.45, "normalized precision")
    service.setVolume(.nan, device: 10)
    check(state()["lastErrorCode"] as? String == "invalidInput", "reject NaN")
    service.setVolume(.infinity, device: 10)
    check(fake.writes == 0, "reject infinity without writes")
    service.setVolume(2, device: 10)
    check(state()["volume"] as? Double == 1, "clamp high")
    service.setVolume(-2, device: 10)
    check(state()["volume"] as? Double == 0, "clamp low")
    service.setMuted(true, device: 10)
    check(state()["muted"] as? Bool == true, "observed mute")
    fake.values[Key(device: 10, property: .volume(0))] = 0.73
    fake.notify(10, .volume(0))
    check(state()["volume"] as? Double == 0.73, "external update while muted")
}
scenario { fake, service, state in
    let master = Key(device: 10, property: .volume(0))
    fake.values.removeValue(forKey: master)
    fake.values[Key(device: 10, property: .volume(1))] = 0.2
    fake.values[Key(device: 10, property: .volume(2))] = 0.6
    service.refresh()
    check(abs((state()["volume"] as? Double ?? -1) - 0.4) < 0.00001, "channel average")
    service.setVolume(0.5, device: 10)
    check(fake.values[Key(device: 10, property: .volume(2))] == 0.5, "all channels written")
    fake.readOnly.insert(Key(device: 10, property: .volume(2)))
    service.refresh()
    check(state()["canSetVolume"] as? Bool == false, "partial channel support disables write")
    let before = fake.writes
    service.setVolume(0.8, device: 10)
    check(fake.writes == before, "unsupported write rejected")
}
scenario { fake, service, state in
    let master = Key(device: 10, property: .volume(0))
    fake.readFailures.insert(master)
    service.refresh()
    check(state()["volumeKnown"] as? Bool == false, "read failure clears observed value")
    check((state()["volume"] as? Double)?.isNaN == true, "unknown is not fabricated zero")
    fake.readFailures.remove(master)
    fake.writeFailures.insert(master)
    service.setVolume(0.9, device: 10)
    check(state()["lastErrorCode"] as? String == "nativeFailure", "checked write error")
    check(state()["volume"] as? Double == 0.45, "no optimistic update")
}
scenario { fake, service, state in
    let old = fake.listeners.values.filter { $0.0.device == 10 }.map { $0.1 }
    fake.device = 11
    fake.values[Key(device: 11, property: .alive)] = 1
    fake.values[Key(device: 11, property: .mute)] = 1
    fake.notify(0, .defaultOutput)
    check(state()["outputDeviceId"] as? String == "11", "device replacement")
    check(state()["volumeKnown"] as? Bool == false, "unsupported output has no scalar")
    check(state()["canMute"] as? Bool == true, "mute capability independent")
    service.setVolume(0.6, device: 10)
    check(fake.writes == 0, "stale drag cannot write new output")
    old.forEach { $0() }
    check(state()["outputDeviceId"] as? String == "11", "late old listener ignored")
    fake.device = 0
    fake.notify(0, .defaultOutput)
    check(state()["available"] as? Bool == false, "disconnection")
    check(state()["muteKnown"] as? Bool == false, "disconnection clears mute")
}
scenario { fake, service, state in
    let volume = Key(device: 10, property: .volume(0))
    fake.probeFailures.insert(volume)
    service.refresh()
    check(state()["volumeKnown"] as? Bool == true, "failed probe does not hide read")
    check(state()["canSetVolume"] as? Bool == false, "failed probe cannot advertise writes")
    fake.probeFailures.remove(volume)
    fake.observeFailures.insert(volume)
    fake.values.removeValue(forKey: volume)
    service.refresh()
    fake.values[volume] = 0.42
    fake.notify(10, .configuration)
    check(state()["lastErrorCode"] as? String == "nativeFailure", "listener failure reported")
    fake.observeFailures.remove(volume)
    service.refresh()
    check(state()["lastErrorCode"] as? String == "", "listener attachment retries")
    fake.values[Key(device: 10, property: .alive)] = 0
    fake.notify(10, .alive)
    check(state()["available"] as? Bool == false, "dead device clears state")
    fake.values[Key(device: 10, property: .alive)] = 1
    fake.notify(10, .alive)
    check(state()["volumeKnown"] as? Bool == true, "alive listener recovers same device")
}
do {
    let fake = FakeAudioHardware()
    var retries: [() -> Void] = []
    var state: [String: Any] = [:]
    let controller = AudioController(hardware: fake, retry: { retries.append($0) })
    fake.observeFailures.insert(Key(device: 0, property: .defaultOutput))
    controller.start { state = $0 }
    check(state["volumeKnown"] as? Bool == true, "initial read survives listener failure")
    check(state["lastErrorCode"] as? String == "nativeFailure", "subscription error visible")
    check(retries.count == 1, "only one recovery pending")
    controller.refresh()
    check(retries.count == 1, "no retry storm")
    fake.observeFailures.removeAll()
    retries.removeFirst()()
    check(state["lastErrorCode"] as? String == "", "subscription retries and recovers")
    controller.stop()
    check(fake.listeners.isEmpty, "recovered listeners removed")
    let late = fake.listeners.values.map { $0.1 }
    late.forEach { $0() }
}
print("PASS: \(assertions) audio fixture assertions")
