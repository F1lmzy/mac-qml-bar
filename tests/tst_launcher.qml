import QtQuick
import QtTest
import "../qml"

TestCase {
    name: "LauncherInteraction"
    when: windowShown
    visible: true
    width: 900
    height: 600
    QtObject {
        id: service
        property bool ready: true
        property bool searching: false
        property bool busy: false
        property string query: ""
        property string lastError: ""
        property string shortcutError: ""
        property string outputTitle: ""
        property string outputText: ""
        property bool serviceMode: false
        property var themeState: ({})
        property bool providerScoped: false
        property int homeCalls: 0
        property bool deferSearch: false
        property int searchCalls: 0
        property var previewContent: []
        property bool previewLoading: false
        property var detailCalls: []
        function requestDetails(provider, id) { detailCalls = detailCalls.concat([{provider: provider, id: id}]) }
        function clearDetails() { previewContent = []; previewLoading = false }
        property var results: []
        property var activations: []
        property int cancellations: 0
        property var pendingConfirmation: ({})
        property int confirmCalls: 0
        property int cancelConfirmationCalls: 0
        signal stateChanged()
        signal closeRequested()
        signal queryRequested(string text)
        signal toggleRequested()
        signal showRequested()
        function setQuery(text) { searchCalls++; query = text; searching = deferSearch; outputTitle = ""; outputText = ""; pendingConfirmation = ({}) }
        function confirmationFor(provider, id, action) {
            for (let i = 0; i < results.length; i++) {
                if (results[i].provider !== provider || results[i].id !== id) continue
                const actions = results[i].actions || []
                for (let j = 0; j < actions.length; j++)
                    if (actions[j].id === action) return actions[j].confirmation || ""
            }
            return ""
        }
        function activate(provider, id, action) {
            const prompt = confirmationFor(provider, id, action)
            if (prompt) { pendingConfirmation = {provider: provider, id: id, action: action, prompt: prompt}; return }
            activations = activations.concat([{provider: provider, id: id, action: action}])
        }
        function confirmActivation() {
            confirmCalls++
            const pending = pendingConfirmation
            pendingConfirmation = ({})
            if (pending && pending.action)
                activations = activations.concat([{provider: pending.provider, id: pending.id, action: pending.action, confirmed: true}])
        }
        function cancelActivation() { cancelConfirmationCalls++; pendingConfirmation = ({}) }
        function cancel() { cancellations++; busy = false }
        function home() { homeCalls++; providerScoped = false }
        function copyOutput() {}
    }
    Pill { id: pill; launcherService: service }
    SignalSpy { id: presentations; target: pill; signalName: "launcherPresented" }
    function row(id, title) {
        return {id: id, provider: "apps", title: title, subtitle: "/Applications/" + title + ".app",
                iconSource: "", iconText: "", actions: [{id: "open", title: "Open"}, {id: "reveal", title: "Reveal in Finder"}]}
    }
    function menuRow(id, title) {
        return {id: id, provider: "menu", title: title, subtitle: "", iconSource: "", iconText: "\u203A",
                actions: [{id: "open", title: "Open"}]}
    }
    function themeRow(slug, title, background, foreground, accent) {
        return {id: "themes:" + slug, provider: "themes", title: title, subtitle: slug + " \u00b7 dark",
                iconSource: "", iconText: "\u25D0",
                content: [{type: "colorPalette", fallbackText: title + " palette", colors: [
                    {role: "background", value: background},
                    {role: "foreground", value: foreground},
                    {role: "accent", value: accent}]}],
                data: {type: "themeSummary", schemaVersion: 1, slug: slug, variant: "dark"},
                actions: [{id: "apply", title: "Apply theme", confirmation: "Apply " + title + "? Wallpaper unchanged."}]}
    }
    function panel() { return findChild(pill, "launcherSurface") }
    function field() { return findChild(pill, "launcherInput") }
    function init() {
        pill.dismiss()
        tryCompare(pill, "width", pill.collapsedSize.width)
        tryCompare(pill, "height", pill.collapsedSize.height)
        service.results = [row("safari", "Safari"), row("terminal", "Terminal")]
        service.activations = []
        service.lastError = ""
        service.shortcutError = ""
        service.outputTitle = ""
        service.outputText = ""
        service.busy = false
        service.searching = false
        service.cancellations = 0
        service.serviceMode = false
        service.themeState = ({})
        service.providerScoped = false
        service.homeCalls = 0
        service.deferSearch = false
        service.searchCalls = 0
        service.previewContent = []
        service.previewLoading = false
        service.detailCalls = []
        service.pendingConfirmation = ({})
        service.confirmCalls = 0
        service.cancelConfirmationCalls = 0
        panel().previewEnabled = true
        pill.openLauncher()
        tryCompare(pill, "width", pill.launcherSize.width)
        tryCompare(pill, "height", pill.launcherSize.height)
        tryCompare(field(), "activeFocus", true)
    }
    function cleanup() { pill.dismiss() }
    function test_serviceActiveThemeIsReadOnlyInAppearance() {
        service.serviceMode = true
        service.themeState = {available: true, name: "Shared palette", slug: "shared", canSelect: false,
            canNext: false, canResyncWallpaper: false, canSetBackground: false, themes: [], wallpapers: []}
        // Service mode routes the palette button to the launcher's Themes route,
        // but the local surface must still stay read-only if it is shown.
        pill.surface = "appearance"
        const appearance = findChild(pill, "appearanceSurface")
        verify(appearance !== null)
        compare(appearance.themeState.name, "Shared palette")
        compare(findChild(pill, "appearanceNextTheme").enabled, false)
        compare(findChild(pill, "appearanceRefresh").enabled, false)
        appearance.confirm("next", {}, "Must not apply")
        compare(appearance.pendingAction, "")
        service.themeState = {available: true, name: "Changed shared palette", slug: "changed", themes: [], wallpapers: []}
        tryCompare(appearance.themeState, "name", "Changed shared palette")
    }
    function test_servicePreviewSelectionToggleAndPlainFallback() {
        service.serviceMode = true
        let first = row("safari", "Safari")
        let second = row("terminal", "Terminal")
        first.detailsAvailable = true
        second.detailsAvailable = true
        service.results = [first, second]
        tryVerify(() => service.detailCalls.length > 0)
        compare(service.detailCalls[service.detailCalls.length - 1].id, "safari")
        service.previewContent = [{type: "future", fallbackText: "<b>literal future</b>"},
            {type: "colorPalette", colors: [{role: "accent", value: "#89b4fa"}], fallbackText: "Blue"}]
        const preview = findChild(pill, "launcherPreview")
        tryCompare(preview, "visible", true)
        compare(preview.textFor(service.previewContent[0]), "<b>literal future</b>")
        keyClick(Qt.Key_Down)
        tryVerify(() => service.detailCalls[service.detailCalls.length - 1].id === "terminal")
        keyClick(Qt.Key_P, Qt.ControlModifier | Qt.ShiftModifier)
        tryCompare(preview, "visible", false)
        compare(service.previewContent.length, 0)
        keyClick(Qt.Key_Return)
        compare(service.activations[0].id, "terminal") // Details never block actions.
    }
    function test_pendingServiceQueryRetainsPreviewAndBlocksActions() {
        service.serviceMode = true
        let first = row("safari", "Safari")
        let second = row("terminal", "Terminal")
        first.detailsAvailable = true
        second.detailsAvailable = true
        service.results = [first, second]
        panel().select(1)
        service.previewContent = [{type: "text", text: "Owned old preview", fallbackText: "Owned old preview"}]
        const preview = findChild(pill, "launcherPreview")
        tryCompare(preview, "visible", true)
        const height = preview.height
        service.deferSearch = true
        field().text = "new query"
        panel().refreshPreview()
        compare(service.searching, true)
        compare(service.results.length, 2)
        compare(service.previewContent.length, 1)
        compare(preview.visible, true)
        compare(preview.height, height)
        keyClick(Qt.Key_Return)
        keyClick(Qt.Key_Tab)
        keyClick(Qt.Key_K, Qt.ControlModifier)
        compare(service.activations.length, 0)
        compare(panel().actionMode, false)
        // Hiding a preview is still explicit even during a pending search.
        keyClick(Qt.Key_P, Qt.ControlModifier | Qt.ShiftModifier)
        compare(service.previewContent.length, 0)
        compare(preview.visible, false)
    }
    function test_sameClipboardQueryOutcomeRequestsFreshSearch() {
        service.serviceMode = true
        service.providerScoped = true
        field().text = "private"
        const before = service.searchCalls
        service.queryRequested("private")
        compare(service.searchCalls, before + 1)
        compare(service.providerScoped, true)
        compare(field().text, "private")
    }
    function test_backendShortcutPresentsWithoutToggling() {
        service.serviceMode = true
        pill.dismiss()
        presentations.clear()
        compare(pill.surface, "")
        // A backend presentation request opens a hidden or canceled launcher.
        service.showRequested()
        tryCompare(pill, "surface", "launcher")
        compare(pill.expanded, true)
        compare(presentations.count, 1)
        // A repeated request must keep an already-open launcher open, not close it.
        service.showRequested()
        tryCompare(pill, "surface", "launcher")
        compare(pill.expanded, true)
        compare(presentations.count, 2) // Native host gets a refocus request even without expandedChanged.
    }
    function test_geometryAndFocus() {
        compare(pill.expanded, true)
        compare(pill.mode, "launcher")
        compare(pill.launcherSize, Qt.size(480, 380))
        tryCompare(panel(), "opacity", 1)
        compare(field().activeFocus, true)
        compare(field().x, 0) // No decorative kanji or reserved glyph margin.
    }
    function test_keyboardNavigationActivationAndSecondaryAction() {
        keyClick(Qt.Key_Down)
        compare(panel().selectedIndex, 1)
        keyClick(Qt.Key_Return)
        compare(service.activations[0].id, "terminal")
        compare(service.activations[0].action, "open")
        keyClick(Qt.Key_Tab)
        compare(service.activations[1].action, "reveal")
        compare(field().activeFocus, true)
    }
    function test_actionsAndEscapeUnwind() {
        keyClick(Qt.Key_K, Qt.ControlModifier)
        compare(panel().actionMode, true)
        keyClick(Qt.Key_Down)
        keyClick(Qt.Key_Return)
        compare(service.activations[0].action, "reveal")
        keyClick(Qt.Key_Escape)
        compare(panel().actionMode, false)
        compare(pill.expanded, true)
        field().text = "safari"
        keyClick(Qt.Key_Escape)
        compare(field().text, "")
        compare(pill.expanded, true)
        keyClick(Qt.Key_Escape)
        compare(pill.expanded, false)
        verify(service.cancellations > 0)
    }
    function test_unicodeAndProviderPicker() {
        field().text = "日本語 café 🚀"
        compare(service.query, "日本語 café 🚀")
        keyClick(Qt.Key_P, Qt.ControlModifier)
        compare(service.query, ";")
        service.queryRequested("/apps ")
        compare(field().text, "/apps ")
        compare(service.query, "/apps ")
    }
    function test_serviceCloseAndBusyGating() {
        service.busy = true
        keyClick(Qt.Key_Return)
        compare(service.activations.length, 0)
        service.busy = false
        service.searching = true
        keyClick(Qt.Key_Return)
        compare(service.activations.length, 0)
        service.searching = false
        service.closeRequested()
        compare(pill.expanded, false)
    }
    function test_switchToMixerCancelsSearch() {
        pill.open()
        verify(service.cancellations > 0)
        compare(pill.surface, "mixer")
        tryCompare(pill, "height", pill.mixerSize.height)
    }
    function test_outputEscapeReturnsToResults() {
        service.outputTitle = "Command output"
        service.outputText = "<b>literal output</b>"
        compare(panel().outputMode, true)
        keyClick(Qt.Key_Escape)
        compare(panel().outputMode, false)
        compare(pill.expanded, true)
    }
    function test_emptyAndErrorStates() {
        service.results = []
        service.lastError = "Provider failed"
        compare(findChild(pill, "launcherStatus").text, "Provider failed")
        keyClick(Qt.Key_Return)
        compare(service.activations.length, 0)
    }
    function test_escapeFromProviderScopeReturnsHome() {
        service.serviceMode = true
        service.providerScoped = true
        field().text = "safari"
        keyClick(Qt.Key_Escape)
        compare(field().text, "")
        compare(service.homeCalls, 0)
        compare(pill.expanded, true)
        keyClick(Qt.Key_Escape)
        compare(service.homeCalls, 1)
        compare(pill.expanded, true)
    }
    function test_providerPickerUsesHomeInServiceMode() {
        service.serviceMode = true
        keyClick(Qt.Key_P, Qt.ControlModifier)
        compare(service.homeCalls, 1)
        verify(service.query !== ";")
    }
    function test_embeddedProviderPickerStaysSemicolon() {
        keyClick(Qt.Key_P, Qt.ControlModifier)
        compare(service.query, ";")
        compare(service.homeCalls, 0)
    }
    function test_searchDropsProviderMenuAndPrefersApplicationNames() {
        service.results = [menuRow("themes", "Themes"), row("airdrop", "AirDrop"),
                           row("finder", "Finder"), row("findmy", "Find My")]
        field().text = "find"
        tryCompare(panel(), "queryText", "find")
        // The provider row was matched through its long description by the
        // backend; navigation rows must not outrank real application hits.
        compare(panel().results.length, 3)
        compare(panel().results[0].title, "Finder")
        compare(panel().results[1].title, "Find My")
        // Typing a provider name still offers its page.
        field().text = "themes"
        tryCompare(panel(), "queryText", "themes")
        compare(panel().results[0].provider, "menu")
        compare(panel().results[0].id, "themes")
    }
    function test_applicationRowsRankByTitleMatch() {
        service.results = [row("computer", "Computer"), row("terminal", "Terminal"),
                           row("ticket", "Ticket Viewer")]
        field().text = "term"
        tryCompare(panel(), "queryText", "term")
        compare(panel().results[0].title, "Terminal")
        compare(panel().results[1].title, "Computer") // "compuTER" contains the query.
    }
    function test_sharedThemesRenderAsGridCardsWithArrowNavigation() {
        service.serviceMode = true
        service.providerScoped = true
        service.themeState = {available: true, name: "Gruvbox", slug: "gruvbox", themes: [], wallpapers: []}
        service.results = [
            themeRow("catppuccin", "Catppuccin", "#1e1e2e", "#cdd6f4", "#cba6f7"),
            themeRow("gruvbox", "Gruvbox", "#282828", "#ebdbb2", "#fe8019"),
            themeRow("osaka", "Osaka Jade", "#101c18", "#c1c497", "#509475"),
            themeRow("tokyo", "Tokyo Night", "#1a1b26", "#c0caf5", "#7aa2f7"),
            themeRow("nord", "Nord", "#2e3440", "#d8dee9", "#88c0d0")
        ]
        const surface = panel()
        tryCompare(surface, "gridMode", true)
        const grid = findChild(pill, "launcherThemes")
        verify(grid !== null)
        tryCompare(grid, "visible", true)
        compare(findChild(pill, "launcherResults").visible, false)
        compare(grid.count, 5)
        compare(grid.currentIndex, 0)
        // A card is filled from the theme's own background and exposes its
        // palette, exactly like the Appearance grid.
        const gruvbox = findChild(surface, "themeCell_gruvbox")
        verify(gruvbox !== null)
        compare(gruvbox.currentTheme, true)
        compare(String(gruvbox.cardBackground).toLowerCase(), "#282828")
        compare(String(gruvbox.cardForeground).toLowerCase(), "#ebdbb2")
        compare(surface.themeDots(service.results[1]).length, 3)
        // Left/Right move one card; Up/Down move a whole three-column row.
        keyClick(Qt.Key_Right)
        compare(surface.selectedIndex, 1)
        keyClick(Qt.Key_Down)
        compare(surface.selectedIndex, 4)
        keyClick(Qt.Key_Right)
        compare(surface.selectedIndex, 4) // Clamped to the catalog.
        keyClick(Qt.Key_Up)
        compare(surface.selectedIndex, 1)
        // Return stages the service confirmation; nothing is applied yet.
        keyClick(Qt.Key_Return)
        compare(surface.confirming, true)
        compare(service.pendingConfirmation.action, "apply")
        compare(service.activations.length, 0)
        keyClick(Qt.Key_Down) // Moving discards the staged consent.
        compare(surface.confirming, false)
        compare(surface.selectedIndex, 4)
    }
    function test_sharedPaletteButtonOpensThemesProvider() {
        service.serviceMode = true
        service.results = [menuRow("themes", "Themes")]
        service.activations = []
        pill.openAppearance()
        compare(pill.surface, "launcher")
        tryVerify(() => service.activations.length === 1)
        compare(service.activations[0].provider, "menu")
        compare(service.activations[0].id, "themes")
        compare(service.activations[0].action, "open")
        compare(panel().pendingThemes, false)
        // Embedded mode still has its own catalog surface.
        service.serviceMode = false
        service.activations = []
        pill.openAppearance()
        compare(pill.surface, "appearance")
    }
    function confirmedTheme(id, title, prompt) {
        return {id: id, provider: "themes", title: title, subtitle: "", iconSource: "", iconText: "",
                actions: [{id: "apply", title: "Apply", confirmation: prompt}]}
    }
    function test_confirmedThemeApplyStagesCancelsAndConfirmsOnce() {
        service.serviceMode = true
        service.results = [confirmedTheme("themes:catppuccin", "Catppuccin", "Apply Catppuccin? It changes your desktop theme."),
                           confirmedTheme("themes:gruvbox", "Gruvbox", "Apply Gruvbox? It changes your desktop theme.")]
        const surface = panel()
        // Selecting Apply stages the prompt and sends nothing.
        keyClick(Qt.Key_Return)
        compare(service.activations.length, 0)
        compare(service.pendingConfirmation.action, "apply")
        compare(surface.confirming, true)
        compare(findChild(pill, "launcherConfirmationText").text, "Apply Catppuccin? It changes your desktop theme.")
        // The consequences must remain readable, not elided beside the buttons.
        const longPrompt = "Apply \"" + "n".repeat(256) + "\"? This writes theme files, updates app settings and reloads apps. The wallpaper will not change."
        service.pendingConfirmation = {provider: "themes", id: "themes:catppuccin", action: "apply", prompt: longPrompt}
        const promptText = findChild(pill, "launcherConfirmationText")
        tryCompare(promptText, "truncated", false)
        compare(promptText.text, longPrompt)
        verify(findChild(pill, "launcherConfirmation").height >= promptText.implicitHeight + 44 * surface.s)
        service.pendingConfirmation = {provider: "themes", id: "themes:catppuccin", action: "apply", prompt: "Consequence\n".repeat(80)}
        const promptPanel = findChild(pill, "launcherConfirmation")
        const promptScroll = findChild(pill, "launcherConfirmationScroll")
        tryVerify(function() { return promptScroll.contentHeight > promptScroll.height })
        verify(promptPanel.height <= 160 * surface.s)
        compare(service.activations.length, 0)
        // Escape discards consent without sending.
        keyClick(Qt.Key_Escape)
        compare(surface.confirming, false)
        compare(service.activations.length, 0)
        compare(pill.expanded, true)
        // A query change discards consent.
        keyClick(Qt.Key_Return)
        compare(surface.confirming, true)
        field().text = "gruvbox"
        compare(surface.confirming, false)
        compare(service.activations.length, 0)
        // A selection change discards consent.
        field().text = ""
        keyClick(Qt.Key_Return)
        compare(surface.confirming, true)
        keyClick(Qt.Key_Down)
        compare(surface.confirming, false)
        compare(service.activations.length, 0)
        // Explicit confirmation sends exactly one confirmed activation.
        keyClick(Qt.Key_Return)
        compare(surface.confirming, true)
        keyClick(Qt.Key_Return)
        compare(service.activations.length, 1)
        compare(service.activations[0].action, "apply")
        compare(service.activations[0].confirmed, true)
        compare(surface.confirming, false)
    }
}
