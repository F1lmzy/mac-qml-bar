import AppKit
import CoreGraphics
import Foundation
import ObjectiveC.runtime
import Darwin

private typealias GetBrightnessFn = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
private typealias SetBrightnessFn = @convention(c) (UInt32, Float) -> Int32
private final class DisplayDriver {
    private let library: UnsafeMutableRawPointer?
    private let getFn: GetBrightnessFn?
    private let setFn: SetBrightnessFn?
    init() {
        library = ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26
            ? dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY | RTLD_LOCAL) : nil
        getFn = library.flatMap { dlsym($0, "DisplayServicesGetBrightness") }.map { unsafeBitCast($0, to: GetBrightnessFn.self) }
        setFn = library.flatMap { dlsym($0, "DisplayServicesSetBrightness") }.map { unsafeBitCast($0, to: SetBrightnessFn.self) }
    }
    deinit { if let library { dlclose(library) } }
    func read(_ display: UInt32) throws -> Double {
        guard let getFn else { throw IntegrationFailure("unsupported", "DisplayServices brightness API is unavailable.") }
        var value: Float = 0
        let status = getFn(display, &value)
        guard status == 0, value.isFinite, (0...1).contains(value) else { throw IntegrationFailure("nativeFailure", "Brightness read failed (\(status)).") }
        return Double(value)
    }
    func write(_ display: UInt32, _ value: Double) throws {
        guard let setFn else { throw IntegrationFailure("unsupported", "DisplayServices brightness API is unavailable.") }
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count <= 64 else { throw IntegrationFailure("unavailable", "Display topology is unavailable.") }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success,
              ids.prefix(Int(count)).contains(display), CGDisplayIsBuiltin(display) != 0 else {
            throw IntegrationFailure("unavailable", "The requested built-in display is no longer active.")
        }
        let status = setFn(display, Float(value))
        guard status == 0 else { throw IntegrationFailure("nativeFailure", "Brightness write failed (\(status)).") }
    }
    var canSet: Bool { getFn != nil && setFn != nil }
}

struct GammaTable: Equatable {
    static let maximumSamples = 65_536
    let red: [Float]
    let green: [Float]
    let blue: [Float]

    init(red: [Float], green: [Float], blue: [Float]) throws {
        guard !red.isEmpty, red.count <= Self.maximumSamples,
              red.count == green.count, red.count == blue.count,
              (red + green + blue).allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            throw IntegrationFailure("invalidResponse", "Display returned an invalid gamma table.")
        }
        self.red = red; self.green = green; self.blue = blue
    }

    func shaded(_ amount: Double) throws -> GammaTable {
        let scale = Float(1 - amount * 0.85)
        return try GammaTable(red: red.map { $0 * scale }, green: green.map { $0 * scale }, blue: blue.map { $0 * scale })
    }

    func matches(_ other: GammaTable, tolerance: Float = 0.0001) -> Bool {
        guard red.count == other.red.count else { return false }
        return zip(red + green + blue, other.red + other.green + other.blue).allSatisfy { abs($0 - $1) <= tolerance }
    }
}

private final class GammaDriver {
    private var original: [UInt32: GammaTable] = [:]
    private var applied: [UInt32: GammaTable] = [:]
    private(set) var amount = 0.0
    func canShade(_ displays: [UInt32]) -> Bool { !displays.isEmpty && displays.allSatisfy { (try? read($0)) != nil } }

    private func topology() throws -> [UInt32] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count <= 64 else {
            throw IntegrationFailure("unavailable", "Display topology is unavailable.")
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else {
            throw IntegrationFailure("unavailable", "Display topology could not be read.")
        }
        return Array(ids.prefix(Int(count)))
    }

