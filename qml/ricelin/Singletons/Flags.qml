pragma Singleton
import QtQuick
import Quickshell

Singleton {
    // Dynamic wallpaper branches in upstream Theme are intentionally unreachable.
    // No Dyn service is provided; this subset offers only the fixed palette.
    readonly property string paletteMode: "static"
    readonly property string uiFont: "Helvetica Neue"
    property bool reduceMotion: false
    readonly property real uiScale: 1
    readonly property real pillOpacity: 1
    readonly property bool showGlyphs: true
    readonly property bool clockSeconds: false
    readonly property bool time12h: false
}
