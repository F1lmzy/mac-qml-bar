import Foundation

// All methods and hardware callbacks run on one serial utility queue.
// Native state is never inferred from a successful write return.
final class AudioController {
    private let hardware: AudioHardware
    private var emit: (([String: Any]) -> Void)?
    private var defaultCancel: (() throws -> Void)?
    private var deviceCancels: [() throws -> Void] = []
    private var device: UInt32 = 0
    private var generation = 0
    private var watched: [AudioProperty] = []
    private var state: [String: Any] = [:]
    private let retry: ((@escaping () -> Void) -> Void)?
    private var recoveryPending = false
    private var lifecycle = 0

    init(hardware: AudioHardware, retry: ((@escaping () -> Void) -> Void)? = nil) {
        self.hardware = hardware
        self.retry = retry
    }
    func start(_ callback: @escaping ([String: Any]) -> Void) {
        stop()
        emit = callback
        refresh()
    }
    private func recoverLater() {
        guard !recoveryPending, let retry = retry else { return }
        recoveryPending = true
        let token = lifecycle
        retry { [weak self] in
            guard let self = self, self.lifecycle == token, self.emit != nil else { return }
            self.recoveryPending = false
            self.refresh()
        }
    }
    private func removeDeviceListeners() {
        generation += 1
        for cancel in deviceCancels {
            do { try cancel() } catch { NSLog("Pill Audio listener removal: %@", String(describing: error)) }
        }
        deviceCancels.removeAll()
        watched.removeAll()
    }
    func stop() {
        lifecycle += 1
        recoveryPending = false
        emit = nil
        removeDeviceListeners()
        do { try defaultCancel?() } catch { NSLog("Pill Audio default listener removal: %@", String(describing: error)) }
        defaultCancel = nil
        device = 0
    }
    private func empty() -> [String: Any] {
        ["available": false, "outputDeviceId": "", "volumeKnown": false,
         "volume": Double.nan, "muteKnown": false, "muted": false,
         "canSetVolume": false, "canMute": false, "lastErrorCode": "",
         "lastError": "", "errorOperation": ""]
    }
    private func volumes(_ id: UInt32) throws -> [AudioProperty] {
        if hardware.has(id, .volume(0)) { return [.volume(0)] }
        return try hardware.channels(id).map { .volume($0) }
    }
    private func watch(_ properties: [AudioProperty]) throws {
        guard properties != watched else { return }
        removeDeviceListeners()
        let token = generation
        for prop in properties {
            deviceCancels.append(try hardware.observe(device, prop) { [weak self] in
                guard let self = self, self.generation == token else { return }
                self.refresh()
            })
        }
        watched = properties // Only after every attachment succeeded.
    }
    func refresh() {
        guard emit != nil else { return }
        var next = empty()
        var failure: Error?
        if defaultCancel == nil {
            do {
                defaultCancel = try hardware.observe(0, .defaultOutput) { [weak self] in self?.refresh() }
            } catch { failure = error; recoverLater() }
        }
        do {
            let current = try hardware.defaultOutput()
            if current != device { removeDeviceListeners(); device = current }
            guard device != 0 else { publish(next, failure); return }
            if hardware.has(device, .alive), try hardware.read(device, .alive) == 0 {
                try watch([.alive]) // Retain a recovery notification on this ID.
                publish(next, failure); return
            }
            next["available"] = true
            next["outputDeviceId"] = String(device)
            var props: [AudioProperty] = []
            do { props = try volumes(device) } catch { failure = error }
            let supported = props.filter { hardware.has(device, $0) }
            var toWatch = supported
            if hardware.has(device, .mute) { toWatch.append(.mute) }
            if hardware.has(device, .alive) { toWatch.append(.alive) }
            if hardware.has(device, .configuration) { toWatch.append(.configuration) }
            do { try watch(toWatch) } catch { failure = failure ?? error }
            // Probe/read separately: failed settability must not hide a read.
            let complete = !props.isEmpty && supported.count == props.count
            do {
                next["canSetVolume"] = try complete && supported.allSatisfy { try hardware.settable(device, $0) }
            } catch { failure = failure ?? error }
            do {
                if complete {
                    let values = try supported.map { try hardware.read(device, $0) }
                    guard values.allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
                        throw AudioFailure("invalid native volume scalar")
                    }
                    next["volume"] = values.reduce(0, +) / Double(values.count)
                    next["volumeKnown"] = true
                }
            } catch { failure = failure ?? error }
            if hardware.has(device, .mute) {
                do { next["canMute"] = try hardware.settable(device, .mute) }
                catch { failure = failure ?? error }
                do {
                    next["muted"] = try hardware.read(device, .mute) != 0
                    next["muteKnown"] = true
                } catch { failure = failure ?? error }
            }
            publish(next, failure)
        } catch { publish(next, error) }
    }
    private func publish(_ next: [String: Any], _ error: Error?) {
        state = next
        if let error = error {
            recoverLater() // One pending, one-second retry only while degraded.
            fail("refresh", error)
        } else { emit?(state) }
    }
    private func fail(_ operation: String, _ error: Error) {
        if state.isEmpty { state = empty() }
        let failure = error as? AudioFailure ?? AudioFailure(String(describing: error))
        state["lastErrorCode"] = failure.code
        state["lastError"] = failure.description
        state["errorOperation"] = operation
        emit?(state)
    }
    private func validate(_ expected: UInt32) throws {
        refresh() // Re-resolve and probe at the time of the write.
        guard state["available"] as? Bool == true, device == expected else {
            throw AudioFailure("unavailable", "Default output changed or disconnected")
        }
    }
    func setVolume(_ value: Double, device expected: UInt32) {
        guard emit != nil else { return }
        do {
            guard value.isFinite else { throw AudioFailure("invalidInput", "Volume must be finite") }
            try validate(expected)
            guard state["canSetVolume"] as? Bool == true else {
                throw AudioFailure("unsupported", "Output has no settable scalar volume")
            }
            for prop in try volumes(device) {
                try hardware.write(device, prop, min(1, max(0, value)))
            }
            refresh()
        } catch {
            refresh() // Partial channel writes can have changed real state.
            fail("setVolume", error)
        }
    }
    func setMuted(_ value: Bool, device expected: UInt32) {
        guard emit != nil else { return }
        do {
            try validate(expected)
            guard state["canMute"] as? Bool == true else {
                throw AudioFailure("unsupported", "Output has no settable mute")
            }
            try hardware.write(device, .mute, value ? 1 : 0)
            refresh()
        } catch { refresh(); fail("setMuted", error) }
    }
}
