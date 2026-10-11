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

    // Standalone Audio contract double. It mirrors the Pill.MacOS.Audio surface
    // without importing the native module, so these tests never touch hardware.
    QtObject {
        id: audio
        property bool available: true
        property string outputDeviceId: "10"
        property bool volumeKnown: true
        property real volume: 0.45
        property bool muteKnown: true
        property bool muted: false
        property bool canSetVolume: true
        property bool canMute: true
        property string lastErrorCode: ""
        property string lastError: ""
        property bool testBackend: true
        property bool deferWrites: false
        property int volumeWrites: 0
        property int muteWrites: 0
        signal stateChanged()
        signal errorOccurred(string operation, string code, string message)
        function setVolume(v) {
            volumeWrites += 1
            if (!deferWrites) {
                volume = Math.max(0, Math.min(1, v))
                stateChanged()
            }
        }
        function setMuted(m) {
            muteWrites += 1
            muted = m
            stateChanged()
        }
        function reset() {
            available = true
            outputDeviceId = "10"
            volumeKnown = true
            volume = 0.45
            muteKnown = true
            muted = false
            canSetVolume = true
            canMute = true
            lastErrorCode = ""
            lastError = ""
            testBackend = true
            deferWrites = false
            volumeWrites = 0
            muteWrites = 0
            stateChanged()
        }
    }

    Pill { id: pill; audioService: audio }

    function settled(size) {
        tryCompare(pill, "width", size.width)
        tryCompare(pill, "height", size.height)
    }
    function init() {
        pill.audioService = audio
        audio.reset()
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
    function test_liveVolumeFaderAndClamping() {
        pill.open()
        settled(pill.mixerSize)
        const volume = findChild(pill, "volumeFader")
        verify(volume !== null)
        compare(volume.enabled, true)
        fuzzyCompare(volume.value, 0.45, 0.001)
        volume.step(10)
        fuzzyCompare(volume.value, 0.55, 0.001)
        fuzzyCompare(audio.volume, 0.55, 0.001)
        volume.step(200)
        compare(volume.value, 1)
        volume.step(-200)
        compare(volume.value, 0)
        compare(audio.volumeWrites, 3)
        compare(pill.expanded, true)
    }
    function test_volumeCapabilityGating() {
        pill.open()
        settled(pill.mixerSize)
        const volume = findChild(pill, "volumeFader")
        audio.canSetVolume = false
        audio.stateChanged()
        compare(volume.enabled, false)
        compare(volume.subLabel, "Read only")
        volume.step(50)
        compare(audio.volumeWrites, 0)
        fuzzyCompare(audio.volume, 0.45, 0.001)
    }
    function test_externalVolumeChangeDoesNotWrite() {
        pill.open()
        settled(pill.mixerSize)
        const volume = findChild(pill, "volumeFader")
        audio.volume = 0.9
        audio.stateChanged()
        compare(audio.volumeWrites, 0)
        fuzzyCompare(volume.value, 0.9, 0.001)
    }
    function test_dragFeedbackReconcilesOnConfirmation() {
        pill.open()
        settled(pill.mixerSize)
        const mixer = findChild(pill, "mixerSurface")
        const volume = findChild(pill, "volumeFader")
        audio.deferWrites = true
        mixer.onVolumeMoved(0.72)
        compare(audio.volumeWrites, 1)
        fuzzyCompare(volume.value, 0.72, 0.001)
        // A confirmed observation for the same device clears local feedback.
        audio.volume = 0.72
        audio.stateChanged()
        verify(isNaN(mixer.requestedVolume))
        // A device change drops stale feedback instead of showing it on the new output.
        mixer.onVolumeMoved(0.8)
        audio.outputDeviceId = "11"
        audio.stateChanged()
        verify(isNaN(mixer.requestedVolume))
    }
    function test_deviceChangeCancelsRemainingDrag() {
        pill.open()
        settled(pill.mixerSize)
        const volume = findChild(pill, "volumeFader")
        mousePress(volume, volume.width / 2, 30)
        compare(volume.pressed, true)
        const pressWrites = audio.volumeWrites
        mouseMove(volume, volume.width / 2, 50)
        verify(audio.volumeWrites > pressWrites) // Positive control for the move path.
        const writes = audio.volumeWrites
        audio.outputDeviceId = "20"
        audio.stateChanged()
        mouseMove(volume, volume.width / 2, 65)
        compare(audio.volumeWrites, writes)
        mouseRelease(volume, volume.width / 2, 65)
        mouseClick(volume, volume.width / 2, 30)
        verify(audio.volumeWrites > writes)
    }
    function test_muteChipTogglesThroughService() {
        pill.open()
        settled(pill.mixerSize)
        const mute = findChild(pill, "muteChip")
        verify(mute !== null)
        compare(mute.enabled, true)
        compare(audio.muted, false)
        mouseClick(mute, mute.width / 2, mute.height / 2)
        compare(audio.muteWrites, 1)
        compare(audio.muted, true)
        mouseClick(mute, mute.width / 2, mute.height / 2)
        compare(audio.muteWrites, 2)
        compare(audio.muted, false)
    }
    function test_unavailableOutputDisablesVolumeAndMute() {
        pill.open()
        settled(pill.mixerSize)
        audio.available = false
        audio.stateChanged()
        const volume = findChild(pill, "volumeFader")
        compare(volume.enabled, false)
        compare(volume.subLabel, "Unavailable")
        compare(findChild(pill, "muteChip").enabled, false)
        volume.step(10)
        compare(audio.volumeWrites, 0)
    }
    function test_nullServiceKeepsControlsDisabled() {
        pill.audioService = null
        pill.open()
        settled(pill.mixerSize)
        const volume = findChild(pill, "volumeFader")
        compare(volume.enabled, false)
        compare(volume.subLabel, "Unavailable")
        compare(findChild(pill, "muteChip").enabled, false)
    }
    function test_unavailableActionsAreDisabled() {
        pill.open()
        settled(pill.mixerSize)
        for (const name of ["vibranceFader", "devicePicker", "dndChip", "awakeChip", "nightChip"])
            compare(findChild(pill, name).enabled, false, name)
    }
    function test_sourceThemeAndUnavailableSystemState() {
        compare(Theme.cream, Qt.color("#e6d6cb"))
        compare(Theme.vermLit, Qt.color("#e0563b"))
        compare(Theme.dyn, false)
        pill.systemService = null
        compare(pill.mapValue(pill.systemService, "windowManager").workspaces, undefined)
        compare(pill.mapValue(pill.systemService, "spotify").title, undefined)
    }
    function test_keyboardAdjustsVolume() {
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
