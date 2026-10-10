import QtQuick
import QtTest
import Quickshell

TestCase {
    name: "QuickshellSubset"
    when: windowShown
    visible: true
    Component {
        id: panelFactory
        PanelWindow {
            implicitWidth: 160
            implicitHeight: 38
            anchors.top: true
            Rectangle { objectName: "panelContent"; width: 12; height: 12 }
        }
    }
    SystemClock { id: clock; precision: SystemClock.Seconds }
    Singleton { id: singleton; property int example: 7; Timer { interval: 10 } }
    function test_panelCreatesRealWindowAndParentsItems() {
        const panel = createTemporaryObject(panelFactory, null)
        verify(panel !== null)
        compare(panel.width, 160)
        compare(panel.height, 38)
        compare(findChild(panel, "panelContent").parent, panel.contentItem)
        compare(panel.anchors.top, true)
        compare(panel.anchors.left, false)
        compare(panel.color, Qt.rgba(0, 0, 0, 0))
    }
    function test_coreUtilities() {
        verify(Quickshell.screens.length > 0)
        verify(clock.date instanceof Date)
        compare(singleton.example, 7)
        compare(singleton.data.length, 1)
    }
    function test_unsupportedAnchorsAreRejected() {
        const panel = createTemporaryObject(panelFactory, null)
        panel.anchors.left = true
        let rejected = false
        try { panel.validate() } catch (error) { rejected = error.message.indexOf("top-anchored") >= 0 }
        verify(rejected)
    }
}
