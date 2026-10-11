import AppKit
import CoreLocation
import CoreWLAN
import Foundation
import SystemConfiguration

final class WifiIntegration: PillIntegration, CLLocationManagerDelegate {
    static func mayReadSSIDForTest(permission: String) -> Bool { permission == "authorized" }
    private var locationManager: CLLocationManager?
    private var locationStatus = "notDetermined"
    private var dynamicStore: SCDynamicStore?
    private var dynamicSource: CFRunLoopSource?
    private let settingsURL = URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension")!

    override func start(_ callback: @escaping ([String: Any]) -> Void) {
        precondition(Thread.isMainThread)
        switch CLLocationManager.authorizationStatus() {
        case .authorized, .authorizedAlways: locationStatus = "authorized"
        case .denied, .restricted: locationStatus = "denied"
        default: locationStatus = "notDetermined"
        }
        super.start(callback)
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.didWakeNotification) { [weak self] _ in self?.refresh() }
        attachNetworkNotifications()
        every(5) { [weak self] in self?.refresh() }
        refresh()
    }

    override func refresh() {
        precondition(Thread.isMainThread)
        let authorized = Self.mayReadSSIDForTest(permission: locationStatus)
        let permission = locationStatus
        perform("refresh", work: { _ in
            let iface = CWWiFiClient.shared().interface()
            let powered = iface?.powerOn() ?? false
            var fields: [String: Any] = ["available": iface != nil, "known": iface != nil,
                "powered": powered, "canReadSSID": authorized, "ssidKnown": false,
                "ssid": NSNull(), "interface": iface?.interfaceName ?? ""]
            if let iface = iface, powered {
                fields["rssi"] = iface.rssiValue()
                fields["transmitRate"] = iface.transmitRate()
                if authorized, let ssid = iface.ssid() { fields["ssid"] = ssid; fields["ssidKnown"] = true }
                if let channel = iface.wlanChannel() { fields["channel"] = channel.channelNumber }
                fields["security"] = String(describing: iface.security())
            }
            if let name = iface?.interfaceName, let store = SCDynamicStoreCreate(nil, "local.pill.wifi" as CFString, nil, nil) {
                let ip = SCDynamicStoreCopyValue(store, "State:/Network/Interface/\(name)/IPv4" as CFString) as? [String: Any]
                let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
                fields["ipv4"] = (ip?["Addresses"] as? [String])?.first ?? ""
                fields["router"] = global?["Router"] as? String ?? ""
            }
            fields["permission"] = permission
            fields["canRequestPermission"] = permission == "notDetermined"
            fields["canOpenSettings"] = true
            return fields
        })
    }


    override func invoke(_ action: String, _ argument: Any) {
        precondition(Thread.isMainThread)
        switch action {
        case "requestPermission":
            guard getppid() == 1 else { fail(action, "launchRequired", "Open PillSpike.app from Finder or scripts/run.sh before requesting Location access."); return }
            guard Bundle.main.object(forInfoDictionaryKey: "NSLocationWhenInUseUsageDescription") as? String != nil else {
                fail(action, "configuration", "Location usage description is missing from the app bundle."); return
            }
            guard CLLocationManager.locationServicesEnabled() else { fail(action, "unavailable", "Location Services are off."); return }
            if locationManager == nil { locationManager = CLLocationManager(); locationManager?.delegate = self }
            switch locationManager!.authorizationStatus {
            case .authorized, .authorizedAlways: locationStatus = "authorized"; refresh()
            case .denied, .restricted: locationStatus = "denied"; fail(action, "permissionDenied", "Allow Location access in System Settings.")
            default: locationManager!.requestWhenInUseAuthorization()
            }
        case "openSettings": NSWorkspace.shared.open(settingsURL)
        default: super.invoke(action, argument)
        }
    }

    private func attachNetworkNotifications() {
        var context = SCDynamicStoreContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        guard let store = SCDynamicStoreCreate(nil, "local.pill.wifi" as CFString, { _, _, info in
            guard let info = info else { return }
            Unmanaged<WifiIntegration>.fromOpaque(info).takeUnretainedValue().refresh()
        }, &context) else { fail("subscribe", "unavailable", "Network change notifications are unavailable."); return }
        let source = SCDynamicStoreCreateRunLoopSource(nil, store, 0)
        guard let source = source,
              SCDynamicStoreSetNotificationKeys(store, nil, ["State:/Network/Global/IPv4", "State:/Network/Interface/.*/IPv4", "State:/Network/Interface/.*/Link", "State:/Network/Interface/.*/AirPort"] as CFArray) else {
            fail("subscribe", "unavailable", "Network change notifications could not be registered."); return
        }
        dynamicStore = store; dynamicSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        precondition(Thread.isMainThread)
        switch manager.authorizationStatus {
        case .authorized, .authorizedAlways: locationStatus = "authorized"
        case .denied, .restricted: locationStatus = "denied"
        default: locationStatus = "notDetermined"
        }
        refresh()
    }

    override func stop() {
        precondition(Thread.isMainThread)
        locationManager?.delegate = nil
        locationManager = nil
        if let source = dynamicSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes); CFRunLoopSourceInvalidate(source) }
        dynamicSource = nil; dynamicStore = nil
        super.stop()
    }
}
