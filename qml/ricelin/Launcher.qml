import QtQuick
import QtQuick.Controls
import "Singletons"
import "." as Ricelin

// Ricelin's fixed-size launcher layout, backed by maccer instead of DesktopEntries.
PillSurface {
    id: root
    objectName: "launcherSurface"
    mTop: 15
    mLeft: 13
    mRight: 13
    mBottom: 14
    property var service: null
    property int selectedIndex: 0
    property bool actionMode: false
    property var actionItem: null
    property int actionIndex: 0
    property bool outputDismissed: false
    // Set by the pill's openThemes() so the palette button lands on the shared
    // theme catalog instead of the provider menu. Cleared by the first search.
    property bool pendingThemes: false
    readonly property bool outputMode: !outputDismissed && service !== null && service.outputTitle.length > 0
    readonly property string queryText: service ? String(service.query || "") : ""
    readonly property var results: rankRows(service ? service.results : [], queryText)
    readonly property var rows: actionMode && actionItem ? actionItem.actions : results
    readonly property bool blocked: !service || !service.ready || service.busy || service.searching
    // The shared backend browses themes as a provider route. Render that route
    // as palette cards, matching the Appearance grid, instead of a text list.
    readonly property bool gridMode: !actionMode && !outputMode && service !== null && service.providerScoped &&
        results.length > 0 && everyRowIsTheme(results)
    readonly property string activeThemeSlug: service && service.themeState ? String(service.themeState.slug || "") : ""
    // A service action descriptor may carry a confirmation prompt. Selecting it
    // stages consent here; nothing is sent until the user explicitly confirms.
    readonly property var pendingConfirmation: service && service.pendingConfirmation ? service.pendingConfirmation : ({})
    readonly property bool confirming: !!pendingConfirmation.prompt
    property string selectedIdentity: ""
    property point lastPointer: Qt.point(-1, -1)
    property bool previewEnabled: true
    readonly property bool previewVisible: previewEnabled && !actionMode && !outputMode && !confirming && !gridMode && service && service.serviceMode &&
        (!!service.previewLoading || !!(service.previewContent && service.previewContent.length > 0))
    function refreshPreview() {
        if (!service || !service.serviceMode || !service.requestDetails) return
        // Pending rows and preview are display-only; the bridge already revoked
        // their snapshot authority. Explicit hide/toggle must still clear them.
        if (open && previewEnabled && service.searching && !actionMode && !outputMode && !confirming) return
        const item = results[selectedIndex]
        if (!open || !previewEnabled || gridMode || blocked || actionMode || outputMode || confirming || !item || !item.detailsAvailable) service.clearDetails()
        else service.requestDetails(item.provider, item.id)
    }
    onSelectedIndexChanged: refreshPreview()
    onActionModeChanged: refreshPreview()
    onPreviewEnabledChanged: refreshPreview()
    onConfirmingChanged: refreshPreview()

    function focusField() { if (root.open) search.input.forceActiveFocus() }
    function identityAt(index) {
        const item = results[index]
        return item ? item.provider + "/" + item.id : ""
    }
    function everyRowIsTheme(items) {
        for (let i = 0; i < items.length; ++i)
            if (!items[i] || String(items[i].provider || "") !== "themes") return false
        return true
    }
    // Lower tiers are better. The backend also scores bundle paths and
    // keywords, so Finder.app helpers (AirDrop, Computer, Recents) match
    // "find" even though their own names do not contain it.
    function titleTier(title, query) {
        const text = String(title || "").toLowerCase()
        query = String(query || "").toLowerCase()
        if (!text) return 6
        if (text === query) return 0
        if (text.indexOf(query) === 0) return 1
        if (text.indexOf(" " + query) >= 0) return 2
        if (text.indexOf(query) > 0) return 3
        let at = 0
        for (let i = 0; i < query.length; ++i) {
            at = text.indexOf(query.charAt(i), at)
            if (at < 0) return 5
            at += 1
        }
        return 4
    }
    function rankRows(items, query) {
        const text = String(query || "").trim().toLowerCase()
        if (!text) return items
        const kept = []
        for (let i = 0; i < items.length; ++i) {
            const item = items[i]
            if (!item) continue
            // Provider entries are navigation, not matches. The backend scores
            // them against long descriptions, which is how "find" matched
            // "Browse palettes and explicitly confirm Apply…". Keep one only
            // when the typed word actually begins its name.
            if (String(item.provider || "") === "menu" &&
                String(item.title || "").toLowerCase().indexOf(text) !== 0) continue
            kept.push(item)
        }
        const slots = []
        for (let i = 0; i < kept.length; ++i)
            if (String(kept[i].provider || "") === "apps") slots.push(i)
        if (slots.length < 2) return kept
        const apps = []
        for (let i = 0; i < slots.length; ++i)
            apps.push({row: kept[slots[i]], order: i, tier: titleTier(kept[slots[i]].title, text)})
        apps.sort((a, b) => a.tier - b.tier || a.order - b.order)
        const ranked = kept.slice()
        for (let i = 0; i < slots.length; ++i) ranked[slots[i]] = apps[i].row
        return ranked
    }
    function themeSwatches(item) {
        const swatches = []
        const blocks = item && item["content"] ? item["content"] : []
        for (let i = 0; i < blocks.length; ++i) {
            const block = blocks[i]
            if (!block || block.type !== "colorPalette" || !block.colors) continue
            for (let j = 0; j < block.colors.length; ++j) {
                const value = String(block.colors[j].value || "")
                if (/^#[0-9a-fA-F]{6}$/.test(value)) swatches.push({role: String(block.colors[j].role || ""), value: value})
            }
        }
        return swatches
    }
    function themeColor(item, role, fallback) {
        const swatches = themeSwatches(item)
        for (let i = 0; i < swatches.length; ++i)
            if (swatches[i].role === role) return swatches[i].value
        return fallback
    }
    function themeDots(item) {
        const swatches = themeSwatches(item)
        const dots = []
        for (let i = 0; i < swatches.length && dots.length < 6; ++i) dots.push(swatches[i].value)
        return dots.length ? dots : [Theme.frameBg, Theme.onGlow, Theme.cream]
    }
    function themeSlug(item) {
        return item && item["data"] ? String(item["data"].slug || "") : ""
    }
    function themeVariant(item) {
        return item && item["data"] ? String(item["data"].variant || "") : ""
    }
    function moveGrid(step) {
        if (confirming) service.cancelActivation()
        if (!results.length) return
        select(selectedIndex + step)
    }
    // The palette button hands the launcher a themes intent. Home results
    // always publish the Themes provider entry; open that route once so the
    // shared catalog appears without hunting through the provider menu.
    function openPendingThemes() {
        if (!pendingThemes || !service || service.searching || service.providerScoped || !results.length) return
        if (queryText.length > 0) { pendingThemes = false; return }
        let themeMenu = -1
        for (let i = 0; i < results.length; ++i)
            if (results[i] && results[i].provider === "menu" && results[i].id === "themes") themeMenu = i
        pendingThemes = false
        if (themeMenu >= 0) {
            select(themeMenu)
            activate(false)
        }
    }
    function resetQuery(text) {
        // Invalidate the bridge snapshot before selection changes can refresh
        // details for an old row. Equal text still requests a fresh snapshot.
        if (search.text === text) {
            if (service) service.setQuery(text)
        } else search.text = text
        actionMode = false
        actionItem = null
        actionIndex = 0
        // Clear the remembered row before moving the cursor: the next details
        // request can reconcile rows synchronously and must not revive it.
        selectedIdentity = ""
        selectedIndex = 0
        outputDismissed = false
        focusField()
    }
    function select(index) {
        if (confirming) service.cancelActivation()
        if (!results.length) return
        const bounded = Math.max(0, Math.min(results.length - 1, index))
        // Remember the identity first. Assigning selectedIndex starts a details
        // request, and a snapshot reconciliation during that request would
        // otherwise see the previous identity and jump back to the first row.
        selectedIdentity = identityAt(bounded)
        selectedIndex = bounded
        if (gridMode) themeGrid.positionViewAtIndex(bounded, GridView.Contain)
        else list.positionViewAtIndex(bounded, ListView.Contain)
    }
    function move(delta) {
        if (confirming) service.cancelActivation()
        if (!rows.length || outputMode) return
        if (actionMode) {
            actionIndex = Math.max(0, Math.min(rows.length - 1, actionIndex + delta))
            list.positionViewAtIndex(actionIndex, ListView.Contain)
        } else select(selectedIndex + delta)
    }
    function activate(secondary) {
        if (outputMode) return
        if (confirming) { if (!secondary) service.confirmActivation(); return }
        if (blocked) return
        const item = actionMode ? actionItem : results[selectedIndex]
        if (!item || !item.actions || !item.actions.length) return
        const index = actionMode ? actionIndex : secondary ? 1 : 0
        if (index >= item.actions.length) return
        service.activate(item.provider, item.id, item.actions[index].id)
    }
    function showActions() {
        if (confirming) service.cancelActivation()
        if (blocked || outputMode || !results.length) return
        if (actionMode) { actionMode = false; focusField(); return }
        actionItem = results[selectedIndex]
        actionIndex = 0
        actionMode = true
    }
    function handleEscape() {
        if (confirming) { service.cancelActivation(); focusField(); return }
        if (service && service.busy) { resetQuery(search.text); return }
        if (actionMode) { actionMode = false; actionItem = null; focusField(); return }
        if (outputMode) { outputDismissed = true; resetQuery(search.text); return }
        if (search.text.length) resetQuery("")
        else if (service && service.serviceMode && service.providerScoped) service.home()
        else requestClose()
    }
    onOpenChanged: {
        if (open) {
            lastPointer = Qt.point(-1, -1)
            resetQuery("")
            Qt.callLater(focusField)
            Qt.callLater(openPendingThemes)
        } else {
            // A cancelled themes intent must not fire on the next plain open.
            pendingThemes = false
            if (service) service.cancel()
            actionMode = false
            actionItem = null
        }
    }
    onResultsChanged: {
        Qt.callLater(refreshPreview)
        let found = -1
        for (let i = 0; i < results.length; i++)
            if (results[i].provider + "/" + results[i].id === selectedIdentity) { found = i; break }
        selectedIndex = found >= 0 ? found : 0
        if (actionMode && actionItem) {
            let current = null
            for (let j = 0; j < results.length; j++)
                if (results[j].provider === actionItem.provider && results[j].id === actionItem.id) current = results[j]
            if (current) actionItem = current
            else { actionMode = false; actionItem = null }
        }
        root.openPendingThemes()
    }
    Connections {
        target: root.service
        function onCloseRequested() { if (root.open) root.requestClose() }
        function onQueryRequested(text) { if (root.open) root.resetQuery(text) }
        // A repeated home snapshot can have identical rows, so waiting only for
        // resultsChanged would strand a pending themes request.
        function onStateChanged() { if (root.open) root.openPendingThemes() }
    }
    Ricelin.SearchField {
        id: search
        inputObjectName: "launcherInput"
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        s: root.s
        placeholder: root.actionMode ? "Choose an action" : "Search apps, files, commands"
        counterText: root.service && root.service.busy ? "Working…" : root.service && root.service.searching ? "Searching…" : root.results.length.toString()
        onEdited: root.pendingThemes = false
        onTextChanged: {
            if (root.open && root.service) root.service.setQuery(text)
            root.actionMode = false
            root.actionItem = null
            root.selectedIdentity = ""
            root.selectedIndex = 0
            root.outputDismissed = false
        }
        onMoved: (delta) => root.move(delta)
        onAccepted: root.activate(false)
        onDismissed: root.handleEscape()
        onKeyPressed: (event) => {
            // Qt swaps the platform modifiers on macOS: Command arrives as
            // ControlModifier and the Control key as MetaModifier.
            if ((event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_P) {
                root.previewEnabled = !root.previewEnabled; event.accepted = true
            } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_K) {
                root.showActions(); event.accepted = true
            } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_P) {
                if (root.service && root.service.serviceMode) root.service.home()
                else root.resetQuery(";")
                event.accepted = true
            } else if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                root.showActions(); event.accepted = true
            } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                root.activate(true); event.accepted = true
            } else if (root.outputMode && (event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_C) {
                root.service.copyOutput(); event.accepted = true
            } else if (root.gridMode && (event.key === Qt.Key_Left || event.key === Qt.Key_Right ||
                                         event.key === Qt.Key_Up || event.key === Qt.Key_Down)) {
                // Cards are laid out three per row. Left/Right step through the
                // row; Up/Down jump a whole row and clamp at the ends.
                const step = event.key === Qt.Key_Left ? -1 : event.key === Qt.Key_Right ? 1 :
                             event.key === Qt.Key_Up ? -3 : 3
                root.moveGrid(step); event.accepted = true
            } else if ((event.modifiers & Qt.MetaModifier) && (event.key === Qt.Key_N || event.key === Qt.Key_P)) {
                root.move(event.key === Qt.Key_N ? 1 : -1); event.accepted = true
            }
        }
        GlyphIcon {
            name: "close"
            width: 24 * root.s
            height: 24 * root.s
            color: closeHover.hovered ? Theme.cream : Theme.dim
            HoverHandler { id: closeHover }
            TapHandler { onTapped: root.requestClose() }
            Accessible.role: Accessible.Button
            Accessible.name: "Close launcher"
            Accessible.onPressAction: root.requestClose()
        }
    }
    Rectangle {
        id: divider
        anchors.top: search.bottom
        anchors.topMargin: 9 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Theme.hair
    }
    Text {
        id: heading
        anchors.top: divider.bottom
        anchors.topMargin: 9 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        textFormat: Text.PlainText
        text: root.actionMode && root.actionItem ? root.actionItem.title : root.outputMode ? root.service.outputTitle : root.gridMode ? "Themes" : ""
        visible: text.length > 0
        height: visible ? 16 * root.s : 0
        elide: Text.ElideRight
        font.family: Theme.font
        font.pixelSize: 11 * root.s
        color: Theme.dim
    }
    ListView {
        id: list
        objectName: "launcherResults"
        anchors.top: heading.bottom
        anchors.topMargin: 6 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: preview.top
        anchors.bottomMargin: root.confirming ? confirmPrompt.height + 7 * root.s : 7 * root.s
        clip: true
        visible: !root.outputMode && !root.gridMode
        spacing: 5 * root.s
        boundsBehavior: Flickable.StopAtBounds
        model: root.rows
        delegate: Item {
            id: row
            required property int index
            required property var modelData
            readonly property bool selected: index === (root.actionMode ? root.actionIndex : root.selectedIndex)
            width: list.width
            height: 42 * root.s
            Rectangle {
                anchors.fill: parent
                radius: 9 * root.s
                color: row.selected ? Theme.frameBg : mouse.containsMouse ? Theme.hoverBg : "transparent"
                border.width: row.selected ? 1 : 0
                border.color: Theme.frameBorder
            }
            MouseArea {
                id: mouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: (event) => {
                    const position = mouse.mapToItem(null, event.x, event.y)
                    if (position.x === root.lastPointer.x && position.y === root.lastPointer.y) return
                    root.lastPointer = position
                    if (root.actionMode) root.actionIndex = row.index
                    else root.select(row.index)
                }
                onClicked: {
                    if (root.actionMode) root.actionIndex = row.index
                    else root.select(row.index)
                    root.activate(false)
                    root.focusField()
                }
            }
            Rectangle {
                id: iconBg
                anchors.left: parent.left
                anchors.leftMargin: 10 * root.s
                anchors.verticalCenter: parent.verticalCenter
                width: 26 * root.s
                height: 26 * root.s
                radius: 6 * root.s
                color: Theme.iconBg
                visible: !root.actionMode
                Text {
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: row.modelData.iconText || ""
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 12 * root.s
                    visible: icon.status !== Image.Ready
                }
                Image {
                    id: icon
                    objectName: "launcherResultIcon"
                    anchors.fill: parent
                    source: row.modelData.iconSource || ""
                    sourceSize: Qt.size(64, 64)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    visible: status === Image.Ready
                }
            }
            Column {
                anchors.left: root.actionMode ? parent.left : iconBg.right
                anchors.leftMargin: 10 * root.s
                anchors.right: returnGlyph.left
                anchors.rightMargin: 8 * root.s
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1 * root.s
                Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: row.modelData.title || ""
                    elide: Text.ElideRight
                    color: Theme.cream
                    font.family: Theme.font
                    font.pixelSize: 13 * root.s
                    font.weight: row.selected ? Font.DemiBold : Font.Normal
                }
                Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: row.modelData.subtitle || ""
                    // Applications show their name alone; bundle paths and
                    // "Application" descriptions only add noise beside a result.
                    visible: !root.actionMode && text.length > 0 &&
                        String(row.modelData.provider || "") !== "apps"
                    elide: Text.ElideRight
                    color: Theme.faint
                    font.family: Theme.font
                    font.pixelSize: 10 * root.s
                }
            }
            GlyphIcon {
                id: returnGlyph
                anchors.right: parent.right
                anchors.rightMargin: 10 * root.s
                anchors.verticalCenter: parent.verticalCenter
                width: 15 * root.s
                height: 15 * root.s
                name: "return"
                color: Theme.vermLit
                visible: row.selected
            }
            Accessible.role: Accessible.ListItem
            Accessible.name: modelData.title || ""
            Accessible.selected: selected
            Accessible.onPressAction: { root.select(row.index); root.activate(false) }
        }
    }
    // Shared-service theme catalogs are palette rows, not plain results. Show
    // the same square-card language as the Appearance grid: fill from the
    // theme background, swatches from its resolved palette, name underneath.
    GridView {
        id: themeGrid
        objectName: "launcherThemes"
        anchors.top: heading.bottom
        anchors.topMargin: 6 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: status.top
        anchors.bottomMargin: root.confirming ? confirmPrompt.height + 7 * root.s : 7 * root.s
        visible: root.gridMode && !root.outputMode
        clip: true
        model: root.gridMode ? root.results : []
        cellWidth: width / 3
        cellHeight: cellWidth
        boundsBehavior: Flickable.StopAtBounds
        currentIndex: root.selectedIndex
        delegate: Item {
            id: themeCell
            required property int index
            required property var modelData
            objectName: "themeCell_" + root.themeSlug(modelData)
            readonly property bool selected: index === root.selectedIndex
            readonly property bool currentTheme: root.activeThemeSlug.length > 0 &&
                root.themeSlug(modelData) === root.activeThemeSlug
            readonly property color cardBackground: root.themeColor(modelData, "background", Theme.frameBg)
            readonly property color cardForeground: root.themeColor(modelData, "foreground", Theme.cream)
            width: themeGrid.cellWidth
            height: themeGrid.cellHeight
            Accessible.role: Accessible.Button
            Accessible.name: String(modelData.title || "Theme")
            Accessible.selected: selected
            Accessible.onPressAction: { root.select(index); root.activate(false) }
            Rectangle {
                anchors.fill: parent
                anchors.margins: 4 * root.s
                radius: 10 * root.s
                color: Qt.tint(themeCell.cardBackground, Qt.alpha(Theme.frameBg, themeCell.selected || themeCell.currentTheme ? 0.06 : 0.32))
                border.width: themeCell.currentTheme || themeCell.selected ? 2 * root.s : 1
                border.color: themeCell.currentTheme ? Theme.vermLit : themeCell.selected ? Theme.onGlow : Theme.border
                Behavior on border.color { ColorAnimation { duration: Motion.fast } }
                Column {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: 9 * root.s
                    spacing: 7 * root.s
                    Item {
                        width: parent.width
                        height: 12 * root.s
                        Row {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4 * root.s
                            Repeater {
                                model: root.themeDots(themeCell.modelData)
                                delegate: Rectangle {
                                    required property var modelData
                                    width: 9 * root.s; height: width; radius: width / 2
                                    color: modelData
                                    border.width: 1; border.color: Theme.hair
                                }
                            }
                        }
                        Rectangle {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 7 * root.s; height: width; radius: width / 2
                            color: themeCell.cardForeground
                            visible: themeCell.selected && !themeCell.currentTheme
                        }
                    }
                    Text {
                        width: parent.width
                        height: 28 * root.s
                        textFormat: Text.PlainText
                        text: String(modelData.title || "Theme")
                        wrapMode: Text.Wrap
                        elide: Text.ElideRight
                        color: themeCell.cardForeground
                        font.family: Theme.font
                        font.pixelSize: 10 * root.s
                        font.weight: Font.DemiBold
                        verticalAlignment: Text.AlignVCenter
                    }
                    Text {
                        width: parent.width
                        textFormat: Text.PlainText
                        text: themeCell.currentTheme ? "CURRENT" : root.themeVariant(modelData).toUpperCase()
                        elide: Text.ElideRight
                        color: Qt.alpha(themeCell.cardForeground, 0.65)
                        font.family: Theme.font
                        font.pixelSize: 7.5 * root.s
                        font.letterSpacing: 0.8 * root.s
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        root.select(index)
                        root.activate(false)
                        root.focusField()
                    }
                }
            }
        }
    }
    Text {
        anchors.centerIn: list
        textFormat: Text.PlainText
        visible: !root.outputMode && !root.rows.length
        text: !root.service ? "Launcher unavailable" : !root.service.ready ? "Starting maccer…" : root.service.searching ? "Searching…" : "No matches"
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: 12 * root.s
    }
    ScrollView {
        anchors.fill: list
        visible: root.outputMode
        TextArea {
            text: root.service ? root.service.outputText : ""
            textFormat: TextEdit.PlainText
            readOnly: true
            selectByMouse: true
            wrapMode: TextEdit.Wrap
            color: Theme.cream
            font.family: Theme.font
            font.pixelSize: 12 * root.s
            background: null
            Keys.onEscapePressed: { root.handleEscape(); root.focusField() }
        }
    }
    ServicePreview {
        id: preview
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: status.top
        height: root.previewVisible ? 112 * root.s : 0
        visible: root.previewVisible
        s: root.s
        blocks: root.service && root.service.serviceMode && root.service.previewContent ? root.service.previewContent : []
        loading: root.service && root.service.serviceMode ? !!root.service.previewLoading : false
    }
    Rectangle {
        id: confirmPrompt
        objectName: "launcherConfirmation"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: status.top
        height: root.confirming ? Math.min(160 * root.s, Math.max(72 * root.s, confirmText.implicitHeight + 44 * root.s)) : 0
        visible: root.confirming
        radius: 9 * root.s
        color: Theme.frameBg
        border.width: 1
        border.color: Theme.frameBorder
        Flickable {
            objectName: "launcherConfirmationScroll"
            anchors.left: parent.left
            anchors.leftMargin: 10 * root.s
            anchors.right: parent.right
            anchors.rightMargin: 10 * root.s
            anchors.top: parent.top
            anchors.topMargin: 8 * root.s
            anchors.bottom: confirmButtons.top
            anchors.bottomMargin: 8 * root.s
            contentWidth: width
            contentHeight: confirmText.implicitHeight
            clip: true
            ScrollBar.vertical: ScrollBar {}
            Text {
                id: confirmText
                objectName: "launcherConfirmationText"
                width: parent.width
                textFormat: Text.PlainText
                text: root.confirming ? root.pendingConfirmation.prompt : ""
                wrapMode: Text.Wrap
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 11 * root.s
            }
        }
        Row {
            id: confirmButtons
            anchors.right: parent.right
            anchors.rightMargin: 8 * root.s
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 8 * root.s
            spacing: 6 * root.s
            Rectangle {
                objectName: "launcherConfirmationCancel"
                width: cancelLabel.width + 20 * root.s
                height: 24 * root.s
                radius: 6 * root.s
                color: cancelHover.hovered ? Theme.hoverBg : "transparent"
                border.width: 1
                border.color: Theme.frameBorder
                Text {
                    id: cancelLabel
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: "Cancel"
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 11 * root.s
                }
                HoverHandler { id: cancelHover }
                TapHandler { onTapped: { root.service.cancelActivation(); root.focusField() } }
                Accessible.role: Accessible.Button
                Accessible.name: "Cancel action"
                Accessible.onPressAction: { root.service.cancelActivation(); root.focusField() }
            }
            Rectangle {
                objectName: "launcherConfirmationApply"
                width: applyLabel.width + 20 * root.s
                height: 24 * root.s
                radius: 6 * root.s
                color: applyHover.hovered ? Theme.hoverBg : Theme.frameBg
                border.width: 1
                border.color: Theme.frameBorder
                Text {
                    id: applyLabel
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: "Apply"
                    color: Theme.cream
                    font.family: Theme.font
                    font.pixelSize: 11 * root.s
                }
                HoverHandler { id: applyHover }
                TapHandler { onTapped: { root.service.confirmActivation(); root.focusField() } }
                Accessible.role: Accessible.Button
                Accessible.name: "Confirm action"
                Accessible.onPressAction: { root.service.confirmActivation(); root.focusField() }
            }
        }
    }
    Text {
        id: status
        objectName: "launcherStatus"
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 28 * root.s
        textFormat: Text.PlainText
        text: root.confirming ? "↵ apply · esc cancel" : root.service && root.service.lastError.length ? root.service.lastError : root.service && root.service.shortcutError.length ? root.service.shortcutError : root.actionMode ? "↑ ↓ select · ↵ run · esc back" : root.outputMode ? "⌘C copy output · esc back" : root.gridMode ? "← → ↑ ↓ select · ↵ apply · esc back" : "↑ ↓ select · ↵ open · ⌘K actions · ⌘P providers"
        maximumLineCount: 2
        wrapMode: Text.Wrap
        elide: Text.ElideRight
        color: root.service && root.service.lastError.length ? Theme.error : Theme.faint
        font.family: Theme.font
        font.pixelSize: 10 * root.s
    }
}