    private func read(_ display: UInt32) throws -> GammaTable {
        let capacity = GammaTable.maximumSamples
        var red = [CGGammaValue](repeating: 0, count: capacity)
        var green = [CGGammaValue](repeating: 0, count: capacity)
        var blue = [CGGammaValue](repeating: 0, count: capacity)
        var count: UInt32 = 0
        let status = red.withUnsafeMutableBufferPointer { r in
            green.withUnsafeMutableBufferPointer { g in
                blue.withUnsafeMutableBufferPointer { b in
                    CGGetDisplayTransferByTable(display, UInt32(capacity), r.baseAddress!, g.baseAddress!, b.baseAddress!, &count)
                }
            }
        }
        guard status == .success, count > 0, count <= UInt32(capacity) else {
            throw IntegrationFailure("nativeFailure", "Could not read display gamma table (\(status.rawValue)).")
        }
        return try GammaTable(red: Array(red.prefix(Int(count))), green: Array(green.prefix(Int(count))), blue: Array(blue.prefix(Int(count))))
    }

    private func write(_ table: GammaTable, display: UInt32) throws {
        var red = table.red, green = table.green, blue = table.blue
        let count = UInt32(red.count)
        let status = red.withUnsafeMutableBufferPointer { r in
            green.withUnsafeMutableBufferPointer { g in
                blue.withUnsafeMutableBufferPointer { b in
                    CGSetDisplayTransferByTable(display, count, r.baseAddress!, g.baseAddress!, b.baseAddress!)
                }
            }
        }
        guard status == .success else { throw IntegrationFailure("nativeFailure", "Could not write display gamma table (\(status.rawValue)).") }
    }

    func setShade(_ amount: Double, displays: [UInt32]) throws {
        let amount = try finiteUnit(amount)
        guard Set(try topology()) == Set(displays), displays.count <= 64 else {
            throw IntegrationFailure("unavailable", "Display topology changed before the request.")
        }
        var before: [UInt32: GammaTable] = [:]
        var baselines: [UInt32: GammaTable] = [:]
        var targets: [UInt32: GammaTable] = [:]
        for id in displays {
            let current = try read(id)
            before[id] = current
            if let prior = applied[id] {
                guard current.matches(prior), let baseline = original[id] else {
                    original.removeValue(forKey: id); applied.removeValue(forKey: id)
                    throw IntegrationFailure("stale", "Display gamma changed outside Pill; refusing to overwrite it.")
                }
                baselines[id] = baseline
            } else {
                baselines[id] = current
            }
            targets[id] = amount == 0 ? baselines[id]! : try baselines[id]!.shaded(amount)
        }

        var changed: [UInt32] = []
        do {
            for id in displays {
                try write(targets[id]!, display: id)
                changed.append(id)
                let observed = try read(id)
                guard observed.matches(targets[id]!, tolerance: 0.005) else { throw IntegrationFailure("nativeFailure", "Gamma change was not confirmed.") }
                targets[id] = observed
            }
        } catch {
            for id in changed {
                do {
                    guard try read(id).matches(targets[id]!) else { NSLog("Pill gamma rollback skipped: external change on display %u.", id); continue }
                    try write(before[id]!, display: id)
                }
                catch { NSLog("Pill gamma rollback failed for display %u: %@", id, String(describing: error)) }
            }
            throw error
        }
        self.amount = amount
        if amount == 0 {
            for id in displays { original.removeValue(forKey: id); applied.removeValue(forKey: id) }
        } else {
            for id in displays { original[id] = baselines[id]; applied[id] = targets[id] }
        }
    }

    func restore() {
        for (id, baseline) in original {
            do {
                let current = try read(id)
                guard let last = applied[id], current.matches(last) else {
                    NSLog("Pill gamma restore skipped for display %u: table changed outside Pill.", id)
                    continue
                }
                try write(baseline, display: id)
            } catch {
                NSLog("Pill gamma restore failed for display %u: %@", id, String(describing: error))
            }
        }
        original.removeAll(); applied.removeAll(); amount = 0
    }
}

