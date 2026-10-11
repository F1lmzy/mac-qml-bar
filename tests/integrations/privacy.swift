import Foundation

// Policy-only fixtures. These deliberately do not instantiate Location,
// CoreBluetooth, IOBluetooth, Accessibility or subprocess APIs.
func runPrivacyTests() throws {
    func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw IntegrationFailure("testFailure", message) }
    }
    try require(BluetoothIntegration.authorizationNameForTest(.notDetermined) == "notDetermined", "Bluetooth must remain gated before consent")
    try require(BluetoothIntegration.authorizationNameForTest(.denied) == "denied", "denied Bluetooth must be explicit")
    try require(MenuIntegration.menuItemEnabledForTest(attributeAvailable: false, enabled: false) == false,
                "unknown AX enabled state must not permit activation")
    try require(MenuIntegration.menuItemEnabledForTest(attributeAvailable: true, enabled: true),
                "enabled AX state is actionable")
    try require(!DesktopIntegration.requiresConfirmationForTest("openSettings"), "settings navigation is non-destructive")
    for action in ["lock", "sleep", "restart", "shutDown"] {
        try require(DesktopIntegration.requiresConfirmationForTest(action), "power action requires explicit confirmation")
    }
    try require(WifiIntegration.mayReadSSIDForTest(permission: "authorized"), "SSID requires explicit location grant")
    try require(!WifiIntegration.mayReadSSIDForTest(permission: "notDetermined"), "SSID is hidden before consent")
    try require(!WifiIntegration.mayReadSSIDForTest(permission: "denied"), "SSID remains hidden after denial")
}
