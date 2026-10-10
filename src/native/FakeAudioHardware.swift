import Foundation

// Explicit test fixture only. The production singleton never chooses it.
final class FakeAudioHardware: AudioHardware {
    struct Key: Hashable { let device: UInt32; let property: AudioProperty }
    var device: UInt32 = 10
    var values: [Key: Double] = [:]
    var readOnly: Set<Key> = []
    var readFailures: Set<Key> = []
    var writeFailures: Set<Key> = []
    var probeFailures: Set<Key> = []
    var observeFailures: Set<Key> = []
    var channelList: [UInt32] = [1, 2]
    var listeners: [UUID: (Key, () -> Void)] = [:]
    var writes = 0
    init() {
        values[Key(device: 10, property: .alive)] = 1
        values[Key(device: 10, property: .configuration)] = 1
        values[Key(device: 10, property: .volume(0))] = 0.45
        values[Key(device: 10, property: .mute)] = 0
    }
    func defaultOutput() throws -> UInt32 { device }
    func channels(_ device: UInt32) throws -> [UInt32] { channelList }
    func has(_ device: UInt32, _ property: AudioProperty) -> Bool {
        values[Key(device: device, property: property)] != nil
    }
    func settable(_ device: UInt32, _ property: AudioProperty) throws -> Bool {
        let key = Key(device: device, property: property)
        if probeFailures.contains(key) { throw AudioFailure("fixture probe failure") }
        return !readOnly.contains(key)
    }
    func read(_ device: UInt32, _ property: AudioProperty) throws -> Double {
        let key = Key(device: device, property: property)
        guard !readFailures.contains(key), let value = values[key] else {
            throw AudioFailure("fixture read failure")
        }
        return value
    }
    func write(_ device: UInt32, _ property: AudioProperty, _ value: Double) throws {
        let key = Key(device: device, property: property)
        guard has(device, property), !readOnly.contains(key), !writeFailures.contains(key) else {
            throw AudioFailure("fixture write failure")
        }
        writes += 1
        values[key] = value
        notify(device, property)
    }
    func observe(_ device: UInt32, _ property: AudioProperty,
                 _ callback: @escaping () -> Void) throws -> () throws -> Void {
        if observeFailures.contains(Key(device: device, property: property)) {
            throw AudioFailure("fixture listener failure")
        }
        let id = UUID()
        listeners[id] = (Key(device: device, property: property), callback)
        return { [weak self] in self?.listeners.removeValue(forKey: id) }
    }
    func notify(_ device: UInt32, _ property: AudioProperty) {
        let key = Key(device: device, property: property)
        let callbacks = listeners.values.filter { $0.0 == key }.map { $0.1 }
        callbacks.forEach { $0() }
    }
}
