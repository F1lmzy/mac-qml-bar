import QtQuick

// Single-primary-screen, bounded top panel only. Native behavior is supplied by
// Host after loading shell.qml; using this type alone does not create a shell.
Window {
    id: panel
    color: "transparent"
    flags: Qt.Tool | Qt.FramelessWindowHint
    property real implicitWidth: 0
    property real implicitHeight: 0
    width: Math.round(implicitWidth)
    height: Math.round(implicitHeight)
    property PanelAnchors anchors: PanelAnchors {}
    function validate() {
        if (!anchors.top || anchors.bottom || anchors.left || anchors.right)
            throw new Error("This macOS subset supports only a top-anchored bounded PanelWindow")
        if (!(implicitWidth > 0 && implicitHeight > 0))
            throw new Error("PanelWindow needs positive implicitWidth and implicitHeight")
        return true
    }
}
