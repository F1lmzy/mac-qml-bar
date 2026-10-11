import Foundation

guard CommandLine.arguments.contains("--write-and-restore"),
      ProcessInfo.processInfo.environment["PILL_DISPLAY_HARDWARE_TEST"] == "1" else {
    fputs("This test changes brightness. Require PILL_DISPLAY_HARDWARE_TEST=1 and --write-and-restore.\n", stderr); exit(2)
}
let service = BrightnessIntegration()
var state: [String: Any] = [:], sequence = 0
service.start { state = $0; sequence += 1 }
func wait(_ condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(10)
    while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    return condition()
}
guard wait({ state["known"] as? Bool == true }), state["canSet"] as? Bool == true,
      let original = state["value"] as? Double, let display = state["displayId"] as? String else {
    service.stop(); fputs("No supported built-in display.\n", stderr); exit(77)
}
var failed = false
func verifyBrightness() {
    defer {
        let beforeRestore = sequence
        service.invoke("set", ["value": original, "displayId": display])
        if !wait({ sequence > beforeRestore && state["known"] as? Bool == true && state["displayId"] as? String == display &&
            abs((state["value"] as? Double ?? -1) - original) < 0.01 }) {
            fputs("FAIL: brightness restoration not confirmed; restore manually.\n", stderr); failed = true
        }
        service.stop()
    }
    let target = original > 0.15 ? original - 0.05 : original + 0.05, before = sequence
    service.invoke("set", ["value": target, "displayId": display])
    if !wait({ sequence > before && state["known"] as? Bool == true && abs((state["value"] as? Double ?? -1) - target) < 0.01 }) {
        fputs("FAIL: brightness change not confirmed.\n", stderr); failed = true
    }
}
verifyBrightness()
if !failed { print("PASS: built-in brightness changed and restoration observed") }
exit(failed ? 1 : 0)
