import QtQuick
import Quickshell
import Pill.MacOS 1.0
import "ricelin/Singletons"

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
    readonly property bool nativeSystemReady: System.testBackend && System.brightness.known === true && System.windowManager.available === true && Boolean(System.theme.palette) && System.theme.palette.schema === 1
    readonly property bool nativeLauncherReady: Maccer.testBackend && Maccer.ready
    Binding { target: Theme; property: "systemTheme"; value: Maccer.serviceMode ? Maccer.themeState : System.theme }
    Pill { id: content; audioService: Audio; systemService: System; launcherService: Maccer }
}
