import Foundation
import IOKit.ps

struct PowerSample { let current: Int; let maximum: Int; let sourceState: String; let isCharging: Bool; let type: String }
struct BatterySnapshot {
    let available: Bool; let known: Bool; let charge: Double; let charging: Bool; let onAC: Bool
    static func parse(sources: [PowerSample]) -> BatterySnapshot {
        guard let source = sources.first(where: { $0.type == kIOPSInternalBatteryType && $0.maximum > 0 && $0.current >= 0 && $0.current <= $0.maximum }) else {
            return BatterySnapshot(available: false, known: false, charge: 0, charging: false, onAC: false)
        }
        let ac = source.sourceState == kIOPSACPowerValue
        return BatterySnapshot(available: true, known: true, charge: Double(source.current) / Double(source.maximum), charging: source.isCharging, onAC: ac)
    }
    var dictionary: [String: Any] { ["available": available, "known": known, "charge": charge, "charging": charging, "onAC": onAC] }
}

private func readBatterySnapshot() -> [String: Any] {
    guard let information = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let sources = IOPSCopyPowerSourcesList(information)?.takeRetainedValue() as? [CFTypeRef] else {
        return BatterySnapshot.parse(sources: []).dictionary
    }
    let samples: [PowerSample] = sources.compactMap { source in
        guard let description = IOPSGetPowerSourceDescription(information, source)?.takeUnretainedValue() as? [String: Any],
              (description[kIOPSIsPresentKey] as? NSNumber)?.boolValue != false,
              let current = description[kIOPSCurrentCapacityKey] as? Int,
              let maximum = description[kIOPSMaxCapacityKey] as? Int,
              let state = description[kIOPSPowerSourceStateKey] as? String,
              let charging = description[kIOPSIsChargingKey] as? NSNumber,
              let type = description[kIOPSTypeKey] as? String else { return nil }
        return PowerSample(current: current, maximum: maximum, sourceState: state, isCharging: charging.boolValue, type: type)
    }
    return BatterySnapshot.parse(sources: samples).dictionary
}

private func batteryChanged(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let service = Unmanaged<BatteryIntegration>.fromOpaque(context).takeUnretainedValue()
    precondition(Thread.isMainThread)
    service.refresh()
}

class BatteryIntegration: PillIntegration {
    private var source: CFRunLoopSource?
    override func start(_ callback: @escaping ([String: Any]) -> Void) {
        super.start(callback); precondition(Thread.isMainThread)
        if source == nil, let unmanaged = IOPSNotificationCreateRunLoopSource(batteryChanged, Unmanaged.passUnretained(self).toOpaque()) {
            let created = unmanaged.takeRetainedValue()
            source = created
            CFRunLoopAddSource(CFRunLoopGetMain(), created, .commonModes)
        }
        refresh()
    }
    override func refresh() {
        precondition(Thread.isMainThread)
        perform("battery.read", work: { _ in readBatterySnapshot() })
    }
    override func stop() {
        precondition(Thread.isMainThread)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes); CFRunLoopSourceInvalidate(source); self.source = nil }
        super.stop()
    }
}
