pragma Singleton
import QtQuick
import Quickshell

// mac-themer publishes a validated palette through System.theme.
// The native reader retains the last good palette; these literals are only
// the cold-start fallback when mac-themer has not published one yet.
Singleton {
    property var systemTheme: ({})
    readonly property var palette: systemTheme.palette || ({})
    readonly property bool followsSystem: systemTheme.available === true && palette.schema === 1
    readonly property var tokens: followsSystem ? palette.tokens : ({})
    readonly property var bar: followsSystem ? palette.bar : ({})
    readonly property var ansi: followsSystem ? palette.palette : ({})
    readonly property real backgroundOpacity: followsSystem ? palette.alpha_byte / 255 : 1

    readonly property color onGlow: followsSystem ? tokens.primary : "#ff9a64"
    readonly property color verm: followsSystem ? tokens.primary : "#c0442b"
    readonly property color vermLit: followsSystem ? bar.accent : "#e0563b"
    readonly property color vermDeep: followsSystem ? tokens.primary_container : "#a3371f"
    readonly property color cream: followsSystem ? bar.label : "#e6d6cb"
    readonly property color bright: followsSystem ? tokens.on_surface : "#fff6f0"
    readonly property color dim: followsSystem ? bar.muted : "#8a7d74"
    readonly property color cardTop: followsSystem ? tokens.surface_container_high : "#2e231b"
    readonly property color cardBot: followsSystem ? tokens.surface_container_low : "#221813"
    readonly property color border: followsSystem ? tokens.outline_variant : "#3a2a22"
    readonly property color shadow: Qt.rgba(0, 0, 0, 0.55)
    readonly property color tileBg: followsSystem ? bar.background : "#211711"
    readonly property color subtle: followsSystem ? tokens.on_surface_variant : "#b9a99e"
    readonly property color faint: followsSystem ? tokens.muted : "#6f635b"
    readonly property color iconDim: followsSystem ? bar.icon : "#cdbfb4"
    readonly property color hair: Qt.alpha(cream, 0.13)
    readonly property color hairSoft: Qt.alpha(cream, 0.08)
    readonly property color sheen: Qt.alpha(cream, 0.07)
    readonly property color vermDim: followsSystem ? tokens.outline : "#8a5440"
    readonly property color vermDimDeep: followsSystem ? tokens.outline_variant : "#5a3526"
    readonly property color vermBurn: followsSystem ? tokens.primary_container : "#8a2c14"
    readonly property color tickRest: followsSystem ? tokens.on_surface_variant : "#cbb6a3"
    readonly property color threadBg: Qt.alpha(cream, 0.13)
    readonly property color flameCore: followsSystem ? tokens.primary : "#ffd9c2"
    readonly property color flameGlow: followsSystem ? tokens.primary : "#ff9a64"
    // Canvas consumers require raw #RRGGBB strings, not QML color values.
    readonly property string flameInk: followsSystem ? tokens.primary : "#f0795a"
    readonly property string flameEmber: followsSystem ? tokens.primary_container : "#7e2812"
    readonly property string flameBurn: followsSystem ? tokens.primary_container : "#8a2c14"
    readonly property string flameTip: followsSystem ? tokens.on_primary_container : "#ffb38a"
    readonly property color todayWarm: followsSystem ? tokens.primary : "#ffb38a"
    readonly property color ghost: followsSystem ? tokens.surface_container_highest : "#594636"
    readonly property color frameBg: followsSystem ? bar.item_bg : Qt.alpha(cream, 0.055)
    readonly property color frameBorder: followsSystem ? tokens.outline_variant : Qt.alpha(cream, 0.10)
    readonly property color hoverBg: Qt.alpha(cream, 0.03)
    readonly property color iconBg: Qt.alpha(cream, 0.05)
    readonly property color selectionBg: followsSystem ? ansi.selection_background : verm
    readonly property color selectionText: followsSystem ? ansi.selection_foreground : bright
    readonly property color error: followsSystem ? bar.red : vermLit
    readonly property color success: followsSystem ? bar.green : onGlow
    readonly property color warning: followsSystem ? bar.yellow : onGlow
    readonly property color creamMenu: Qt.alpha(cream, 0.82)
    readonly property real shadowOpacity: 0.5
    /**
     * Snapshot of the system families, not a binding: Qt.fontFamilies() is not
     * notifiable, so a font dropped onto the pill re-registers through
     * refreshFonts() once its FontLoader is ready.
     */
    property var fontFamilies: Qt.fontFamilies()
    function refreshFonts() { fontFamilies = Qt.fontFamilies(); }
    readonly property string font: (Flags.uiFont.length > 0 && fontFamilies.indexOf(Flags.uiFont) >= 0) ? Flags.uiFont : "Inter"
    readonly property string fontJp: fontFamilies.indexOf("Zen Kaku Gothic New") >= 0 ? "Zen Kaku Gothic New" : "Hiragino Sans"

    /**
     * MPRIS trackArtists arrives as a JS array from some players and as a
     * plain string from others (Spotify); calling join on the string throws
     * and kills the whole binding. Handles both, falls back to trackArtist.
     */
    function joinArtists(artists, single) {
        if (artists && typeof artists.join === "function" && artists.length > 0)
            return artists.join(", ");
        if (artists && String(artists).length > 0)
            return String(artists);
        return single ? String(single) : "";
    }
}
