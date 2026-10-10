import Foundation

// Property-level boundary shared by real CoreAudio and deterministic fixtures.
enum AudioProperty: Hashable {
    case defaultOutput, alive, configuration, volume(UInt32), mute
}

struct AudioFailure: Error, CustomStringConvertible {
    let code: String
    let description: String
    init(_ description: String) { self.init("nativeFailure", description) }
    init(_ code: String, _ description: String) {
        self.code = code
        self.description = description
    }
}

protocol AudioHardware: AnyObject {
    func defaultOutput() throws -> UInt32
    func channels(_ device: UInt32) throws -> [UInt32]
    func has(_ device: UInt32, _ property: AudioProperty) -> Bool
    func settable(_ device: UInt32, _ property: AudioProperty) throws -> Bool
    func read(_ device: UInt32, _ property: AudioProperty) throws -> Double
    func write(_ device: UInt32, _ property: AudioProperty, _ value: Double) throws
    // Runs on the controller queue; cancellation removes the exact listener.
    func observe(_ device: UInt32, _ property: AudioProperty,
                 _ callback: @escaping () -> Void) throws -> () throws -> Void
}
