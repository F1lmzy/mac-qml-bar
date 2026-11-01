pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import "Singletons"

/**
 * Theme picker for mac-themer packs. The cards keep each pack's palette visible
 * at a glance; wallpaper selection lives on its own carousel surface.
 */
PillSurface {
    id: root
    objectName: "appearanceSurface"
    mTop: 14; mLeft: 16; mRight: 16; mBottom: 14
    property var systemService: null
    property var themeSource: null
    readonly property var themeState: themeSource !== null ? themeSource : systemService && systemService.theme ? systemService.theme : ({})
    readonly property bool busy: themeState.busy === true
    readonly property var themes: themeState.themes || []
    property int focusIndex: 0
    property string pendingAction: ""
    property var pendingArgument: ({})
    property string pendingLabel: ""
    property string pendingSlug: ""
    signal requestBack()
    signal requestBackgrounds()

    function clearPending() { pendingAction = ""; pendingArgument = ({}); pendingLabel = ""; pendingSlug = "" }
    function refreshCatalog() { if (themeSource === null && systemService) systemService.invoke("theme", "catalog", null) }
    function confirm(action, argument, label) {
        if (themeSource !== null || !systemService || busy) return
        pendingAction = action; pendingArgument = argument || ({}); pendingLabel = label
        pendingSlug = String(themeState.slug || "")
    }
    function applyPending() {
        if (themeSource !== null || !pendingAction || busy || !systemService) return
        systemService.invoke("theme", pendingAction, Object.assign({}, pendingArgument, {confirmed: true}))
        clearPending()
    }
    function moveSelection(dx, dy) {
        if (themes.length === 0) return
        var col = focusIndex % 3
        var row = Math.floor(focusIndex / 3)
        col = Math.max(0, Math.min(2, col + dx))
        row = Math.max(0, Math.min(1, row + dy))
        focusIndex = Math.max(0, Math.min(themes.length - 1, row * 3 + col))
    }
    function activateFocused() {
        if (busy || !systemService || root.themeState.canSelect !== true) return
        if (focusIndex < 0 || focusIndex >= themes.length) return
        var item = themes[focusIndex]
        if (String(item.slug || "") === String(themeState.slug || "")) return
        confirm("select", {slug: String(item.slug)}, "Apply " + String(item.name) + " to your desktop and apps?")
        applyPending()
    }
    function handleEscape() { if (pendingAction) clearPending(); else requestClose() }
    function themeColors(item) {
        var raw = String(item && item.swatches || "").split(",")
        var colors = []
        for (var i = 0; i < raw.length; i++) if (raw[i].trim().length > 0) colors.push(raw[i].trim())
        return colors.length ? colors : [Theme.cardTop, Theme.onGlow, Theme.cream, Theme.success, Theme.error]
    }
    function activeColors() {
        for (var i = 0; i < themes.length; i++)
            if (String(themes[i].slug || "") === String(themeState.slug || "")) return themeColors(themes[i])
        return [Theme.cardTop, Theme.onGlow, Theme.cream, Theme.success, Theme.error]
    }
    onActiveChanged: {
        clearPending()
        if (active) {
            refreshCatalog()
            focusIndex = currentThemeIndex() >= 0 ? currentThemeIndex() : 0
        }
    }
    function currentThemeIndex() {
        for (var i = 0; i < themes.length; i++) if (String(themes[i].slug || "") === String(themeState.slug || "")) return i
        return -1
    }
    onThemesChanged: {
        if (focusIndex >= themes.length) focusIndex = Math.max(0, themes.length - 1)
        if (focusIndex < 0 && themes.length > 0) focusIndex = 0
    }
    onThemeStateChanged: {
        if (pendingAction && (busy || pendingSlug !== String(themeState.slug || ""))) clearPending()
    }

    component ActionButton: Button {
        id: button
        implicitWidth: implicitContentWidth + 20 * root.s
        implicitHeight: 28 * root.s
        opacity: enabled ? 1 : 0.4
        font.family: Theme.font
        font.pixelSize: 10 * root.s
        Accessible.name: text
        background: Rectangle {
            radius: 8 * root.s
            color: button.checked || button.highlighted ? Theme.frameBg : button.hovered ? Theme.hoverBg : "transparent"
            border.width: 1
            border.color: button.activeFocus || button.checked || button.highlighted ? Theme.onGlow : Theme.border
        }
        contentItem: Text {
            text: button.text; textFormat: Text.PlainText; font: button.font
            color: Theme.cream; elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter
        }
    }
    component SectionLabel: Text {
        textFormat: Text.PlainText
        color: Theme.subtle
        font.family: Theme.font; font.pixelSize: 9 * root.s; font.weight: Font.DemiBold
        font.letterSpacing: 1.2 * root.s
    }

    Item {
        id: header
        width: parent.width; height: 28 * root.s
        SectionLabel { anchors.verticalCenter: parent.verticalCenter; text: "THEMES" }
        Row {
            anchors.right: parent.right; spacing: 4 * root.s
            ActionButton { text: "Backgrounds >"; onClicked: root.requestBackgrounds() }
            ActionButton { objectName: "appearanceNextTheme"; text: "Next"; enabled: root.themeState.canNext === true && !root.busy; onClicked: root.confirm("next", null, "Apply the next theme to your desktop and apps?") }
            ActionButton { objectName: "appearanceRefresh"; text: "Refresh"; enabled: root.themeSource === null && root.systemService !== null && !root.themeState.catalogLoading && !root.busy; onClicked: root.refreshCatalog() }
            ActionButton { text: "Close"; onClicked: root.requestClose() }
        }
    }
    Rectangle { id: divider; anchors.top: header.bottom; anchors.topMargin: 8 * root.s; width: parent.width; height: 1; color: Theme.hair }

    Item {
        id: content
        anchors.top: divider.bottom; anchors.topMargin: 9 * root.s
        anchors.left: parent.left; anchors.right: parent.right
        anchors.bottom: footer.top; anchors.bottomMargin: 7 * root.s
        property real gap: 8 * root.s
        // Square cards. The grid is three columns wide, so the column width sets
        // the card size; the host picks appearanceSize so two rows fit the height
        // exactly, rather than stretching cards to fill whatever space is left.
        property real cardSize: (width - 2 * gap) / 3
        Grid {
            id: grid
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left; anchors.right: parent.right
            columns: 3; spacing: content.gap
            Repeater {
                model: root.themes
                delegate: Item {
                    id: cardItem
                    required property var modelData
                    required property int index
                    objectName: "themeChoice_" + String(modelData.slug || index)
                    readonly property bool current: String(modelData.slug || "") === String(root.themeState.slug || "")
                    readonly property bool focused: index === root.focusIndex
                    readonly property color cardFill: modelData.background ? Qt.tint(Qt.color(String(modelData.background)), Qt.alpha(Theme.frameBg, focused || current ? 0.08 : 0.28)) : Theme.frameBg
                    width: content.cardSize
                    height: content.cardSize
                    enabled: root.themeState.canSelect === true && !root.busy
                    Accessible.role: Accessible.Button
                    Accessible.name: String(modelData.name || "Theme")
                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: cardItem.current ? 1 : 0
                        radius: 10 * root.s
                        color: cardItem.cardFill
                        border.width: cardItem.current ? 2 * root.s : cardItem.focused ? 2 * root.s : 1
                        border.color: cardItem.current ? Theme.vermLit : cardItem.focused ? Theme.onGlow : Theme.border
                        Behavior on border.color { ColorAnimation { duration: Motion.fast } }
                        Column {
                            // Centred rather than top-aligned: the card is square, so a
                            // top-hung block leaves a visibly empty lower half.
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.margins: 8 * root.s
                            spacing: 7 * root.s
                            Item {
                                width: parent.width; height: 12 * root.s
                                Row {
                                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                    spacing: 4 * root.s
                                    Repeater {
                                        model: root.themeColors(cardItem.modelData)
                                        delegate: Rectangle {
                                            required property var modelData
                                            required property int index
                                            objectName: "themeDot_" + String(cardItem.modelData.slug || cardItem.index) + "_" + index
                                            width: 9 * root.s; height: width; radius: width / 2
                                            color: modelData
                                            border.width: 1; border.color: Theme.hair
                                        }
                                    }
                                }
                                Rectangle {
                                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                    width: 7 * root.s; height: width; radius: width / 2
                                    color: cardItem.modelData.accent ? Qt.color(String(cardItem.modelData.accent)) : Theme.onGlow
                                    visible: cardItem.focused && !cardItem.current
                                }
                            }
                            Text {
                                width: parent.width; height: 28 * root.s
                                text: String(cardItem.modelData.name || "Theme")
                                textFormat: Text.PlainText; wrapMode: Text.Wrap; elide: Text.ElideRight
                                color: cardItem.modelData.foreground ? Qt.color(String(cardItem.modelData.foreground)) : Theme.cream
                                font.family: Theme.font; font.pixelSize: 10 * root.s; font.weight: Font.DemiBold
                                verticalAlignment: Text.AlignVCenter
                            }
                            Text {
                                width: parent.width; text: cardItem.current ? "CURRENT" : ""
                                textFormat: Text.PlainText; color: Theme.subtle
                                font.family: Theme.font; font.pixelSize: 7 * root.s; font.letterSpacing: 0.8 * root.s
                            }
                        }
                    }
                    HoverHandler { onHoveredChanged: if (hovered) root.focusIndex = cardItem.index }
                    TapHandler {
                        onTapped: {
                            if (!cardItem.focused) root.focusIndex = cardItem.index
                            else if (!cardItem.current) root.confirm("select", {slug: String(cardItem.modelData.slug)}, "Apply " + String(cardItem.modelData.name) + " to your desktop and apps?")
                        }
                    }
                }
            }
        }
        Text {
            objectName: "appearanceEmptyThemes"
            anchors.centerIn: parent
            visible: root.themes.length === 0 && root.themeState.catalogLoading !== true
            text: root.themeState.catalogError || "No themes loaded. Install mac-themer, then refresh."
            textFormat: Text.PlainText; wrapMode: Text.Wrap; horizontalAlignment: Text.AlignHCenter
            color: root.themeState.catalogError ? Theme.error : Theme.dim
            font.family: Theme.font; font.pixelSize: 10 * root.s
            width: parent.width * 0.8
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom
            visible: root.themeState.catalogLoading === true
            text: "Loading themes…"; textFormat: Text.PlainText
            color: Theme.dim; font.family: Theme.font; font.pixelSize: 10 * root.s
        }
    }

    Item {
        id: footer
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        height: 82 * root.s
        Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Theme.hair }
        Row {
            anchors.top: parent.top; anchors.topMargin: 7 * root.s
            width: parent.width; height: 26 * root.s; spacing: 7 * root.s
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "ACTIVE"; textFormat: Text.PlainText; color: Theme.faint
                font.family: Theme.font; font.pixelSize: 8 * root.s; font.weight: Font.DemiBold; font.letterSpacing: 0.8 * root.s
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(40 * root.s, parent.width - activeDots.width - 68 * root.s)
                text: root.themeState.available ? String(root.themeState.name || "Current theme") : "No published theme"
                textFormat: Text.PlainText; color: Theme.cream; font.family: Theme.font
                font.pixelSize: 10 * root.s; font.weight: Font.DemiBold; elide: Text.ElideRight
            }
            Row {
                id: activeDots
                anchors.verticalCenter: parent.verticalCenter; spacing: 3 * root.s
                Repeater {
                    model: root.activeColors()
                    delegate: Rectangle {
                        required property var modelData
                        width: 8 * root.s; height: width; radius: width / 2
                        color: modelData; border.width: 1; border.color: Theme.hair
                    }
                }
            }
        }
        Text {
            anchors.top: parent.top; anchors.topMargin: 34 * root.s
            width: parent.width * 0.68; height: 38 * root.s
            textFormat: Text.PlainText; wrapMode: Text.Wrap; elide: Text.ElideRight
            text: root.pendingAction ? root.pendingLabel : (root.themeState.lastError || "Arrows move · Enter applies. Theme changes update mac-themer's other consumers.")
            color: root.themeState.lastError ? Theme.error : root.pendingAction ? Theme.cream : Theme.faint
            font.family: Theme.font; font.pixelSize: 8.5 * root.s
        }
        Row {
            anchors.right: parent.right; anchors.bottom: parent.bottom
            spacing: 5 * root.s
            // Visibility lives on the row, not the buttons: a child that toggles
            // its own visible changes the row's implicit width, and with a right
            // anchor that re-layout lands a frame late, parking the buttons
            // outside the surface on the first staged selection.
            visible: root.pendingAction.length > 0
            ActionButton { objectName: "appearanceApply"; text: "Apply"; highlighted: true; enabled: !root.busy; onClicked: root.applyPending() }
            ActionButton { objectName: "appearanceCancel"; text: "Cancel"; onClicked: root.clearPending() }
        }
    }
}
