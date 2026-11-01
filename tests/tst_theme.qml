import QtQuick
import QtTest
import "../qml"
import "../qml/ricelin/Singletons"

TestCase {
    name: "PillSystemTheme"
    when: windowShown
    visible: true
    width: 900
    height: 600
    Pill { id: pill }
    property var previousTheme
    function init() { previousTheme = Theme.systemTheme; Theme.systemTheme = ({}); pill.dismiss() }
    function cleanup() { Theme.systemTheme = previousTheme }

    function palette(light) {
        return {schema: 1, name: light ? "Light fixture" : "Catppuccin Mocha", alpha_byte: 230,
            tokens: {surface: light ? "#fafafa" : "#1e1e2e", on_surface: light ? "#222222" : "#cdd6f4",
                on_surface_variant: light ? "#444444" : "#9ca2bd", muted: "#6c7086",
                surface_container_low: light ? "#eeeeee" : "#28293a",
                surface_container: light ? "#dddddd" : "#313244",
                surface_container_high: light ? "#cccccc" : "#3a3b4e",
                surface_container_highest: light ? "#bbbbbb" : "#4c4e61",
                outline: "#64687d", outline_variant: "#44465a",
                primary: light ? "#004488" : "#cba6f7", primary_container: light ? "#004488" : "#cba6f7",
                on_primary: light ? "#ffffff" : "#1e1e2e", on_primary_container: light ? "#ffffff" : "#1e1e2e",
                error: "#f38ba8", success: "#a6e3a1", warning: "#f9e2af"},
            palette: {selection_background: "#585b70", selection_foreground: "#cdd6f4"},
            bar: {background: light ? "#fafafa" : "#1e1e2e", item_bg: light ? "#dddddd" : "#313244",
                accent: light ? "#004488" : "#cba6f7", label: light ? "#222222" : "#cdd6f4",
                icon: light ? "#222222" : "#cdd6f4", muted: "#6c7086",
                red: "#f38ba8", green: "#a6e3a1", yellow: "#f9e2af"}}
    }
    function apply(light) { Theme.systemTheme = {available: true, palette: palette(light)} }
    function test_coldMissingPaletteUsesFallback() {
        compare(Theme.cream, "#e6d6cb")
        compare(Theme.cardTop, "#2e231b")
        compare(Theme.vermLit, "#e0563b")
        Theme.systemTheme = {available: true, name: "Old fixture without palette"}
        compare(Theme.cream, "#e6d6cb")
    }
    function test_macThemerSemanticColorsAreUsed() {
        apply(false)
        compare(Theme.cream, "#cdd6f4")
        compare(Theme.bright, "#cdd6f4")
        compare(Theme.vermLit, "#cba6f7")
        compare(Theme.tileBg, "#1e1e2e")
        compare(Theme.cardTop, "#3a3b4e")
        compare(Theme.cardBot, "#28293a")
        compare(Theme.border, "#44465a")
        compare(Theme.dim, "#6c7086")
        compare(Theme.frameBg, "#313244")
        compare(Theme.selectionBg, "#585b70")
        compare(Theme.selectionText, "#cdd6f4")
        compare(Theme.error, "#f38ba8")
        compare(Theme.backgroundOpacity, 230 / 255)
        compare(findChild(pill, "restClock").color, Theme.cream)
        compare(pill.restW, 160)
        compare(pill.restH, 32)
    }
    function test_liveUpdateChangesExistingItemsWithoutRelayout() {
        apply(false)
        const clock = findChild(pill, "restClock")
        compare(clock.color, "#cdd6f4")
        apply(true)
        tryCompare(clock, "color", "#222222")
        compare(Theme.vermLit, "#004488")
        compare(Theme.tileBg, "#fafafa")
        compare(Theme.cardTop, "#cccccc")
        compare(Theme.frameBg, "#dddddd")
        compare(Theme.hoverBg, Qt.alpha(Theme.cream, 0.03))
        compare(pill.restW, 160)
        compare(pill.restH, 32)
    }
    function test_lastValidPaletteWithReadErrorStillDisplays() {
        Theme.systemTheme = {available: true, palette: palette(false), lastErrorCode: "invalidResponse"}
        compare(Theme.cream, "#cdd6f4")
        compare(Theme.vermLit, "#cba6f7")
    }
    function test_allSurfacesUseThemeBindings() {
        apply(false)
        pill.open()
        tryCompare(pill, "height", pill.mixerH)
        pill.openSystem()
        tryCompare(pill, "height", pill.systemH)
        pill.openLauncher()
        tryCompare(pill, "height", pill.launcherSize.height)
        const input = findChild(pill, "launcherInput")
        verify(input !== null)
        compare(input.color, Theme.cream)
        compare(input.selectionColor, Theme.selectionBg)
        compare(input.selectedTextColor, Theme.selectionText)
        apply(true)
        tryCompare(input, "color", "#222222")
        pill.dismiss()
    }
}
