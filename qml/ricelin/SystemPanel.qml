import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "Singletons"

PillSurface {
    id: panel
    objectName: "systemPanel"
    mTop: 12; mLeft: 14; mRight: 14; mBottom: 12
    property real s: 1
    property var systemService: null
    property string pendingDomain: ""
    property string pendingAction: ""
    property var pendingArgument: null
    property string pendingLabel: ""
    property string pendingMenuFingerprint: ""
    signal requestBack()
    function clearPending() { pendingDomain = ""; pendingAction = ""; pendingArgument = null; pendingLabel = ""; pendingMenuFingerprint = "" }
    onActiveChanged: if (!active) clearPending()
    component PanelButton: Button {
        id: actionButton
        implicitWidth: Math.max(28 * panel.s, implicitContentWidth + 18 * panel.s)
        implicitHeight: 26 * panel.s
        background: Rectangle {
            radius: 6 * panel.s
            color: actionButton.hovered ? Theme.border : Theme.frameBg
            border.width: 1
            border.color: actionButton.activeFocus ? Theme.onGlow : Theme.border
            opacity: actionButton.enabled ? 1 : 0.35
        }
        font.family: Theme.font
        font.pixelSize: 10 * panel.s
        contentItem: Text { textFormat: Text.PlainText;
            text: actionButton.text; font: actionButton.font
            color: actionButton.enabled ? Theme.cream : Theme.faint
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
        }
        palette.button: Theme.frameBg
        palette.buttonText: Theme.cream
    }

    function state(domain) { return systemService && systemService[domain] && typeof systemService[domain] === "object" ? systemService[domain] : ({}) }
    function act(domain, action, argument) { if (systemService) systemService.invoke(domain, action, argument === undefined ? null : argument) }
    function confirm(domain, action, argument, label) {
        pendingDomain = domain; pendingAction = action; pendingArgument = argument; pendingLabel = label
        pendingMenuFingerprint = domain === "menus" ? String(state("menus").frontPid) + ":" + JSON.stringify(state("menus").items || []) : ""
    }
    function performConfirmed() {
        if (pendingAction.length) {
            const argument = Object.assign({}, pendingArgument || {}, {confirmed: true})
            act(pendingDomain, pendingAction, argument)
        }
        pendingDomain = ""; pendingAction = ""; pendingArgument = null; pendingLabel = ""; pendingMenuFingerprint = ""
    }

    Connections {
        target: panel.systemService
        enabled: panel.systemService !== null
        function onStateChanged() {
            if (panel.pendingDomain === "menus") {
                const current = String(panel.state("menus").frontPid) + ":" + JSON.stringify(panel.state("menus").items || [])
                if (current !== panel.pendingMenuFingerprint) {
                    panel.pendingDomain = ""; panel.pendingAction = ""; panel.pendingArgument = null; panel.pendingLabel = ""; panel.pendingMenuFingerprint = ""
                }
            }
        }
    }
    Item {
        anchors.top: parent.top; anchors.left: parent.left; anchors.right: parent.right
        height: 28 * panel.s
        Text { textFormat: Text.PlainText; anchors.verticalCenter: parent.verticalCenter; text: "SYSTEM"; color: Theme.cream; font.family: Theme.font; font.pixelSize: 11 * panel.s; font.weight: Font.DemiBold; font.letterSpacing: 1.2 * panel.s }
        PanelButton { anchors.right: closeButton.left; anchors.rightMargin: 5 * panel.s; anchors.verticalCenter: parent.verticalCenter; text: "Back"; onClicked: panel.requestBack() }
        PanelButton { id: closeButton; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; text: "×"; onClicked: panel.requestClose() }
    }
    Rectangle { id: divider; anchors.top: parent.top; anchors.topMargin: 33 * panel.s; width: parent.width; height: 1; color: Theme.hair }
    ScrollView {
        anchors.top: divider.bottom; anchors.topMargin: 5 * panel.s; anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: confirmBar.top
        clip: true
        contentWidth: availableWidth
        ScrollBar.vertical.policy: ScrollBar.AlwaysOn
        Column {
            width: parent.width
            spacing: 5 * panel.s
            Text { textFormat: Text.PlainText; width: parent.width; wrapMode: Text.Wrap; color: Theme.faint; font.family: Theme.font; font.pixelSize: 8 * panel.s
                text: panel.systemService === null ? "Native system services unavailable." : (panel.systemService.testBackend ? "TEST FIXTURE · no hardware access" : "Live macOS services. Actions run only when requested.") }
            Repeater {
                model: ["brightness", "display", "battery", "wifi", "bluetooth", "spotify", "desktop", "menus", "weather", "theme", "outputDevices", "windowManager"]
                delegate: Column {
                    required property string modelData
                    width: parent.width; spacing: 2 * panel.s
                    readonly property var serviceState: panel.state(modelData)
                    Rectangle { width: parent.width; height: 1; color: Theme.hair }
                    RowLayout {
                        width: parent.width
                        Text { textFormat: Text.PlainText; Layout.fillWidth: true; text: modelData.toUpperCase() + " · " + (serviceState.available === true ? "AVAILABLE" : "UNAVAILABLE"); color: serviceState.available ? Theme.cream : Theme.faint; font.family: Theme.font; font.pixelSize: 9 * panel.s; font.weight: Font.DemiBold }
                        Text { textFormat: Text.PlainText; text: String(serviceState.lastError || ""); color: Theme.vermLit; font.family: Theme.font; font.pixelSize: 8 * panel.s; elide: Text.ElideRight; Layout.maximumWidth: parent.width * 0.48 }
                    }
                    Text { textFormat: Text.PlainText; visible: modelData === "wifi" && serviceState.ssidKnown === true; text: "Network: " + String(serviceState.ssid); color: Theme.subtle; font.family: Theme.font; font.pixelSize: 8 * panel.s }
                    Text { textFormat: Text.PlainText; visible: modelData === "battery" && serviceState.known === true; text: Math.round(Number(serviceState.charge) * 100) + "%" + (serviceState.charging ? " · charging" : ""); color: Theme.subtle; font.family: Theme.font; font.pixelSize: 8 * panel.s }
                    Text { textFormat: Text.PlainText; visible: modelData === "desktop" && serviceState.frontAppKnown === true; text: String(serviceState.frontApp); color: Theme.subtle; font.family: Theme.font; font.pixelSize: 9 * panel.s }
                    Text { textFormat: Text.PlainText; visible: modelData === "wifi" && Boolean(serviceState.ipv4); text: "IP " + String(serviceState.ipv4 || "") + " · router " + String(serviceState.router || ""); color: Theme.subtle; font.family: Theme.font; font.pixelSize: 8 * panel.s }
                    Text { textFormat: Text.PlainText; visible: modelData === "theme" && Boolean(serviceState.name); text: String(serviceState.name || ""); color: Theme.subtle; font.family: Theme.font; font.pixelSize: 9 * panel.s }
                    Text { textFormat: Text.PlainText; visible: modelData === "spotify" && serviceState.known === true; text: String(serviceState.title || "") + " · " + String(serviceState.artist || ""); color: Theme.subtle; font.family: Theme.font; font.pixelSize: 8 * panel.s }
                    Row {
                        spacing: 4 * panel.s
                        visible: modelData === "wifi" || modelData === "bluetooth" || modelData === "spotify" || modelData === "menus" || modelData === "desktop"
                        PanelButton { visible: modelData === "wifi" && serviceState.canRequestPermission === true && serviceState.permission !== "authorized"; objectName: modelData === "wifi" ? "wifiPermissionButton" : ""; text: "Allow location for SSID"; onClicked: panel.act("wifi", "requestPermission") }
                        PanelButton { visible: modelData === "bluetooth" && serviceState.canRequestPermission === true && serviceState.permission !== "authorized"; objectName: modelData === "bluetooth" ? "bluetoothPermissionButton" : ""; text: "Allow Bluetooth"; onClicked: panel.act("bluetooth", "requestPermission") }
                        PanelButton { visible: modelData === "menus" && serviceState.canRequestPermission === true && serviceState.permission !== "authorized"; objectName: modelData === "menus" ? "accessibilityPermissionButton" : ""; text: "Allow Accessibility"; onClicked: panel.act("menus", "requestPermission") }
                        PanelButton { visible: modelData === "spotify" && serviceState.canRequestPermission === true && serviceState.permission !== "authorized"; text: "Allow Spotify Automation"; onClicked: panel.act("spotify", "requestPermission") }
                        PanelButton { visible: modelData === "spotify"; text: "Refresh Spotify"; onClicked: panel.act("spotify", "refresh") }
                        PanelButton { visible: modelData === "wifi" || modelData === "bluetooth"; text: "Settings"; onClicked: panel.act(modelData, "openSettings") }
                        PanelButton { visible: modelData === "desktop"; text: "System Settings"; onClicked: panel.act("desktop", "openSettings") }
                    }
                    Row {
                        spacing: 4 * panel.s
                        visible: modelData === "spotify" && serviceState.available === true
                        PanelButton { text: "Previous"; enabled: serviceState.canControl === true; onClicked: panel.act("spotify", "previous") }
                        PanelButton { text: serviceState.playing ? "Pause" : "Play"; enabled: serviceState.canControl === true; onClicked: panel.act("spotify", "playPause") }
                        PanelButton { text: "Next"; enabled: serviceState.canControl === true; onClicked: panel.act("spotify", "next") }
                    }
                    Row {
                        spacing: 4 * panel.s
                        visible: modelData === "desktop"
                        Repeater {
                            model: ["lock", "sleep", "restart", "shutDown"]
                            delegate: PanelButton { required property string modelData; text: modelData; enabled: panel.state("desktop")[({lock: "canLock", sleep: "canSleep", restart: "canRestart", shutDown: "canShutDown"})[modelData]] === true; onClicked: panel.confirm("desktop", modelData, {confirmed: true}, "Confirm " + modelData + "?") }
                        }
                    }
                    Row {
                        spacing: 4 * panel.s
                        visible: modelData === "display"
                        PanelButton { text: "Night Shift"; enabled: serviceState.nightShiftKnown === true && serviceState.canSetNightShift === true; onClicked: panel.act("display", "setNightShift", !serviceState.nightShiftEnabled) }
                        PanelButton { text: "Restore shade"; enabled: serviceState.canShade === true && Number(serviceState.shade || 0) > 0; onClicked: panel.act("display", "setShade", 0) }
                    }
                    Row {
                        visible: modelData === "display" && serviceState.canShade === true
                        spacing: 5 * panel.s
                        Slider { id: shadeSlider; objectName: "shadeSlider"; from: 0; to: 1; value: Number(serviceState.shade || 0); width: 190 * panel.s }
                        PanelButton { text: "Apply display shade"; onClicked: panel.act("display", "setShade", shadeSlider.value) }
                    }
                    Text { textFormat: Text.PlainText; visible: modelData === "display"; text: "Shade changes display colors. Disable other gamma filters first; Pill restores only its own unchanged transfer table."; color: Theme.faint; wrapMode: Text.Wrap; width: parent.width; font.family: Theme.font; font.pixelSize: 8 * panel.s }
                    Text { textFormat: Text.PlainText; visible: modelData === "weather"; text: "Weather provider wttr.in receives your network IP. Enable only if you want this request."; color: Theme.faint; wrapMode: Text.Wrap; width: parent.width; font.family: Theme.font; font.pixelSize: 8 * panel.s }
                    Text { textFormat: Text.PlainText; visible: modelData === "weather" && serviceState.known === true; text: String(serviceState.temperatureC || "") + "°C · " + String(serviceState.description || ""); color: Theme.cream; font.family: Theme.font; font.pixelSize: 10 * panel.s }
                    PanelButton { visible: modelData === "weather"; text: serviceState.enabled ? "Refresh weather" : "Enable wttr.in weather"; onClicked: panel.act("weather", "refresh") }
                    PanelButton { visible: modelData === "weather" && serviceState.enabled === true; text: "Disable weather"; onClicked: panel.act("weather", "enable", false) }
                    PanelButton { visible: modelData === "theme"; enabled: serviceState.canNext === true; objectName: modelData === "theme" ? "nextThemeButton" : ""; text: "Next theme"; onClicked: panel.confirm("theme", "next", null, "Run the configured theme action?") }
                    PanelButton { visible: modelData === "theme"; enabled: serviceState.canResyncWallpaper === true; objectName: modelData === "theme" ? "wallpaperButton" : ""; text: "Resync wallpaper"; onClicked: panel.confirm("theme", "resyncWallpaper", null, "Change desktop wallpaper settings?") }
                    Repeater {
                        model: modelData === "bluetooth" && serviceState.devices ? serviceState.devices : []
                        delegate: PanelButton { required property var modelData; text: String(modelData.name || modelData.id); onClicked: panel.act("bluetooth", modelData.connected ? "disconnect" : "connect", {id: String(modelData.id)}) }
                    }
                    Repeater {
                        model: modelData === "outputDevices" && serviceState.devices ? serviceState.devices : []
                        delegate: PanelButton { required property var modelData; text: String(modelData.name || modelData.id) + (modelData.default ? " · default" : ""); enabled: serviceState.canSelect === true; onClicked: panel.act("outputDevices", "select", String(modelData.id)) }
                    }
                    Repeater {
                        model: modelData === "windowManager" && serviceState.workspaces ? serviceState.workspaces : []
                        delegate: PanelButton { required property var modelData; text: String(modelData.id); enabled: serviceState.canSwitch === true; onClicked: panel.act("windowManager", "switchWorkspace", String(modelData.id)) }
                    }
                    Repeater {
                        model: modelData === "windowManager" && serviceState.windows ? serviceState.windows : []
                        delegate: PanelButton { required property var modelData; text: String(modelData.appName || modelData.id); enabled: serviceState.canFocus === true; onClicked: panel.act("windowManager", "focusWindow", String(modelData.id)) }
                    }
                    PanelButton { visible: modelData === "menus" && Boolean(serviceState.breadcrumb) && serviceState.breadcrumb.length > 0; text: "Back"; onClicked: panel.act("menus", "back") }
                    Repeater {
                        model: modelData === "menus" && serviceState.items ? serviceState.items : []
                        delegate: PanelButton {
                            required property var modelData
                            text: String(modelData.title || "")
                            enabled: serviceState.permission === "authorized" && (modelData.hasChildren === true || modelData.enabled === true)
                            onClicked: modelData.hasChildren
                                ? panel.act("menus", "open", {index: Number(modelData.index), pid: Number(serviceState.frontPid)})
                                : panel.confirm("menus", "press", {index: Number(modelData.index), title: String(modelData.title), pid: Number(serviceState.frontPid), confirmed: true}, "Activate menu item: " + String(modelData.title) + "?")
                        }
                    }
                }
            }
        }
    }
    Row {
        id: confirmBar
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        height: visible ? 42 * panel.s : 0
        visible: panel.pendingAction.length > 0
        spacing: 4 * panel.s
        Text { textFormat: Text.PlainText; width: parent.width * 0.55; anchors.verticalCenter: parent.verticalCenter; text: panel.pendingLabel; color: Theme.cream; font.family: Theme.font; font.pixelSize: 9 * panel.s; wrapMode: Text.Wrap }
        PanelButton { objectName: "confirmSystemAction"; text: "Confirm"; anchors.verticalCenter: parent.verticalCenter; onClicked: panel.performConfirmed() }
        PanelButton { objectName: "cancelSystemAction"; text: "Cancel"; anchors.verticalCenter: parent.verticalCenter; onClicked: { panel.pendingAction = ""; panel.pendingArgument = null; panel.pendingDomain = ""; panel.pendingLabel = ""; panel.pendingMenuFingerprint = "" } }
    }
}
