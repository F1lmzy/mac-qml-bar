import QtQuick
import Quickshell
import "ricelin"
import "ricelin/Singletons"

// Selected-component port of Gakuseei/Ricelin Pill.qml. See third_party/ricelin
// for source commit, MIT license and the upstream blocks retained here.
Item {
    id: pill
    focus: true
    property real s: Flags.uiScale
    property bool tracePreview: false
    property var audioService: null
    property bool hovered: false
    property bool hoverHeld: false
    property string surface: ""
    readonly property bool expanded: surface === "mixer"
    readonly property string mode: expanded ? "mixer" : hoverHeld ? "hover" : "rest"
    readonly property real restW: 160 * s
    readonly property real restH: 38 * s
    readonly property real hoverPad: 20 * s
    readonly property real hoverH: 58 * s
    readonly property real mixerH: 214 * s
    readonly property real restCorner: 18 * s
    readonly property real openCorner: 22 * s
    readonly property size collapsedSize: Qt.size(restW, restH)
    readonly property size hoverSize: Qt.size(hoverRow.implicitWidth + 2 * hoverPad, hoverH)
    readonly property size mixerSize: Qt.size(93 * 4 * s, mixerH)
    readonly property size targetSize: expanded ? mixerSize : hoverHeld ? hoverSize : collapsedSize
    readonly property real targetW: targetSize.width
    readonly property real targetH: targetSize.height
    readonly property bool morphing: morphAnimW.running || morphAnimH.running || morphAnimR.running
    readonly property bool transitioning: morphing || restFade.running || hoverFade.running
    property real morphRadius: mode === "mixer" ? openCorner : restCorner
    property string lastMode: "rest"
    property bool hoverHop: false
    readonly property real morphCloseness: {
        const d = Math.max(Math.abs(width - targetW), Math.abs(height - targetH))
        return 1 - Math.min(1, d / (110 * s))
    }
    width: targetW
    height: targetH
    signal quitRequested()

    function open() { surface = "mixer"; forceActiveFocus() }
    function dismiss() { surface = ""; hovered = false; hoverHeld = false; leaveDelay.stop() }
    onHoveredChanged: {
        if (hovered) { leaveDelay.stop(); hoverHeld = true }
        else leaveDelay.restart()
    }
    Timer {
        id: leaveDelay
        interval: 180
        onTriggered: if (!pill.hovered) pill.hoverHeld = false
    }
    onModeChanged: {
        hoverHop = (mode === "hover" || mode === "rest") && (lastMode === "hover" || lastMode === "rest")
        lastMode = mode
    }
    Behavior on width {
        NumberAnimation { id: morphAnimW; duration: pill.hoverHop ? Motion.glide : Motion.morph; easing.type: Motion.easeMorph; easing.bezierCurve: Motion.morphCurve }
    }
    Behavior on height {
        NumberAnimation { id: morphAnimH; duration: pill.hoverHop ? Motion.glide : Motion.morph; easing.type: Motion.easeMorph; easing.bezierCurve: Motion.morphCurve }
    }
    Behavior on morphRadius {
        NumberAnimation { id: morphAnimR; duration: pill.hoverHop ? Motion.glide : Motion.morph; easing.type: Motion.easeMorph; easing.bezierCurve: Motion.morphCurve }
    }
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape) { dismiss(); event.accepted = true }
        else if (expanded) {
            if (event.key === Qt.Key_Left) { mixer.moveFocus(-1); event.accepted = true }
            if (event.key === Qt.Key_Right) { mixer.moveFocus(1); event.accepted = true }
            if (event.key === Qt.Key_Up) { mixer.stepFocused(1); event.accepted = true }
            if (event.key === Qt.Key_Down) { mixer.stepFocused(-1); event.accepted = true }
        }
    }

    Rectangle {
        id: body
        anchors.fill: parent
        radius: pill.morphRadius
        border.width: 1
        border.color: Theme.border
        gradient: Gradient {
            GradientStop { position: 0; color: Qt.alpha(Theme.cardTop, Flags.pillOpacity) }
            GradientStop { position: 1; color: Qt.alpha(Theme.cardBot, Flags.pillOpacity) }
        }
        Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.topMargin: 1
            anchors.leftMargin: body.radius * 0.6
            anchors.rightMargin: body.radius * 0.6
            height: 1
            color: Theme.sheen
        }
    }
    SystemClock {
        id: sysClock
        precision: Flags.clockSeconds ? SystemClock.Seconds : SystemClock.Minutes
    }
    QtObject {
        id: clock
        readonly property string hhmm: Qt.formatTime(sysClock.date, Flags.time12h ? "hh:mm AP" : "HH:mm")
        readonly property string date: Qt.locale().toString(sysClock.date, "ddd d MMM")
    }
    Item {
        id: rest
        objectName: "restContent"
        anchors.fill: parent
        opacity: pill.mode === "rest" ? Math.pow(pill.morphCloseness, 1.5) : 0
        visible: opacity > 0.01
        enabled: pill.mode === "rest"
        Behavior on opacity { NumberAnimation { id: restFade; duration: pill.mode === "rest" ? Motion.fast : Math.round(260 * Motion.mult) } }
        Row {
            anchors.centerIn: parent
            spacing: 9 * pill.s
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "時"
                color: Theme.cream
                font.family: Theme.fontJp
                font.weight: Font.Medium
                font.pixelSize: 15 * pill.s
                style: Text.Outline
                styleColor: Qt.alpha(Theme.vermLit, 0.5)
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: clock.hhmm
                color: Theme.cream
                font.family: Theme.font
                font.pixelSize: 16 * pill.s
                font.weight: Font.DemiBold
                font.features: { "tnum": 1 }
            }
        }
        TapHandler { onTapped: pill.open() }
    }
    Item {
        id: hover
        objectName: "hoverContent"
        anchors.fill: parent
        opacity: pill.mode === "hover" ? Math.pow(pill.morphCloseness, 1.2) : 0
        visible: opacity > 0.01
        enabled: pill.mode === "hover"
        Behavior on opacity { NumberAnimation { id: hoverFade; duration: pill.mode === "hover" ? Motion.fast : 40 } }
        Row {
            id: hoverRow
            anchors.centerIn: parent
            spacing: 20 * pill.s
            Workspaces {
                anchors.verticalCenter: parent.verticalCenter
                width: implicitWidth
                height: implicitHeight
                s: pill.s
                gap: 8 * pill.s
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: 22 * pill.s
                color: Theme.hair
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2 * pill.s
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: clock.hhmm
                    color: Theme.cream
                    font.family: Theme.font
                    font.pixelSize: 18 * pill.s
                    font.weight: Font.DemiBold
                    font.features: { "tnum": 1 }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: clock.date
                    color: Theme.dim
                    font.family: Theme.font
                    font.pixelSize: 8.5 * pill.s
                    font.weight: Font.Medium
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1.6 * pill.s
                }
            }
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 1
                height: 22 * pill.s
                color: Theme.hair
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2 * pill.s
                Text { text: DemoState.mediaTitle; color: Theme.subtle; font.family: Theme.font; font.pixelSize: 10 * pill.s }
                Text { text: DemoState.mediaArtist; color: Theme.faint; font.family: Theme.font; font.pixelSize: 8.5 * pill.s }
            }
            GlyphIcon {
                anchors.verticalCenter: parent.verticalCenter
                width: 18 * pill.s
                height: 18 * pill.s
                name: "mixer"
                color: Theme.iconDim
                stroke: 1.7
            }
        }
        TapHandler { onTapped: pill.open() }
    }
    Mixer {
        id: mixer
        s: pill.s
        tracePreview: pill.tracePreview
        audioService: pill.audioService
        open: pill.expanded
        morphCloseness: pill.morphCloseness
        onRequestClose: pill.dismiss()
        onQuitRequested: pill.quitRequested()
    }
}