private struct BlueLightStatus {
    var active = ObjCBool(false); var enabled = ObjCBool(false); var sunSchedulePermitted = ObjCBool(false)
    var mode: Int32 = 0; var schedule = (Int32(0), Int32(0), Int32(0), Int32(0))
    var disableFlags: UInt64 = 0; var available = ObjCBool(false)
}
private final class BlueLightDriver {
    private let framework: UnsafeMutableRawPointer?
    private let cls: NSObject.Type?
    private let client: NSObject?
    private let allowed: Bool
    init() {
        allowed = ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26
        let handle = allowed ? dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY | RTLD_LOCAL) : nil
        if let handle, let type = NSClassFromString("CBBlueLightClient") as? NSObject.Type {
            framework = handle; cls = type; client = type.init()
        } else {
            if let handle { dlclose(handle) }
            framework = nil; cls = nil; client = nil
        }
    }
    deinit { if let framework { dlclose(framework) } }
    func read() -> Bool? {
        guard let cls, let client else { return nil }
        let selector = NSSelectorFromString("getBlueLightStatus:")
        guard let method = class_getInstanceMethod(cls, selector) else { return nil }
        typealias Function = @convention(c) (AnyObject, Selector, UnsafeMutableRawPointer) -> Bool
        // Private output struct may grow. A padded buffer avoids a small struct
        // overwrite; the known macOS 26 layout remains a version-tested ABI.
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: 4096, alignment: 16)
        defer { buffer.deallocate() }
        buffer.initializeMemory(as: UInt8.self, repeating: 0, count: 4096)
        let ok = unsafeBitCast(method_getImplementation(method), to: Function.self)(client, selector, buffer)
        let status = buffer.load(as: BlueLightStatus.self)
        return ok && status.available.boolValue ? status.enabled.boolValue : nil
    }
    func write(_ enabled: Bool) throws {
        guard allowed, let cls, let client else { throw IntegrationFailure("unsupported", "Night Shift private API is unavailable on this macOS version.") }
        let selector = NSSelectorFromString("setEnabled:")
        guard let method = class_getInstanceMethod(cls, selector) else { throw IntegrationFailure("unsupported", "Night Shift setter is unavailable.") }
        typealias Function = @convention(c) (AnyObject, Selector, Bool) -> Bool
        guard unsafeBitCast(method_getImplementation(method), to: Function.self)(client, selector, enabled) else {
            throw IntegrationFailure("nativeFailure", "Night Shift rejected the request.")
        }
    }
    var canSet: Bool { allowed && cls.map { class_getInstanceMethod($0, NSSelectorFromString("setEnabled:")) != nil } == true }
}

struct DisplaySample { let id: UInt32; let name: String; let builtin: Bool }
struct DisplaySnapshot {
    let builtinId: UInt32?; let brightnessKnown: Bool; let brightness: Double
    let canSetBrightness: Bool; let nightShiftKnown: Bool; let canSetNightShift: Bool
    static func make(displays: [DisplaySample], brightness: Double?, canSetBrightness: Bool, nightShift: Bool?) -> DisplaySnapshot {
        let id = displays.first(where: \.builtin)?.id
        let known = id != nil && brightness != nil && brightness!.isFinite && (0...1).contains(brightness!)
        return DisplaySnapshot(builtinId: id, brightnessKnown: known, brightness: known ? brightness! : 0,
                               canSetBrightness: id != nil && canSetBrightness, nightShiftKnown: nightShift != nil,
                               canSetNightShift: nightShift != nil)
    }
}
struct DisplayWritePin {
    let expected: UInt32
    func validate(current: UInt32?, requested: Double) throws -> Double {
        guard current == expected else { throw IntegrationFailure("unavailable", "Built-in display changed.") }
        return try finiteUnit(requested)
    }
}

