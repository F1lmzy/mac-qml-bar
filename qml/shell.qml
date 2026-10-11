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
    readonly property bool nativeAudioReady: Audio.testBackend && Audio.available && Audio.volumeKnown && Audio.muteKnown
    readonly property bool nativeSystemReady: System.testBackend && System.brightness.known === true && System.windowManager.available === true
    Pill { id: content; audioService: Audio; systemService: System }
}
