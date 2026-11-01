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
        pill.openAppearance()
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
        keyClick(Qt.Key_P, Qt.MetaModifier | Qt.ShiftModifier)
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
        keyClick(Qt.Key_K, Qt.MetaModifier)
        compare(service.activations.length, 0)
        compare(panel().actionMode, false)
        // Hiding a preview is still explicit even during a pending search.
        keyClick(Qt.Key_P, Qt.MetaModifier | Qt.ShiftModifier)
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
        keyClick(Qt.Key_K, Qt.MetaModifier)
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
        keyClick(Qt.Key_P, Qt.MetaModifier)
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
        keyClick(Qt.Key_P, Qt.MetaModifier)
        compare(service.homeCalls, 1)
        verify(service.query !== ";")
    }
    function test_embeddedProviderPickerStaysSemicolon() {
        keyClick(Qt.Key_P, Qt.MetaModifier)
        compare(service.query, ";")
        compare(service.homeCalls, 0)
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
