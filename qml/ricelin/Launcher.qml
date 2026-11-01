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
    readonly property bool outputMode: !outputDismissed && service !== null && service.outputTitle.length > 0
    readonly property var results: service ? service.results : []
    readonly property var rows: actionMode && actionItem ? actionItem.actions : results
    readonly property bool blocked: !service || !service.ready || service.busy || service.searching
    // A service action descriptor may carry a confirmation prompt. Selecting it
    // stages consent here; nothing is sent until the user explicitly confirms.
    readonly property var pendingConfirmation: service && service.pendingConfirmation ? service.pendingConfirmation : ({})
    readonly property bool confirming: !!pendingConfirmation.prompt
    property string selectedIdentity: ""
    property point lastPointer: Qt.point(-1, -1)
    property bool previewEnabled: true
    readonly property bool previewVisible: previewEnabled && !actionMode && !outputMode && !confirming && service && service.serviceMode &&
        (!!service.previewLoading || !!(service.previewContent && service.previewContent.length > 0))
    function refreshPreview() {
        if (!service || !service.serviceMode || !service.requestDetails) return
        // Pending rows and preview are display-only; the bridge already revoked
        // their snapshot authority. Explicit hide/toggle must still clear them.
        if (open && previewEnabled && service.searching && !actionMode && !outputMode && !confirming) return
        const item = results[selectedIndex]
        if (!open || !previewEnabled || blocked || actionMode || outputMode || confirming || !item || !item.detailsAvailable) service.clearDetails()
        else service.requestDetails(item.provider, item.id)
    }
    onSelectedIndexChanged: refreshPreview()
    onActionModeChanged: refreshPreview()
    onPreviewEnabledChanged: refreshPreview()
    onConfirmingChanged: refreshPreview()

    function focusField() { if (root.open) search.input.forceActiveFocus() }
    function resetQuery(text) {
        // Invalidate the bridge snapshot before selection changes can refresh
        // details for an old row. Equal text still requests a fresh snapshot.
        if (search.text === text) {
            if (service) service.setQuery(text)
        } else search.text = text
        actionMode = false
        actionItem = null
        actionIndex = 0
        selectedIndex = 0
        selectedIdentity = ""
        outputDismissed = false
        focusField()
    }
    function select(index) {
        if (confirming) service.cancelActivation()
        selectedIndex = Math.max(0, Math.min(results.length - 1, index))
        selectedIdentity = results.length ? results[selectedIndex].provider + "/" + results[selectedIndex].id : ""
        list.positionViewAtIndex(selectedIndex, ListView.Contain)
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
        } else {
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
    }
    Connections {
        target: root.service
        function onCloseRequested() { if (root.open) root.requestClose() }
        function onQueryRequested(text) { if (root.open) root.resetQuery(text) }
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
        onTextChanged: {
            if (root.open && root.service) root.service.setQuery(text)
            root.actionMode = false
            root.actionItem = null
            root.selectedIndex = 0
            root.selectedIdentity = ""
            root.outputDismissed = false
        }
        onMoved: (delta) => root.move(delta)
        onAccepted: root.activate(false)
        onDismissed: root.handleEscape()
        onKeyPressed: (event) => {
            if ((event.modifiers & Qt.MetaModifier) && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_P) {
                root.previewEnabled = !root.previewEnabled; event.accepted = true
            } else if ((event.modifiers & Qt.MetaModifier) && event.key === Qt.Key_K) {
                root.showActions(); event.accepted = true
            } else if ((event.modifiers & Qt.MetaModifier) && event.key === Qt.Key_P) {
                if (root.service && root.service.serviceMode) root.service.home()
                else root.resetQuery(";")
                event.accepted = true
            } else if ((event.modifiers & Qt.MetaModifier) && (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)) {
                root.showActions(); event.accepted = true
            } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
                root.activate(true); event.accepted = true
            } else if (root.outputMode && (event.modifiers & Qt.MetaModifier) && event.key === Qt.Key_C) {
                root.service.copyOutput(); event.accepted = true
            } else if ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_N || event.key === Qt.Key_P)) {
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
        text: root.actionMode && root.actionItem ? root.actionItem.title : root.outputMode ? root.service.outputTitle : ""
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
        visible: !root.outputMode
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
                    visible: !root.actionMode && text.length > 0
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
        text: root.confirming ? "↵ apply · esc cancel" : root.service && root.service.lastError.length ? root.service.lastError : root.service && root.service.shortcutError.length ? root.service.shortcutError : root.actionMode ? "↑ ↓ select · ↵ run · esc back" : root.outputMode ? "⌘C copy output · esc back" : "↑ ↓ select · ↵ open · ⌘K actions · ⌘P providers"
        maximumLineCount: 2
        wrapMode: Text.Wrap
        elide: Text.ElideRight
        color: root.service && root.service.lastError.length ? Theme.error : Theme.faint
        font.family: Theme.font
        font.pixelSize: 10 * root.s
    }
}
