import CoreAudio
import Foundation

private enum OutputDevicesDriver {
    static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
    static func deviceName(_ id: UInt32) throws -> String {
        var a = address(kAudioObjectPropertyName), value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        let status = AudioObjectGetPropertyData(id, &a, 0, nil, &size, &value)
        guard status == 0, let value = value else { throw IntegrationFailure("nativeFailure", "Audio device name failed (\(status)).") }
        // AudioHardwareBase.h: the caller releases the returned CFObject.
        return value.takeRetainedValue() as String
    }
    static var canSelect: Bool {
        var a = address(kAudioHardwarePropertyDefaultOutputDevice), settable = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(UInt32(kAudioObjectSystemObject), &a, &settable) == 0 && settable.boolValue
    }
    static func devices() throws -> [[String: Any]] {
        var a = address(kAudioHardwarePropertyDevices), size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(UInt32(kAudioObjectSystemObject), &a, 0, nil, &size) == 0,
              size <= 65536, size % 4 == 0 else { throw IntegrationFailure("nativeFailure", "Cannot enumerate audio devices.") }
        let capacity = size
        var ids = [UInt32](repeating: 0, count: Int(size / 4))
        guard AudioObjectGetPropertyData(UInt32(kAudioObjectSystemObject), &a, 0, nil, &size, &ids) == 0, size <= capacity, size % 4 == 0 else { throw IntegrationFailure("nativeFailure", "Cannot read audio devices.") }
        var selected: UInt32 = 0, defaultAddress = address(kAudioHardwarePropertyDefaultOutputDevice), defaultSize: UInt32 = 4
        guard AudioObjectGetPropertyData(UInt32(kAudioObjectSystemObject), &defaultAddress, 0, nil, &defaultSize, &selected) == 0, defaultSize == 4 else { throw IntegrationFailure("nativeFailure", "Cannot read the current output device.") }
        return try ids.prefix(Int(size / 4)).filter { id in
            var stream = address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput), bytes: UInt32 = 0
            return AudioObjectGetPropertyDataSize(id, &stream, 0, nil, &bytes) == 0 && bytes > 0
        }.map { id in
            let name = try deviceName(id)
            return ["id": String(id), "name": name, "default": id == selected]
        }
    }
    static func select(_ id: UInt32) throws {
        guard try devices().contains(where: { $0["id"] as? String == String(id) }) else { throw IntegrationFailure("staleIdentifier", "Output device is no longer connected.") }
        var a = address(kAudioHardwarePropertyDefaultOutputDevice), settable = DarwinBoolean(false), selected = id
        guard AudioObjectIsPropertySettable(UInt32(kAudioObjectSystemObject), &a, &settable) == 0, settable.boolValue else { throw IntegrationFailure("unsupported", "Default output selection is unavailable.") }
        let status = AudioObjectSetPropertyData(UInt32(kAudioObjectSystemObject), &a, 0, nil, 4, &selected)
        guard status == 0 else { throw IntegrationFailure("nativeFailure", "Output selection failed (\(status)).") }
    }
}
final class OutputDevicesIntegration: PillIntegration {
    private let hardware = CoreAudioHardware(queue: DispatchQueue(label: "local.pill.device-events"))
    private var removals: [() throws -> Void] = []
    override func start(_ callback: @escaping ([String: Any]) -> Void) {
        super.start(callback)
        // Exact listener blocks are retained by the driver; this weak delivery
        // is created on main before being passed to its event queue.
        let deliver: () -> Void = { [weak self] in self?.refresh() }
        for property in [AudioProperty.defaultOutput] {
            do { removals.append(try hardware.observe(1, property) { DispatchQueue.main.async { deliver() } }) }
            catch { fail("subscribe", "nativeFailure", String(describing: error)) }
        }
        every(5) { [weak self] in self?.refresh() } // device-list reconciliation
    }
    override func refresh() {
        perform("devices.read", work: { _ in
            let devices = try OutputDevicesDriver.devices()
            return ["available": !devices.isEmpty, "devices": devices, "canSelect": !devices.isEmpty && OutputDevicesDriver.canSelect]
        })
    }
    override func invoke(_ action: String, _ argument: Any) {
        guard action == "select", let id = argument as? String, let numeric = UInt32(id) else {
            fail(action, "invalidInput", "Expected a current output device ID."); return
        }
        perform(action, work: { _ in
            try OutputDevicesDriver.select(numeric)
            return ["available": true, "devices": try OutputDevicesDriver.devices(), "canSelect": OutputDevicesDriver.canSelect]
        })
    }
    override func stop() {
        removals.forEach { do { try $0() } catch { NSLog("Pill output listener removal failed: %@", String(describing: error)) } }; removals.removeAll()
        super.stop()
    }
}
