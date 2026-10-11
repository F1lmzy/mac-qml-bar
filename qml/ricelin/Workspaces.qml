pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "Singletons"

Item {
    id: workspaces
    objectName: "workspaces"
    property var systemService: null
    property real s: 1
    property real gap: 5 * s
    property string focusedWorkspace: ""
    readonly property var rows: systemService && systemService.windowManager && systemService.windowManager.workspaces
        ? systemService.windowManager.workspaces : []
    readonly property int shownCount: Math.min(8, rows.length)
    implicitWidth: row.implicitWidth
    implicitHeight: 22 * s
    signal workspaceRequested(string id)
    Row {
        id: row
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: workspaces.gap
        Repeater {
            model: workspaces.shownCount
            delegate: Rectangle {
                required property int index
                readonly property var workspace: workspaces.rows[index]
                readonly property string workspaceId: String(workspace.id || "")
                objectName: "workspaceDot_" + workspaceId
                readonly property bool focused: workspaceId === workspaces.focusedWorkspace
                width: focused ? 16 * workspaces.s : 6 * workspaces.s
                height: 6 * workspaces.s
                radius: height / 2
                color: focused ? Theme.vermLit : Theme.cream
                opacity: focused ? 1 : workspace.visible ? 0.72 : Number(workspace.windowCount || 0) > 0 ? 0.48 : 0.22
                Accessible.name: workspaceId + (focused ? ", focused" : workspace.visible ? ", visible" : "")
                ToolTip.visible: area.containsMouse
                ToolTip.text: workspaceId + (workspace.visible ? " · visible" : "")
                    + (Number(workspace.windowCount || 0) > 0 ? " · occupied" : " · empty")
                Behavior on width { NumberAnimation { duration: Motion.fast; easing.type: Motion.easeStandard } }
                MouseArea {
                    id: area
                    anchors.fill: parent
                    anchors.margins: -5 * workspaces.s
                    hoverEnabled: true
                    enabled: workspaces.systemService !== null && workspaces.systemService.windowManager
                        && workspaces.systemService.windowManager.canSwitch === true
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: workspaces.workspaceRequested(workspaceId)
                }
            }
        }
        Text {
            visible: workspaces.rows.length > 8
            text: "+" + (workspaces.rows.length - 8)
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 9 * workspaces.s
        }
    }
}
