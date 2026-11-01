pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import "Singletons"

/**
 * Local wallpaper filmstrip adapted from Ricelin's Wallpaper.qml. The pill
 * keeps only the browsing motion and confirmation controls; search, deletion,
 * monitor routing and video previews belong to the upstream desktop surface.
 * Cached small thumbs are warmed before the strip opens, avoiding full-size
 * image decoding during normal navigation.
 */
PillSurface {
    id: root
    objectName: "wallpaperSurface"
    mTop: 14; mLeft: 16; mRight: 16; mBottom: 14

    property var systemService: null
    property var themeSource: null
    readonly property var themeState: themeSource !== null ? themeSource : systemService && systemService.theme ? systemService.theme : ({})
    readonly property var wallpapers: themeState.wallpapers || []
    property int focusIndex: 0
    property real pos: 0
    property string pendingAction: ""
    property var pendingArgument: ({})
    property string pendingLabel: ""
    property string pendingSlug: ""
    signal requestBack()

    clip: true

    readonly property int itemCount: wallpapers.length
    readonly property var preloadRows: {
        var rows = [];
        for (var i = Math.max(0, focusIndex - 2); i <= Math.min(itemCount - 1, focusIndex + 2); ++i) {
            var row = wallpapers[i];
            if (row && row.thumb && String(row.thumb).length)
                rows.push({index: i, source: String(row.thumb)});
        }
        return rows;
    }

    readonly property var slotW:      [196, 126, 104, 88, 74]
    readonly property var slotH:      [110, 71, 59, 50, 42]
    readonly property var slotCX:     [0, 143, 244, 326, 393]
    readonly property var slotBright: [1, 0.56, 0.42, 0.30, 0.22]
    readonly property var slotSat:    [1, 0.65, 0.55, 0.45, 0.40]

    function slotLerp(arr, ao) {
        if (ao >= 4) return arr[4];
        var i = Math.floor(ao);
        var f = ao - i;
        return arr[i] + (arr[i + 1] - arr[i]) * f;
    }
    function offsetX(off) {
        var ao = Math.abs(off);
        var cx = ao <= 4 ? slotLerp(slotCX, ao) : slotCX[4] + (ao - 4) * 60;
        return (off < 0 ? -cx : cx) * s;
    }
    function move(delta) {
        if (itemCount === 0) return;
        focusIndex = Math.max(0, Math.min(itemCount - 1, focusIndex + delta));
    }
    function centerOnCurrent() {
        var idx = 0;
        for (var i = 0; i < itemCount; ++i) {
            if (String(wallpapers[i].path || "") === String(themeState.backgroundPath || "")) {
                idx = i;
                break;
            }
        }
        focusIndex = idx;
        pos = idx;
    }
    function clearPending() {
        pendingAction = "";
        pendingArgument = ({});
        pendingLabel = "";
        pendingSlug = "";
    }
    function confirm(action, argument, label) {
        if (themeSource !== null || !systemService || themeState.busy === true) return;
        pendingAction = action;
        pendingArgument = argument || ({});
        pendingLabel = label;
        pendingSlug = String(themeState.slug || "");
    }
    function applyPending() {
        if (themeSource !== null || !pendingAction || !systemService || themeState.busy === true) return;
        systemService.invoke("theme", pendingAction,
            Object.assign({}, pendingArgument, {confirmed: true}));
        clearPending();
    }
    function activate() {
        if (focusIndex < 0 || focusIndex >= itemCount ||
                themeState.canSetBackground !== true || themeState.busy === true || !systemService)
            return;
        var row = wallpapers[focusIndex];
        if (String(row.path || "") === String(themeState.backgroundPath || "")) return;
        confirm("setBackground", {path: String(row.path), slug: String(themeState.slug || "")},
                "Use " + String(row.name || "this background") + " on every display?");
        applyPending();
    }
    // Consumed only when there was a pending confirmation to cancel, so the
    // host knows whether to step back to the theme grid.
    function handleEscape() {
        if (pendingAction) { clearPending(); return true; }
        return false;
    }
    onFocusIndexChanged: {
        if (focusIndex >= itemCount) focusIndex = Math.max(0, itemCount - 1);
    }
    onItemCountChanged: {
        if (itemCount === 0) { focusIndex = 0; pos = 0; }
        else if (focusIndex >= itemCount) focusIndex = itemCount - 1;
    }
    onActiveChanged: {
        clearPending();
        if (active) centerOnCurrent();
    }
    onThemeStateChanged: {
        if (pendingAction && (themeState.busy === true || pendingSlug !== String(themeState.slug || "")))
            clearPending();
    }

    FrameAnimation {
        running: root.active && root.pos !== root.focusIndex
        onTriggered: {
            var k = 1 - Math.exp(-frameTime / 0.07);
            var next = root.pos + (root.focusIndex - root.pos) * k;
            root.pos = Math.abs(next - root.focusIndex) < 0.001 ? root.focusIndex : next;
        }
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
    component HintKey: Row {
        id: hint
        property string key: ""
        property string caption: ""
        spacing: 5 * root.s
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: keyText.implicitWidth + 11 * root.s
            height: keyText.implicitHeight + 6 * root.s
            radius: 5 * root.s
            color: Theme.frameBg
            border.width: 1
            border.color: Theme.hairSoft
            Text {
                id: keyText
                anchors.centerIn: parent
                text: hint.key
                color: Theme.cream
                font.family: Theme.font; font.pixelSize: 8.5 * root.s; font.weight: Font.DemiBold
            }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: hint.caption
            color: Theme.faint
            font.family: Theme.font; font.pixelSize: 9.5 * root.s; font.weight: Font.Medium
        }
    }

    Item {
        id: header
        width: parent.width; height: 28 * root.s
        SectionLabel { anchors.verticalCenter: parent.verticalCenter; text: "BACKGROUNDS" }
        Row {
            anchors.right: parent.right; spacing: 4 * root.s
            ActionButton { text: "Back"; onClicked: root.requestBack() }
            ActionButton {
                objectName: "appearanceNextBackground"
                text: "Next"
                enabled: root.themeState.canNextBackground === true && !root.themeState.busy
                onClicked: root.confirm("nextBackground", null, "Use the next background on every display?")
            }
            ActionButton {
                objectName: "appearanceResync"
                text: "Resync"
                enabled: root.themeState.canResyncWallpaper === true && !root.themeState.busy
                onClicked: root.confirm("resyncWallpaper", null, "Restore the current background on every display?")
            }
            ActionButton { text: "Close"; onClicked: root.requestClose() }
        }
    }
    Rectangle {
        id: divider
        anchors.top: header.bottom; anchors.topMargin: 9 * root.s
        width: parent.width; height: 1; color: Theme.hair
    }

    Repeater {
        model: root.wallpapers
        delegate: Item {
            id: tile
            required property int index
            required property var modelData
            objectName: "wallpaperChoice_" + index
            readonly property real off: index - root.pos
            readonly property real ao: Math.abs(off)
            readonly property bool focused: index === root.focusIndex
            readonly property real bright: root.slotLerp(root.slotBright, ao)
            readonly property real sat: root.slotLerp(root.slotSat, ao)
            readonly property real corner: (8 + 2 * Math.max(0, 1 - ao)) * root.s
            readonly property real edgeFade: {
                var soft = 70 * root.s;
                var gap = Math.min(x, root.width - (x + width));
                return Math.max(0, Math.min(1, gap / soft));
            }
            width: root.slotLerp(root.slotW, ao) * root.s
            height: root.slotLerp(root.slotH, ao) * root.s
            x: root.width / 2 + root.offsetX(off) - width / 2
            y: stripTop.y + (stripTop.height - height) / 2
            z: 10 - ao
            visible: ao <= 5
            opacity: edgeFade * (ao <= 4 ? 1 : Math.max(0, 5 - ao))

            Rectangle {
                id: card
                anchors.fill: parent
                radius: tile.corner
                color: Theme.tileBg
                clip: true
                Image {
                    id: wallpaperImage
                    objectName: "wallpaperImage_" + tile.index
                    anchors.fill: parent
                    source: (tile.modelData.thumb !== undefined && String(tile.modelData.thumb).length > 0)
                        ? String(tile.modelData.thumb) : String(tile.modelData.url || "")
                    sourceSize: Qt.size(384, 384)
                    asynchronous: true
                    cache: true
                    smooth: true
                    fillMode: Image.PreserveAspectCrop
                    visible: status === Image.Ready
                }
                GlyphIcon {
                    anchors.centerIn: parent
                    width: 24 * root.s; height: width
                    name: "palette"; color: Theme.faint
                    visible: wallpaperImage.status !== Image.Ready
                }
                Rectangle {
                    anchors.fill: parent
                    color: Qt.rgba(0, 0, 0, 1)
                    opacity: 1 - tile.bright
                }
            }
            Rectangle {
                anchors.fill: parent
                radius: tile.corner
                color: "transparent"
                border.width: tile.focused ? 2 * root.s : 1
                border.color: tile.focused ? Theme.onGlow : Theme.border
                Behavior on border.color { ColorAnimation { duration: Motion.fast } }
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (!tile.focused) {
                        root.focusIndex = tile.index;
                    } else if (root.themeState.canSetBackground === true && !root.themeState.busy) {
                        var row = tile.modelData;
                        if (String(row.path || "") !== String(root.themeState.backgroundPath || ""))
                            root.confirm("setBackground", {path: String(row.path), slug: String(root.themeState.slug || "")},
                                "Use " + String(row.name || "this background") + " on every display?");
                    }
                }
            }
        }
    }

    Item {
        id: stripTop
        anchors.top: divider.bottom
        anchors.topMargin: 8 * root.s
        anchors.bottom: footer.top
        anchors.bottomMargin: 7 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        clip: true
    }
    // Instantiating only the five nearby cached sources warms Qt's decoded-image
    // cache without ever preloading originals or the whole catalog.
    Repeater {
        model: root.preloadRows
        delegate: Image {
            required property var modelData
            objectName: "wallpaperPreload_" + modelData.index
            x: 0; y: 0; width: 1; height: 1
            opacity: 0
            source: modelData.source
            sourceSize: Qt.size(384, 384)
            asynchronous: true
            cache: true
        }
    }

    Text {
        objectName: "appearanceEmptyWallpapers"
        anchors.centerIn: stripTop
        visible: root.itemCount === 0
        width: stripTop.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        textFormat: Text.PlainText
        text: "This theme has no backgrounds. Add images to its backgrounds folder in mac-themer."
        color: Theme.faint
        font.family: Theme.font; font.pixelSize: 10 * root.s
    }
    Text {
        anchors.left: parent.left; anchors.right: parent.right
        anchors.bottom: footer.top; anchors.bottomMargin: 2 * root.s
        visible: Boolean(root.themeState.lastError)
        text: String(root.themeState.lastError || "")
        textFormat: Text.PlainText; elide: Text.ElideRight
        color: Theme.error; font.family: Theme.font; font.pixelSize: 9 * root.s
    }

    Item {
        id: footer
        anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
        height: 47 * root.s
        Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Theme.hair }
        Text {
            anchors.left: parent.left; anchors.right: actions.left; anchors.rightMargin: 8 * root.s
            anchors.top: parent.top; anchors.topMargin: 5 * root.s
            height: 20 * root.s
            textFormat: Text.PlainText; elide: Text.ElideRight
            text: root.pendingAction ? root.pendingLabel : "Backgrounds apply to every display."
            color: root.pendingAction ? Theme.cream : Theme.faint
            font.family: Theme.font; font.pixelSize: 9 * root.s
        }
        Row {
            id: actions
            anchors.right: parent.right; anchors.top: parent.top; anchors.topMargin: 3 * root.s
            visible: root.pendingAction.length > 0
            spacing: 5 * root.s
            ActionButton { objectName: "appearanceApply"; text: "Apply"; highlighted: true; enabled: !root.themeState.busy; onClicked: root.applyPending() }
            ActionButton { objectName: "appearanceCancel"; text: "Cancel"; onClicked: root.clearPending() }
        }
        Row {
            anchors.left: parent.left; anchors.bottom: parent.bottom; anchors.bottomMargin: 2 * root.s
            spacing: 12 * root.s
            visible: root.itemCount > 0 && !root.pendingAction
            HintKey { key: "←/→"; caption: "select" }
            HintKey { key: "enter"; caption: "apply" }
        }
    }
    MouseArea {
        id: wheelArea
        anchors.fill: stripTop
        z: 30
        acceptedButtons: Qt.NoButton
        property real acc: 0
        onWheel: (event) => {
            acc += event.angleDelta.y / 120;
            const notches = Math.trunc(acc);
            if (notches !== 0) {
                root.move(-notches);
                acc -= notches;
            }
            event.accepted = true;
        }
    }
}
