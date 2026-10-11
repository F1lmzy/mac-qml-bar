import QtQuick
import QtTest
import "../qml"
import "../qml/ricelin/Singletons"

TestCase {
    name: "PillSystemIntegrations"
    when: windowShown
    visible: true
    width: 900
    height: 600

    QtObject {
        id: system
        property bool testBackend: true
        property var brightness: ({available: true, known: true, canSet: true, value: 0.6, displayId: "display-a"})
        property var display: ({available: true, nightShiftKnown: true, nightShiftEnabled: false, canSetNightShift: true, canShade: false})
        property var battery: ({available: true, known: true, charge: 0.8, charging: false})
        property var wifi: ({available: true, permission: "notDetermined", ssidKnown: false, canRequestPermission: true})
        property var bluetooth: ({available: false, permission: "notDetermined", devices: []})
        property var spotify: ({available: false, known: false})
        property var desktop: ({available: true})
        property var menus: ({available: false, permission: "notDetermined", items: [], frontPid: 10})
        property var weather: ({available: false})
        property var theme: ({available: true})
        property var outputDevices: ({available: false, devices: []})
        property var windowManager: ({available: true, canSwitch: true, focusedWorkspace: "web", workspaces: [
            {id: "1", visible: false, windowCount: 0}, {id: "web", visible: true, windowCount: 2}
        ]})
        property var calls: []
        signal stateChanged()
        signal errorOccurred(string domain, string operation, string code, string message)
        function invoke(domain, action, argument) { calls = calls.concat([{domain: domain, action: action, argument: argument}]) }
    }
    QtObject {
        id: audio
        property bool available: true
        property string outputDeviceId: "out-1"
        property bool volumeKnown: true
        property real volume: 0.4
        property bool muteKnown: true
        property bool muted: false
        property bool canSetVolume: true
        property bool canMute: true
        property string lastError: ""
        property bool testBackend: true
        signal stateChanged()
        signal errorOccurred(string operation, string code, string message)
        function setVolume(v) {}
        function setMuted(v) {}
    }

    Pill { id: pill; audioService: audio; systemService: system }
    function init() { system.calls = []; pill.dismiss(); system.brightness = ({available: true, known: true, canSet: true, value: 0.6, displayId: "display-a"}) }
    function test_brightnessRequiresCapabilityAndPinsDisplay() {
        pill.open(); tryCompare(pill, "width", pill.mixerSize.width)
        const mixer = findChild(pill, "mixerSurface")
        const fader = findChild(pill, "brightnessFader")
        verify(fader.enabled)
        tryCompare(pill, "height", pill.mixerSize.height)
        tryCompare(mixer, "opacity", 1)
        mousePress(fader, fader.width / 2, fader.height / 2)
        verify(fader.pressed)
        const beforeMove = system.calls.length
        mouseMove(fader, fader.width / 2, fader.height / 3)
        verify(system.calls.length > beforeMove)
        const beforeSwitch = system.calls.length
        compare(system.calls[0].domain, "brightness")
        compare(system.calls[0].argument.displayId, "display-a")
        system.brightness = ({available: true, known: true, canSet: true, value: 0.2, displayId: "display-b"})
        system.stateChanged()
        mouseMove(fader, fader.width / 2, fader.height / 4)
        compare(system.calls.length, beforeSwitch)
        mouseRelease(fader, fader.width / 2, fader.height / 4)
        fader.step(1) // Keyboard starts a fresh action on the current display.
        compare(system.calls.length, beforeSwitch + 1)
        compare(system.calls[system.calls.length - 1].argument.displayId, "display-b")
        system.brightness = ({available: true, known: true, canSet: false, value: 0.2, displayId: "display-b"})
        system.stateChanged()
        verify(!fader.enabled)
    }
    function test_workspaceRowsAreLiveAndActionsValidatedByService() {
        pill.hovered = true
        tryCompare(pill, "height", pill.hoverH)
        tryCompare(pill, "width", pill.hoverSize.width)
        tryCompare(findChild(pill, "hoverContent"), "opacity", 1)
        const workspaces = findChild(pill, "workspaces")
        verify(workspaces !== null)
        compare(workspaces.rows.length, 2)
        const dot = findChild(workspaces, "workspaceDot_web")
        verify(dot !== null)
        mouseClick(dot)
        compare(system.calls.length, 1)
        compare(system.calls[0].action, "switchWorkspace")
        compare(system.calls[0].argument, "web")
    }
    function test_externalWorkspaceChangeUpdatesHighlightImmediately() {
        pill.hovered = true
        tryCompare(pill, "width", pill.hoverSize.width)
        const workspaces = findChild(pill, "workspaces")
        const dot = findChild(workspaces, "workspaceDot_web")
        verify(dot !== null)
        const previous = system.windowManager
        system.windowManager = Object.assign({}, previous, {focusedWorkspace: "web"})
        system.stateChanged()
        compare(workspaces.focusedWorkspace, "web")
        verify(dot.focused)
        compare(dot.color, Theme.vermLit)
        compare(system.calls.length, 0) // Observation must not write back.
        system.windowManager = previous
        system.stateChanged()
    }
    function test_systemPanelRequiresConfirmationForPowerAndMenuActions() {
        pill.openSystem(); tryCompare(pill, "height", pill.systemSize.height)
        const panel = findChild(pill, "systemPanel")
        panel.confirm("desktop", "restart", ({confirmed: true}), "Confirm restart?")
        compare(system.calls.length, 0)
        mouseClick(findChild(panel, "confirmSystemAction"))
        compare(system.calls.length, 1)
        compare(system.calls[0].action, "restart")
        panel.confirm("menus", "press", ({index: 2, title: "Quit", pid: 10, confirmed: true}), "Activate Quit?")
        mouseClick(findChild(panel, "cancelSystemAction"))
        compare(system.calls.length, 1)
    }
    function test_permissionRequestIsOnlyExplicitAction() {
        pill.openSystem(); tryCompare(pill, "height", pill.systemSize.height)
        compare(system.calls.length, 0)
        const button = findChild(pill, "wifiPermissionButton")
        verify(button !== null && button.visible)
        mouseClick(button)
        compare(system.calls.length, 1)
        compare(system.calls[0].domain, "wifi")
    }
    function test_helperCapabilitiesAndCloseCancelConfirmation() {
        pill.openSystem(); tryCompare(pill, "height", pill.systemSize.height)
        const panel = findChild(pill, "systemPanel")
        system.theme = ({available: false, canNext: false, canResyncWallpaper: false})
        system.stateChanged()
        verify(!findChild(panel, "nextThemeButton").enabled)
        verify(!findChild(panel, "wallpaperButton").enabled)
        panel.confirm("theme", "next", null, "Run theme helper?")
        panel.performConfirmed()
        compare(system.calls.length, 1)
        verify(system.calls[0].argument.confirmed === true)
        panel.confirm("desktop", "restart", {confirmed: true}, "Restart?")
        pill.dismiss()
        compare(panel.pendingAction, "")
    }
    function test_micAndLinuxControlsRemainDisabled() {
        pill.open(); tryCompare(pill, "height", pill.mixerSize.height)
        verify(!findChild(pill, "micFader").enabled)
        verify(!findChild(pill, "vibranceFader").enabled)
        verify(!findChild(pill, "dndChip").enabled)
        verify(!findChild(pill, "awakeChip").enabled)
    }
}
