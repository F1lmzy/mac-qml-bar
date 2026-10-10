pragma Singleton
import QtQml

QtObject {
    readonly property var workspaceIds: [1, 2, 3, 4, 5]
    readonly property int activeWorkspace: 2
    readonly property string mediaTitle: "Media preview"
    readonly property string mediaArtist: "Not connected"
}
