pragma Singleton
import QtQuick

QtObject {
    readonly property var screens: Qt.application.screens
}
