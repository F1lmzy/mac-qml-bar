import QtQuick
import Quickshell

PanelWindow {
    id: panel
    title: "PillSpike"
    screen: Quickshell.screens[0]
    anchors.top: true
    implicitWidth: content.width
    implicitHeight: content.height
    property alias pill: content
    Pill { id: content }
}
