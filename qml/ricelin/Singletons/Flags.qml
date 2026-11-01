pragma Singleton
import QtQuick
import Quickshell

Singleton {
    // The active mac-themer palette is delivered by the native System service.
    readonly property string paletteMode: "system"
    readonly property string uiFont: "Helvetica Neue"
    property bool reduceMotion: false
    readonly property real uiScale: 1
    readonly property real pillOpacity: 1
    readonly property bool showGlyphs: true
    readonly property bool clockSeconds: false
    readonly property bool time12h: false
}
