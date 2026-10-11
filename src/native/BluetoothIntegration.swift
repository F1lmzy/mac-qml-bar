import AppKit
import CoreBluetooth
import Foundation
import IOBluetooth
import Darwin

// All classic Bluetooth access is gated immediately before use. In
// particular, do not construct a CBCentralManager just to inspect TCC state.
final class BluetoothIntegration: PillIntegration, CBCentralManagerDelegate {
    static func authorizationNameForTest(_ value: CBManagerAuthorization) -> String {
        switch value {
        case .allowedAlways: return "authorized"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "notDetermined"
        @unknown default: return "unknown"
        }
    }

    private var central: CBCentralManager?
    private var authorization = CBCentralManager.authorization
    private var launchRequired = false
    private var refreshQueued = false
    private var operationGeneration = 0

    override func start(_ callback: @escaping ([String: Any]) -> Void) {
        precondition(Thread.isMainThread)
        super.start(callback)
        authorization = CBCentralManager.authorization
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didActivateApplicationNotification) { [weak self] _ in
            guard let self = self else { return }
            self.authorization = CBCentralManager.authorization
            self.refresh()
        }
        every(10) { [weak self] in
            guard let self = self, self.authorization == .allowedAlways else { return }
            self.refresh()
        }
        refresh()
    }

    override func refresh() {
        precondition(Thread.isMainThread)
        authorization = CBCentralManager.authorization
        guard authorization == .allowedAlways else {
            operationGeneration += 1
            refreshQueued = false
            publish(["available": false, "permission": Self.authorizationNameForTest(authorization),
                     "devices": [], "canRequestPermission": authorization == .notDetermined,
                     "canConnect": false, "canReadPower": false, "powered": false,
                     "launchRequired": launchRequired])
            return
        }
        guard !refreshQueued else { return }
        refreshQueued = true
        operationGeneration += 1
        let token = operationGeneration
        perform("refresh", work: { _ in
            guard CBCentralManager.authorization == .allowedAlways else {
                throw IntegrationFailure("permissionDenied", "Bluetooth permission is no longer authorized.")
            }
            // IOBluetooth calls can abort on TCC denial. Recheck the gate
            // immediately before every classic API access.
            let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
            let rows: [[String: Any]] = devices.compactMap { device in
                guard CBCentralManager.authorization == .allowedAlways else { return nil }
                let id = device.addressString ?? ""
                guard !id.isEmpty else { return nil }
                return ["id": id, "name": device.name ?? id, "connected": device.isConnected()]
            }
            let power = Self.readPowerIfAuthorized()
            return ["available": true, "permission": "authorized", "devices": rows,
                    "canConnect": true, "canReadPower": power != nil, "powered": power ?? false,
                    "canRequestPermission": false]
        }, receive: { [weak self] snapshot in
            guard let self = self, self.operationGeneration == token else { return }
            self.refreshQueued = false
            self.publish(snapshot)
        }, failure: { [weak self] error in
            guard let self = self, self.operationGeneration == token else { return }
            self.refreshQueued = false
            if CBCentralManager.authorization != .allowedAlways {
                self.authorization = CBCentralManager.authorization
                self.publish(["available": false, "permission": Self.authorizationNameForTest(self.authorization),
                              "devices": [], "canConnect": false, "canReadPower": false, "powered": false])
            } else {
                self.fail("refresh", error.code, error.message)
            }
        })
    }

    override func invoke(_ action: String, _ argument: Any) {
        precondition(Thread.isMainThread)
        switch action {
        case "requestPermission":
            guard Bundle.main.object(forInfoDictionaryKey: "NSBluetoothAlwaysUsageDescription") as? String != nil else {
                fail(action, "configuration", "Bluetooth usage description is missing from the app bundle."); return
            }
            guard getppid() == 1 else {
                launchRequired = true
                fail(action, "launchRequired", "Quit and open PillSpike.app from Finder before requesting Bluetooth access.")
                return
            }
            authorization = CBCentralManager.authorization
            guard authorization == .notDetermined else { refresh(); return }
            guard central == nil else { return }
            // This is the only construction site. It is reachable only from
            // the explicit UI action and a LaunchServices-responsible process.
            central = CBCentralManager(delegate: self, queue: .main)
        case "connect", "disconnect":
            authorization = CBCentralManager.authorization
            guard authorization == .allowedAlways else {
                publishDeniedState()
                fail(action, "permissionDenied", "Bluetooth access is required.")
                return
            }
            guard let id = (argument as? [String: Any])?["id"] as? String,
                  !id.isEmpty, id.count <= 32 else {
                fail(action, "invalidInput", "Expected a paired Bluetooth device ID."); return
            }
            operationGeneration += 1
            refreshQueued = false
            let token = operationGeneration
            perform(action, work: { _ in
                guard CBCentralManager.authorization == .allowedAlways else {
                    throw IntegrationFailure("permissionDenied", "Bluetooth permission is no longer authorized.")
                }
                guard let device = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice])?.first(where: {
                    guard CBCentralManager.authorization == .allowedAlways else { return false }
                    return $0.addressString == id
                }) else { throw IntegrationFailure("stale", "Bluetooth device is no longer paired.") }
                guard CBCentralManager.authorization == .allowedAlways else {
                    throw IntegrationFailure("permissionDenied", "Bluetooth permission changed before the action.")
                }
                let status = action == "connect" ? device.openConnection() : device.closeConnection()
                guard status == kIOReturnSuccess else {
                    throw IntegrationFailure("nativeFailure", "Bluetooth action failed (\(status)).")
                }
                // Re-query on this worker; never claim the requested state
                // merely because the synchronous call returned success.
                guard CBCentralManager.authorization == .allowedAlways else {
                    throw IntegrationFailure("permissionDenied", "Bluetooth permission changed after the action.")
                }
                let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
                let rows: [[String: Any]] = devices.compactMap { device in
                    guard CBCentralManager.authorization == .allowedAlways else { return nil }
                    let address = device.addressString ?? ""
                    guard !address.isEmpty else { return nil }
                    return ["id": address, "name": device.name ?? address, "connected": device.isConnected()]
                }
                return ["available": true, "permission": "authorized", "devices": rows,
                        "canConnect": true, "canReadPower": false, "powered": false]
            }, receive: { [weak self] snapshot in
                guard let self = self, self.operationGeneration == token else { return }
                self.publish(snapshot)
            }, failure: { [weak self] error in
                guard let self = self, self.operationGeneration == token else { return }
                if error.code == "permissionDenied" { self.publishDeniedState() }
                self.fail(action, error.code, error.message)
            })
        case "openSettings":
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!)
        default:
            super.invoke(action, argument)
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        precondition(Thread.isMainThread)
        authorization = CBCentralManager.authorization
        if authorization == .allowedAlways { refresh() }
        else { publishDeniedState() }
    }

    override func stop() {
        precondition(Thread.isMainThread)
        operationGeneration += 1
        refreshQueued = false
        central?.delegate = nil
        central = nil
        super.stop()
    }

    private func publishDeniedState() {
        authorization = CBCentralManager.authorization
        operationGeneration += 1
        refreshQueued = false
        publish(["available": false, "permission": Self.authorizationNameForTest(authorization),
                 "devices": [], "canRequestPermission": authorization == .notDetermined,
                 "canConnect": false, "canReadPower": false, "powered": false,
                 "launchRequired": launchRequired])
    }

    private static func readPowerIfAuthorized() -> Bool? {
        guard CBCentralManager.authorization == .allowedAlways else { return nil }
        guard let handle = dlopen("/System/Library/Frameworks/IOBluetooth.framework/IOBluetooth", RTLD_LAZY) else { return nil }
        defer { dlclose(handle) }
        guard let symbol = dlsym(handle, "IOBluetoothPreferenceGetControllerPowerState") else { return nil }
        guard CBCentralManager.authorization == .allowedAlways else { return nil }
        typealias Function = @convention(c) () -> Int32
        return unsafeBitCast(symbol, to: Function.self)() != 0
    }
}