private struct GammaFormula: Equatable {
    var values: [Float]
    static func read(_ id: CGDirectDisplayID) -> GammaFormula? {
        var rMin: Float = 0, rMax: Float = 0, rGamma: Float = 0
        var gMin: Float = 0, gMax: Float = 0, gGamma: Float = 0
        var bMin: Float = 0, bMax: Float = 0, bGamma: Float = 0
        let status = CGGetDisplayTransferByFormula(id, &rMin, &rMax, &rGamma, &gMin, &gMax, &gGamma, &bMin, &bMax, &bGamma)
        return status == .success ? GammaFormula(values: [rMin, rMax, rGamma, gMin, gMax, gGamma, bMin, bMax, bGamma]) : nil
    }
    func apply(_ id: CGDirectDisplayID) -> Bool {
        CGSetDisplayTransferByFormula(id, values[0], values[1], values[2], values[3], values[4], values[5], values[6], values[7], values[8]) == .success
    }
    func matches(_ other: GammaFormula?) -> Bool {
        guard let other, values.count == other.values.count else { return false }
        return zip(values, other.values).allSatisfy { abs($0 - $1) < 0.0001 }
    }
    func shaded(_ amount: Double) -> GammaFormula {
        let scale = Float(1 - amount * 0.85); var v = values
        for i in [1, 4, 7] { v[i] *= scale }
        return GammaFormula(values: v)
    }
}

private func activeDisplaySamples() -> [DisplaySample] {
    var count: UInt32 = 0
    guard CGGetActiveDisplayList(0, nil, &count) == .success, count <= 64 else { return [] }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
    let names = NSScreen.screens.reduce(into: [UInt32: String]()) { result, screen in
        if let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            result[number.uint32Value] = screen.localizedName
        }
    }
    return ids.prefix(Int(count)).map { DisplaySample(id: $0, name: names[$0] ?? "Display \($0)", builtin: CGDisplayIsBuiltin($0) != 0) }
}

class BrightnessIntegration: PillIntegration {
    private let driver = DisplayDriver()
    private var displayId: UInt32?
    private var readPending = false
    private var revision = 0
    override func start(_ callback: @escaping ([String: Any]) -> Void) {
        super.start(callback); precondition(Thread.isMainThread)
        observe(.default, NSNotification.Name("NSApplicationDidChangeScreenParametersNotification")) { [weak self] _ in self?.refresh() }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification) { [weak self] _ in self?.refresh() }
        // The private notification ABI has no documented unregister contract.
        // Poll only this one value at a modest rate; screen/wake events refresh sooner.
        every(2) { [weak self] in self?.refresh() }
        refresh()
    }
    override func refresh() {
        precondition(Thread.isMainThread)
        let id = activeDisplaySamples().first(where: \.builtin)?.id
        if id != displayId { revision += 1; readPending = false; displayId = id }
        guard let id else { publish(["available": false, "displayId": "", "known": false, "value": 0.0, "canSet": false]); return }
        guard !readPending else { return }
        readPending = true
        let driver = self.driver, token = revision
        perform("brightness.read", work: { _ in
            do {
                let value = try driver.read(id)
                return ["available": true, "displayId": String(id), "known": true, "value": value, "canSet": driver.canSet]
            } catch let error as IntegrationFailure {
                return ["available": true, "displayId": String(id), "known": false, "value": 0.0, "canSet": driver.canSet,
                        "lastErrorCode": error.code, "lastError": error.message]
            }
        }, receive: { [weak self] fields in
            guard let self = self, self.revision == token else { return }
            self.readPending = false
            guard self.displayId == id, activeDisplaySamples().first(where: \.builtin)?.id == id else { self.refresh(); return }
            self.publish(fields)
        }, failure: { [weak self] error in
            guard let self = self, self.revision == token else { return }
            self.readPending = false; self.fail("brightness.read", error.code, error.message)
        })
    }
    override func invoke(_ action: String, _ argument: Any) {
        precondition(Thread.isMainThread)
        guard action == "set", let fields = argument as? [String: Any],
              let expected = UInt32(fields["displayId"] as? String ?? ""), let current = displayId, expected == current else {
            fail(action, "unavailable", "The built-in display changed or is unavailable."); return
        }
        do { let value = try finiteUnit(fields["value"] ?? NSNull()); let driver = self.driver
            revision += 1; readPending = false
            perform("brightness.set", work: { _ in
                try driver.write(expected, value); let observed = try driver.read(expected)
                return ["available": true, "displayId": String(expected), "known": true, "value": observed, "canSet": driver.canSet]
            }, receive: { [weak self] fields in
                guard let self = self else { return }
                guard activeDisplaySamples().first(where: \.builtin)?.id == expected else { self.refresh(); return }
                self.publish(fields)
            })
        } catch let error as IntegrationFailure { fail(action, error.code, error.message) }
        catch { fail(action, "invalidInput", String(describing: error)) }
    }
    override func stop() { revision += 1; readPending = false; super.stop() }
}

