import CoreAudio
import Foundation

// CoreAudio driver for the property boundary in AudioHardware.swift.
// Read/write logic adapts helper/bar.swift 672-733 and listener attachment
// adapts 3619-3648 from omacosy. MIT, Copyright (c) 2026 Paul Spende.
// See third_party/omacosy/LICENSE. All callbacks land on the injected queue,
// which is the controller's serial worker, never the macOS main / Qt thread.
final class CoreAudioHardware: AudioHardware {
    private let queue: DispatchQueue

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    private func target(_ device: UInt32, _ property: AudioProperty) -> AudioObjectID {
        switch property {
        case .defaultOutput: return AudioObjectID(kAudioObjectSystemObject)
        default: return AudioObjectID(device)
        }
    }

    private func address(_ property: AudioProperty) -> AudioObjectPropertyAddress {
        switch property {
        case .defaultOutput:
            return AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        case .alive:
            return AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyDeviceIsAlive,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        case .configuration:
            return AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
                mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        case .volume(let element):
            return AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar,
                mScope: kAudioDevicePropertyScopeOutput, mElement: element)
        case .mute:
            return AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute,
                mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        }
    }

    private func check(_ status: OSStatus, _ operation: String) throws {
        guard status == noErr else {
            throw AudioFailure("nativeFailure", "\(operation) OSStatus \(status)")
        }
    }

    func defaultOutput() throws -> UInt32 {
        var addr = address(.defaultOutput)
        var id: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        try check(AudioObjectGetPropertyData(target(0, .defaultOutput), &addr, 0, nil, &size, &id),
                  "read default output")
        return id
    }

    func channels(_ device: UInt32) throws -> [UInt32] {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioObjectPropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        let object = AudioObjectID(device)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(object, &addr, 0, nil, &size),
                  "stream configuration size")
        let header = MemoryLayout<AudioBufferList>.offset(of: \.mBuffers) ?? MemoryLayout<UInt32>.size
        guard Int(size) >= header, size <= 1_048_576 else {
            throw AudioFailure("nativeFailure", "stream configuration size \(size) is too small")
        }
        let capacity = Int(size)
        let raw = UnsafeMutableRawPointer.allocate(byteCount: capacity,
                                                   alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { raw.deallocate() }
        try check(AudioObjectGetPropertyData(object, &addr, 0, nil, &size, raw),
                  "stream configuration")
        guard Int(size) >= header, Int(size) <= capacity else {
            throw AudioFailure("nativeFailure", "invalid returned stream configuration size")
        }
        let list = raw.assumingMemoryBound(to: AudioBufferList.self)
        let buffers = Int(list.pointee.mNumberBuffers)
        let maxBuffers = (Int(size) - header) / MemoryLayout<AudioBuffer>.stride
        guard buffers >= 0, buffers <= maxBuffers else {
            throw AudioFailure("nativeFailure",
                               "stream configuration reported \(buffers) buffers for \(size) bytes")
        }
        var total = 0
        for buffer in UnsafeMutableAudioBufferListPointer(list) {
            total += Int(buffer.mNumberChannels)
        }
        guard total > 0 else { return [] }
        guard total <= 256 else {
            throw AudioFailure("nativeFailure", "stream configuration reported \(total) channels")
        }
        return Array(1...UInt32(total))
    }

    func has(_ device: UInt32, _ property: AudioProperty) -> Bool {
        var addr = address(property)
        return AudioObjectHasProperty(target(device, property), &addr)
    }

    func settable(_ device: UInt32, _ property: AudioProperty) throws -> Bool {
        var addr = address(property)
        var settable: DarwinBoolean = false
        try check(AudioObjectIsPropertySettable(target(device, property), &addr, &settable),
                  "is settable")
        return settable.boolValue
    }

    func read(_ device: UInt32, _ property: AudioProperty) throws -> Double {
        if property == .configuration { throw AudioFailure("unsupported", "Use channels for stream configuration") }
        var addr = address(property)
        let object = target(device, property)
        if case .volume = property {
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            try check(AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value),
                      "read volume")
            return Double(value)
        }
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        try check(AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &value),
                  "read \(property)")
        return Double(value)
    }

    func write(_ device: UInt32, _ property: AudioProperty, _ value: Double) throws {
        var addr = address(property)
        let object = target(device, property)
        switch property {
        case .volume:
            var scalar = Float32(value)
            try check(AudioObjectSetPropertyData(object, &addr, 0, nil,
                                                 UInt32(MemoryLayout<Float32>.size), &scalar),
                      "write volume")
        case .mute:
            var flag: UInt32 = value != 0 ? 1 : 0
            try check(AudioObjectSetPropertyData(object, &addr, 0, nil,
                                                 UInt32(MemoryLayout<UInt32>.size), &flag),
                      "write mute")
        case .defaultOutput, .alive, .configuration:
            throw AudioFailure("unsupported", "\(property) is read-only")
        }
    }

    func observe(_ device: UInt32, _ property: AudioProperty,
                 _ callback: @escaping () -> Void) throws -> () throws -> Void {
        var addr = address(property)
        let object = target(device, property)
        let queue = self.queue
        let block: AudioObjectPropertyListenerBlock = { _, _ in callback() }
        try check(AudioObjectAddPropertyListenerBlock(object, &addr, queue, block),
                  "add listener")
        return {
            var removeAddr = addr
            let status = AudioObjectRemovePropertyListenerBlock(object, &removeAddr, queue, block)
            guard status == noErr else {
                throw AudioFailure("nativeFailure", "remove listener OSStatus \(status)")
            }
        }
    }
}
