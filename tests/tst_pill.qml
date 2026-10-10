import QtQuick
import QtTest
import "../qml"
import "../qml/ricelin/Singletons"

TestCase {
    name: "RicelinInteraction"
    when: windowShown
    visible: true
    width: 800
    height: 500
    Pill { id: pill }
    function settled(size) {
        tryCompare(pill, "width", size.width)
        tryCompare(pill, "height", size.height)
    }
    function init() {
        pill.dismiss()
        settled(pill.collapsedSize)
    }
    function test_sourceGeometryAndMotion() {
        compare(pill.width, 160)
        compare(pill.height, 38)
        compare(pill.mixerSize, Qt.size(372, 214))
        compare(pill.morphRadius, 18)
        compare(Motion.glide, 260)
        compare(Motion.morph, 420)
        compare(Motion.morphCurve, [0.16, 1, 0.3, 1, 1, 1])
    }
    function test_hoverAndLeave() {
        pill.hovered = true
        settled(pill.hoverSize)
        compare(pill.height, 58)
        tryCompare(findChild(pill, "hoverContent"), "opacity", 1)
        compare(pill.expanded, false)
        pill.hovered = false
        settled(pill.collapsedSize)
    }
    function test_clickPinsMixer() {
        mouseClick(pill, 80, 19)
        settled(pill.mixerSize)
        compare(pill.expanded, true)
        pill.hovered = false
        wait(500)
        compare(pill.expanded, true)
    }
    function test_dismissAndEscape() {
        pill.open()
        pill.hovered = true
        pill.dismiss()
        compare(pill.expanded, false)
        compare(pill.hovered, false)
        settled(pill.collapsedSize)
        pill.open()
        pill.forceActiveFocus()
        keyClick(Qt.Key_Escape)
        compare(pill.expanded, false)
    }
    function test_previewFadersAndClamping() {
        pill.open()
        settled(pill.mixerSize)
        const volume = findChild(pill, "volumeFader")
        verify(volume !== null)
        const previous = volume.value
        volume.step(10)
        fuzzyCompare(volume.value, Math.min(1, previous + 0.1), 0.001)
        volume.step(200)
        compare(volume.value, 1)
        volume.step(-200)
        compare(volume.value, 0)
        compare(pill.expanded, true)
    }
    function test_unavailableActionsAreDisabled() {
        pill.open()
        settled(pill.mixerSize)
        for (const name of ["vibranceFader", "devicePicker", "dndChip", "awakeChip", "nightChip"])
            compare(findChild(pill, name).enabled, false, name)
    }
    function test_sourceThemeAndPlaceholders() {
        compare(Theme.cream, Qt.color("#e6d6cb"))
        compare(Theme.vermLit, Qt.color("#e0563b"))
        compare(Theme.dyn, false)
        compare(DemoState.workspaceIds, [1, 2, 3, 4, 5])
        compare(DemoState.mediaTitle, "Media preview")
    }
    function test_keyboardAdjustsPreviewOnly() {
        pill.open()
        settled(pill.mixerSize)
        pill.forceActiveFocus()
        const volume = findChild(pill, "volumeFader")
        const mixer = findChild(pill, "mixerSurface")
        mixer.focusIndex = 1
        const previous = volume.value
        keyClick(Qt.Key_Up)
        fuzzyCompare(volume.value, Math.min(1, previous + 0.01), 0.001)
    }
}