class DisplayIntegration: PillIntegration {
    private let blue = BlueLightDriver()
    private let gamma = GammaDriver()
    private var shade = 0.0
    override func start(_ callback: @escaping ([String: Any]) -> Void) {
        super.start(callback); precondition(Thread.isMainThread)
        observe(.default, NSNotification.Name("NSApplicationDidChangeScreenParametersNotification")) { [weak self] _ in self?.refresh() }
        every(3) { [weak self] in self?.refresh() }
        refresh()
    }
    override func refresh() {
        precondition(Thread.isMainThread)
        let displays = activeDisplaySamples()
        let blue = self.blue, gamma = self.gamma, canSet = blue.canSet
        perform("display.read", work: { _ in
            let night = blue.read()
            return ["available": !displays.isEmpty, "screens": displays.map { ["id": String($0.id), "name": $0.name, "builtin": $0.builtin] },
                    "nightShiftKnown": night != nil, "nightShiftEnabled": night ?? false, "canSetNightShift": canSet,
                    "shade": gamma.amount, "canShade": gamma.canShade(displays.map(\.id))]
        })
    }
    override func invoke(_ action: String, _ argument: Any) {
        precondition(Thread.isMainThread)
        switch action {
        case "setNightShift":
            guard let value = argument as? Bool, blue.canSet else { fail(action, "unsupported", "Night Shift control is unavailable."); return }
            let blue = self.blue, gamma = self.gamma, displays = activeDisplaySamples()
            perform(action, work: { _ in
                try blue.write(value)
                guard let observed = blue.read() else { throw IntegrationFailure("nativeFailure", "Night Shift state could not be confirmed.") }
                return ["available": !displays.isEmpty, "screens": displays.map { ["id": String($0.id), "name": $0.name, "builtin": $0.builtin] },
                        "nightShiftKnown": true, "nightShiftEnabled": observed, "canSetNightShift": blue.canSet,
                        "shade": gamma.amount, "canShade": gamma.canShade(displays.map(\.id))]
            })
        case "setShade":
            do { let amount = try finiteUnit(argument); let displays = activeDisplaySamples().map(\.id); guard !displays.isEmpty else { throw IntegrationFailure("unavailable", "No active displays.") }
                let gamma = self.gamma, blue = self.blue, screenSamples = activeDisplaySamples()
                perform(action, work: { _ in
                    try gamma.setShade(amount, displays: displays)
                    let night = blue.read()
                    return ["available": !screenSamples.isEmpty, "screens": screenSamples.map { ["id": String($0.id), "name": $0.name, "builtin": $0.builtin] },
                            "nightShiftKnown": night != nil, "nightShiftEnabled": night ?? false, "canSetNightShift": blue.canSet,
                            "shade": amount, "canShade": !screenSamples.isEmpty]
                }, receive: { [weak self] snapshot in self?.shade = amount; self?.publish(snapshot) })
            } catch let error as IntegrationFailure { fail(action, error.code, error.message) } catch { fail(action, "nativeFailure", String(describing: error)) }
        default: fail(action, "unsupported", "Unknown display action.")
        }
    }
    override func stop() {
        precondition(Thread.isMainThread)
        let gamma = self.gamma
        worker.async { gamma.restore() }
        shade = 0
        super.stop()
    }
}
