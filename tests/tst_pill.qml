import QtQuick
import QtTest
import "../qml"

TestCase {
    name: "PillInteraction"
    when: windowShown
    visible: true
    width: 600
    height: 400
    Pill { id: pill }

    function init() {
        pill.dismiss()
        tryCompare(pill, "width", 250)
        tryCompare(pill, "height", 34)
    }
    function test_hoverMorphsWithoutOpening() {
        pill.hovered = true
        tryCompare(pill, "width", 360)
        tryCompare(pill, "height", 44)
        compare(pill.expanded, false)
    }
    function test_pointerLeavesAndCollapses() {
        pill.hovered = true
        tryCompare(pill, "width", 360)
        pill.hovered = false
        tryCompare(pill, "width", 250)
    }
    function test_clickOpensAndStaysPinned() {
        mouseClick(pill, 125, 17)
        tryCompare(pill, "width", 440)
        tryCompare(pill, "height", 264)
        compare(pill.expanded, true)
        pill.hovered = false
        wait(350)
        compare(pill.expanded, true)
    }
    function test_dismissClearsHoverAndPin() {
        pill.open()
        pill.hovered = true
        pill.dismiss()
        compare(pill.expanded, false)
        compare(pill.hovered, false)
        tryCompare(pill, "width", 250)
    }
    function test_escapeClosesPanel() {
        pill.open()
        pill.forceActiveFocus()
        keyClick(Qt.Key_Escape)
        compare(pill.expanded, false)
    }
    function test_sliderIsDemoOnly() {
        pill.open()
        tryCompare(pill, "height", 264)
        const slider = findChild(pill, "volumeSlider")
        verify(slider !== null)
        slider.value = 0.25
        compare(slider.value, 0.25)
        compare(pill.expanded, true)
    }
}
