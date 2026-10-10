import QtQuick
import QtQuick.Controls.Basic

Item {
    id: pill
    property bool hovered: false
    property bool expanded: false
    property bool hoverHeld: false
    property string clock: Qt.formatTime(new Date(), "hh:mm")
    readonly property color cream: "#f2e7d3"
    readonly property color dim: "#baa99c"
    readonly property color accent: "#df765b"
    readonly property bool showingMore: expanded || hoverHeld
    signal quitRequested()

    width: expanded ? 440 : (hoverHeld ? 360 : 250)
    height: expanded ? 264 : (hoverHeld ? 44 : 34)
    focus: true

    function open() { expanded = true; forceActiveFocus() }
    function toggle() { if (expanded) dismiss(); else open() }
    function dismiss() {
        expanded = false
        hovered = false
        hoverHeld = false
        leaveDelay.stop()
    }

    onHoveredChanged: {
        if (hovered) { leaveDelay.stop(); hoverHeld = true }
        else leaveDelay.restart()
    }
    Timer { id: leaveDelay; interval: 180; onTriggered: pill.hoverHeld = false }
    Timer {
        interval: 1000; running: true; repeat: true
        onTriggered: pill.clock = Qt.formatTime(new Date(), "hh:mm")
    }
    Behavior on width { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
    Behavior on height { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
    Keys.onEscapePressed: event => { dismiss(); event.accepted = true }

    Rectangle {
        anchors.fill: parent
        radius: Math.min(20, height / 2)
        color: "#25201d"
        border.color: "#524038"
        border.width: 1
        clip: true

        Item {
            id: header
            width: parent.width
            height: pill.expanded ? 48 : pill.height
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: pill.toggle()
                Accessible.role: Accessible.Button
                Accessible.name: pill.expanded ? "Close mixer" : "Open mixer"
                Accessible.onPressAction: pill.toggle()
            }
            Row {
                anchors.left: parent.left; anchors.leftMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6
                visible: !pill.expanded
                Repeater {
                    model: 4
                    Rectangle {
                        required property int index
                        width: index === 0 ? 16 : 5
                        height: 5; radius: 3
                        color: index === 0 ? pill.accent : "#766053"
                    }
                }
            }
            Text {
                anchors.left: parent.left; anchors.leftMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                visible: pill.expanded
                text: "MIXER"; color: pill.dim
                font.family: "Helvetica Neue"; font.pixelSize: 11; font.letterSpacing: 1.8
            }
            Text {
                anchors.centerIn: parent
                text: pill.clock; color: pill.cream
                font.family: "Helvetica Neue"; font.pixelSize: 13
                font.weight: Font.Medium
            }
            Text {
                anchors.right: parent.right; anchors.rightMargin: 18
                anchors.verticalCenter: parent.verticalCenter
                visible: !pill.expanded
                text: pill.hoverHeld ? "DEMO  ·  72%" : "72%"
                color: pill.dim; font.family: "Helvetica Neue"; font.pixelSize: 10
            }
            Button {
                anchors.right: parent.right; anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                width: 28; height: 28
                visible: pill.expanded
                text: "×"
                Accessible.name: "Close mixer"
                onClicked: pill.dismiss()
                background: Rectangle { radius: 14; color: parent.hovered ? "#44342d" : "transparent" }
                contentItem: Text { text: parent.text; color: pill.cream; font.pixelSize: 19; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
            }
        }

        Column {
            x: 20; y: 48; width: 400
            spacing: 12
            opacity: pill.expanded && pill.height > 160 ? 1 : 0
            enabled: pill.expanded
            visible: opacity > 0
            Behavior on opacity { NumberAnimation { duration: 180 } }

            Rectangle { width: parent.width; height: 1; color: "#49372f" }
            Row {
                width: parent.width; spacing: 24
                Repeater {
                    model: [
                        { label: "VOLUME", value: 0.72 },
                        { label: "BRIGHTNESS", value: 0.60 },
                        { label: "MICROPHONE", value: 0.40 }
                    ]
                    Column {
                        required property var modelData
                        required property int index
                        width: 117; spacing: 4
                        Slider {
                            objectName: index === 0 ? "volumeSlider" : ""
                            id: fader
                            anchors.horizontalCenter: parent.horizontalCenter
                            orientation: Qt.Vertical
                            width: 28; height: 102
                            from: 0; to: 1; value: modelData.value
                            Accessible.name: modelData.label + " demo slider"
                            background: Rectangle {
                                x: fader.leftPadding + (fader.availableWidth - width) / 2
                                y: fader.topPadding; width: 2; height: fader.availableHeight
                                color: "#715447"; radius: 1
                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: 2; height: fader.position * parent.height
                                    color: pill.accent
                                }
                            }
                            handle: Rectangle {
                                x: fader.leftPadding + (fader.availableWidth - width) / 2
                                y: fader.topPadding + fader.visualPosition * (fader.availableHeight - height)
                                width: 18; height: 4; radius: 2
                                color: fader.pressed ? pill.cream : pill.accent
                            }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Math.round(fader.value * 100) + "%"
                            color: pill.cream; font.pixelSize: 12
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.label; color: pill.dim
                            font.pixelSize: 9; font.letterSpacing: 0.8
                        }
                    }
                }
            }
            Row {
                width: parent.width; spacing: 12
                Text {
                    width: 330; height: 28; verticalAlignment: Text.AlignVCenter
                    text: "Demo controls · no system changes"
                    color: pill.dim; font.pixelSize: 10
                }
                Button {
                    width: 58; height: 28; text: "Quit"
                    onClicked: pill.quitRequested()
                    background: Rectangle { radius: 6; color: parent.hovered ? "#5c4033" : "#3a2c25"; border.color: "#664637" }
                    contentItem: Text { text: parent.text; color: pill.cream; font.pixelSize: 11; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                }
            }
        }
    }
}
