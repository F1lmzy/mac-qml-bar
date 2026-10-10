import QtQuick
import Quickshell
import Pill.MacOS 1.0

PanelWindow {
    id: panel
    title: "PillSpike"
    screen: Quickshell.screens[0]
    anchors.top: true
    implicitWidth: content.width
    implicitHeight: content.height
    property alias pill: content
    readonly property bool nativeBridgeReady: Bridge.ready
    Pill { id: content }
}
