// Adapted from Ricelin SearchField.qml. See third_party/ricelin/SOURCE.md.
import QtQuick
import QtQuick.Controls
import "Singletons"

Item {
    id: root

    property real s: 1
    property string placeholder: ""
    property string counterText: ""

    /**
     * Map Left/Right to the moved() signal instead of text-cursor motion. For a
     * horizontal result strip the arrows should page the strip; without this the
     * field swallows them until the caret sits at a text boundary, so navigation
     * stalls mid-query.
     */
    property bool horizontalNav: false
    property string inputObjectName: ""
    readonly property alias input: field
    property alias text: field.text
    default property alias rightContent: rightSlot.data

    signal moved(int delta)
    signal accepted()
    signal dismissed()
    signal keyPressed(var event)

    height: 30 * s

    TextField {
        id: field
        objectName: root.inputObjectName
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: counter.left
        anchors.rightMargin: 10 * root.s
        background: null
        padding: 0
        color: Theme.cream
        font.family: Theme.font
        font.pixelSize: 15 * root.s
        placeholderText: root.placeholder
        placeholderTextColor: Theme.faint
        selectByMouse: true
        selectionColor: Theme.selectionBg
        selectedTextColor: Theme.selectionText
        Keys.onPressed: (e) => {
            // Composition owns Return/arrows until the IME commits its text.
            if (field.inputMethodComposing) { e.accepted = false; return; }
            e.accepted = false;
            root.keyPressed(e);
            if (e.accepted)
                return;
            if (e.key === Qt.Key_Up || e.key === Qt.Key_Down) {
                root.moved(e.key === Qt.Key_Up ? -1 : 1);
                e.accepted = true;
            } else if (root.horizontalNav && (e.key === Qt.Key_Left || e.key === Qt.Key_Right)) {
                root.moved(e.key === Qt.Key_Right ? 1 : -1);
                e.accepted = true;
            } else if (e.key === Qt.Key_Return || e.key === Qt.Key_Enter) {
                root.accepted();
                e.accepted = true;
            } else if (e.key === Qt.Key_Escape) {
                root.dismissed();
                e.accepted = true;
            }
        }
    }

    Rectangle {
        anchors.left: field.left
        anchors.right: field.right
        anchors.top: field.bottom
        anchors.topMargin: 2 * root.s
        height: 1
        color: Theme.faint
        opacity: field.activeFocus ? 0.7 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.standard; easing.type: Motion.easeStandard } }
    }

    Text {
        id: counter
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: rightSlot.left
        anchors.rightMargin: rightSlot.width > 0 ? 10 * root.s : 0
        text: root.counterText
        color: Theme.faint
        font.family: Theme.font
        font.pixelSize: 10.5 * root.s
        font.features: { "tnum": 1 }
    }

    Item {
        id: rightSlot
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        width: childrenRect.width
        height: parent.height
    }
}
