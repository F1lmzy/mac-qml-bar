import Foundation

private func checkDisplay(_ condition: @autoclosure () -> Bool, _ name: String) {
    precondition(condition(), "display fixture failed: \(name)")
}

// Pure fixtures only. Never construct a framework-backed driver or invoke an
// integration action here; these checks are safe in non-GUI test runs.
func runDisplayTests() throws {
    for (input, expected) in [(0.0, 0.0), (0.5, 0.5), (1.0, 1.0), (-1.0, 0.0), (2.0, 1.0)] {
        let actual = try finiteUnit(input)
        checkDisplay(actual == expected, "finite clamp \(input)")
    }
    do { _ = try finiteUnit(Double.nan); preconditionFailure("NaN accepted") }
    catch let failure as IntegrationFailure { checkDisplay(failure.code == "invalidInput", "NaN code") }
    do { _ = try finiteUnit(Double.infinity); preconditionFailure("infinity accepted") }
    catch let failure as IntegrationFailure { checkDisplay(failure.code == "invalidInput", "infinity code") }

    let noBattery = BatterySnapshot.parse(sources: [])
    checkDisplay(!noBattery.available && !noBattery.known && noBattery.charge == 0, "no stale battery")
    let upsOnly = BatterySnapshot.parse(sources: [PowerSample(current: 40, maximum: 80, sourceState: "Battery Power", isCharging: false, type: "UPS")])
    checkDisplay(!upsOnly.available, "UPS is not an internal battery")
    let partial = BatterySnapshot.parse(sources: [PowerSample(current: 40, maximum: 80, sourceState: "Battery Power", isCharging: false, type: "InternalBattery")])
    checkDisplay(partial.available && partial.known && partial.charge == 0.5 && partial.charging == false && partial.onAC == false, "battery normalization")
    let charging = BatterySnapshot.parse(sources: [PowerSample(current: 100, maximum: 100, sourceState: "AC Power", isCharging: true, type: "InternalBattery")])
    checkDisplay(charging.charging && charging.onAC && charging.charge == 1, "AC state")
    let malformed = BatterySnapshot.parse(sources: [PowerSample(current: 90, maximum: 0, sourceState: "Battery Power", isCharging: false, type: "InternalBattery")])
    checkDisplay(!malformed.available && !malformed.known, "bad denominator unavailable")

    let noBuiltIn = DisplaySnapshot.make(displays: [DisplaySample(id: 7, name: "External", builtin: false)], brightness: nil, canSetBrightness: false, nightShift: nil)
    checkDisplay(noBuiltIn.builtinId == nil && !noBuiltIn.brightnessKnown, "external is not builtin")
    let found = DisplaySnapshot.make(displays: [DisplaySample(id: 7, name: "External", builtin: false), DisplaySample(id: 42, name: "Panel", builtin: true)], brightness: 0.4, canSetBrightness: true, nightShift: nil)
    checkDisplay(found.builtinId == 42 && found.brightnessKnown && found.brightness == 0.4, "built-in selection")
    checkDisplay(!found.nightShiftKnown && !found.canSetNightShift, "private API missing")
    let outOfRange = DisplaySnapshot.make(displays: [DisplaySample(id: 42, name: "Panel", builtin: true)], brightness: 1.4, canSetBrightness: true, nightShift: true)
    checkDisplay(!outOfRange.brightnessKnown && outOfRange.canSetBrightness && outOfRange.nightShiftKnown, "invalid hardware read")

    let pin = DisplayWritePin(expected: 42)
    let pinnedValue = try pin.validate(current: 42, requested: 0.7)
    checkDisplay(pinnedValue == 0.7, "pinned display write")
    do { _ = try pin.validate(current: 99, requested: 0.7); preconditionFailure("display switch accepted") }
    catch let failure as IntegrationFailure { checkDisplay(failure.code == "unavailable", "display switch error") }
}
