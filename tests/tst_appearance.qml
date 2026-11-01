import QtQuick
import QtTest
import "../qml/ricelin"

TestCase {
    name: "PillAppearance"
    when: windowShown
    visible: true
    width: 900; height: 700
    QtObject {
        id: system
        property bool testBackend: true
        property var display: ({})
        property var theme: ({})
        property var calls: []
        signal stateChanged()
        signal errorOccurred(string domain, string operation, string code, string message)
        function invoke(domain, action, argument) { calls = calls.concat([{domain: domain, action: action, argument: argument}]) }
    }
    SignalSpy { id: closeSpy; target: panel; signalName: "requestClose" }
    Item {
        id: holder
        // Matches Pill.appearanceSize so the square-card geometry assertion below
        // guards the shipped surface, not a roomier test container.
        x: 20; y: 20; width: 420; height: 420
        Appearance { id: panel; anchors.fill: parent; systemService: system; open: false; morphCloseness: 1 }
    }
    function fixtureThemes() {
        return [
            {slug: "fixture", name: "Fixture", background: "#1e1e2e", foreground: "#cdd6f4", accent: "#cba6f7", swatches: "#cba6f7,#f38ba8,#a6e3a1,#f9e2af,#89b4fa,#94e2d5"},
            {slug: "other", name: "Other theme", background: "#282828", foreground: "#ebdbb2", accent: "#d79921", swatches: "#d79921,#cc241d,#98971a,#458588,#b16286,#689d6a"},
            {slug: "third", name: "Third", background: "", foreground: "", accent: "", swatches: ""},
            {slug: "fourth", name: "Fourth", background: "#111c18", foreground: "#c1c497", accent: "#509475", swatches: "#509475,#ff5345"}
        ]
    }
    function init() {
        panel.open = false
        closeSpy.clear()
        system.calls = []
        system.theme = {available: true, name: "Fixture", slug: "fixture", variant: "dark", canSelect: true,
            canNext: true, busy: false, catalogLoading: false, themes: fixtureThemes(), lastError: ""}
    }
    function openPanel() {
        panel.open = true
        tryCompare(panel, "opacity", 1)
        // Grid delegates are positioned on the first frame after the surface
        // opens; without this a click can land before a card has a position,
        // which made the mouse tests flaky against the real surface size.
        waitForRendering(panel)
        compare(system.calls.length, 1)
        compare(system.calls[0].action, "catalog")
        system.calls = []
        return panel
    }

    function test_gridCreatesOneCardPerThemeAndFallbackPalette() {
        const view = openPanel()
        for (const row of fixtureThemes()) verify(findChild(view, "themeChoice_" + row.slug) !== null)
        compare(findChild(view, "themeChoice_fixture").current, true)
        compare(view.themeColors(fixtureThemes()[0]).length, 6)
        verify(findChild(view, "themeDot_fixture_5") !== null)
        verify(findChild(view, "themeDot_fixture_6") === null)
        compare(view.themeColors(fixtureThemes()[2]).length, 5)
        verify(findChild(view, "themeDot_third_4") !== null)
        verify(findChild(view, "themeDot_third_5") === null)
        verify(String(findChild(view, "themeChoice_third").cardFill).length > 0)
    }
    function test_cardsAreSquareAndTwoRowsFitTheContent() {
        const view = openPanel()
        const first = findChild(view, "themeChoice_fixture")
        const second = findChild(view, "themeChoice_other")
        verify(first !== null && second !== null)
        verify(first.width > 0)
        compare(first.height, first.width, "cards are square")
        compare(second.width, first.width, "columns are uniform")
        const grid = first.parent
        const content = grid.parent
        compare(grid.height, 2 * first.width + content.gap, "two rows plus one gap")
        // The host sizes the surface so the grid fits without dead space.
        verify(grid.height <= content.height + 1, "grid fits the content area")
    }
    function test_arrowSelectionMovesByColumnAndRowAndClamps() {
        const view = openPanel()
        compare(view.focusIndex, 0)
        view.moveSelection(1, 0)
        compare(view.focusIndex, 1)
        view.moveSelection(0, 1)
        compare(view.focusIndex, 3)
        view.moveSelection(1, 0)
        compare(view.focusIndex, 3)
        view.moveSelection(0, -1)
        compare(view.focusIndex, 0)
        view.moveSelection(-1, 0)
        compare(view.focusIndex, 0)
    }
    function test_enterAppliesFocusedThemeImmediately() {
        const view = openPanel()
        view.moveSelection(1, 0)
        view.activateFocused()
        compare(system.calls.length, 1)
        compare(system.calls[0].domain, "theme")
        compare(system.calls[0].action, "select")
        compare(system.calls[0].argument.slug, "other")
        verify(system.calls[0].argument.confirmed)
        compare(view.pendingAction, "")
    }
    function test_mouseSelectionStillRequiresApply() {
        const view = openPanel()
        const choice = findChild(view, "themeChoice_other")
        mouseClick(choice)
        compare(view.focusIndex, 1)
        compare(view.pendingAction, "")
        compare(system.calls.length, 0)
        mouseClick(choice)
        compare(view.pendingAction, "select")
        compare(system.calls.length, 0)
        // The Apply row is only laid out once a pending action exists, so the
        // click needs a polish pass before it can land.
        verify(waitForPolish(view))
        mouseClick(findChild(view, "appearanceApply"))
        compare(system.calls.length, 1)
        compare(system.calls[0].argument.slug, "other")
        verify(system.calls[0].argument.confirmed)
    }
    function test_currentRingAndBusyState() {
        const view = openPanel()
        compare(findChild(view, "themeChoice_fixture").current, true)
        system.theme = Object.assign({}, system.theme, {busy: true})
        verify(!findChild(view, "themeChoice_other").enabled)
        verify(!findChild(view, "appearanceApply").enabled)
    }
    function test_emptyAndUnavailableCatalogAreHonest() {
        const view = openPanel()
        system.theme = {available: false, themes: [], canNext: false, catalogLoading: false, catalogError: ""}
        verify(findChild(view, "appearanceEmptyThemes").visible)
        verify(!findChild(view, "appearanceNextTheme").enabled)
        system.theme = Object.assign({}, system.theme, {catalogError: "Catalog unavailable"})
        compare(findChild(view, "appearanceEmptyThemes").text, "Catalog unavailable")
    }
    function test_escapeCancelsPendingBeforeClosing() {
        const view = openPanel()
        view.confirm("select", {slug: "other"}, "Apply Other theme?")
        view.handleEscape()
        compare(view.pendingAction, "")
        compare(view.open, true)
        view.handleEscape()
        compare(view.open, true)
        compare(closeSpy.count, 1)
        compare(system.calls.length, 0)
    }
    function test_externalThemeChangeCancelsPendingAndRefreshButton() {
        const view = openPanel()
        view.confirm("select", {slug: "other"}, "Apply Other theme?")
        system.theme = Object.assign({}, system.theme, {slug: "other"})
        compare(view.pendingAction, "")
        mouseClick(findChild(view, "appearanceRefresh"))
        compare(system.calls.length, 1)
        compare(system.calls[0].action, "catalog")
    }
}
