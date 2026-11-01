import QtQuick
import QtQuick.Controls.Basic
import "Singletons"

// Adapted Ricelin mixer layout. Brightness, volume and mute use observed
// native state; unsupported mic/vibrance controls stay disabled. With
// no service injected every hardware-backed control stays disabled rather than
// showing a plausible-looking value.
PillSurface {
    id: root
    objectName: "mixerSurface"
    mTop: 13
    mLeft: 14
    mRight: 14
    mBottom: 12
    property bool tracePreview: false
    property var audioService: null
    property var systemService: null
    property real requestedBrightness: NaN
    property string brightnessDisplay: ""
    property string brightnessGestureDisplay: ""
    property bool brightnessGestureCanceled: false
    property int focusIndex: -1
    // Local drag feedback only. The observed device value stays the source of
    // truth, and a queued command never counts as a confirmed write.
    property real requestedVolume: NaN
    property string feedbackDevice: ""
    property string gestureDevice: ""
    property bool volumeGestureCanceled: false

    readonly property var brightnessState: systemService && systemService.brightness ? systemService.brightness : ({})
    readonly property bool brightnessEnabled: brightnessState.available === true && brightnessState.known === true && brightnessState.canSet === true
    readonly property bool volumeReady: audioService !== null && audioService.available && audioService.volumeKnown
    readonly property bool volumeEnabled: volumeReady && audioService.canSetVolume
    readonly property bool muteEnabled: audioService !== null && audioService.available
        && audioService.muteKnown && audioService.canMute
    readonly property real observedVolume: volumeReady ? audioService.volume : 0
    readonly property string volumeLabel: !volumeReady ? "Unavailable"
        : (audioService.canSetVolume ? (audioService.testBackend ? "Volume TEST" : "Volume LIVE") : "Read only")

    // Keyboard navigation deliberately skips the disabled fourth visual column.
    readonly property var faders: [brFader, volFader]
    signal quitRequested()
    signal requestSystem()

    onActiveChanged: {
        focusIndex = active ? 0 : -1
        if (!active) clearFeedback()
    }
    onFocusIndexChanged: if (tracePreview) console.info("preview-focus", focusIndex)
    // Keep the existing input-harness trace key while the observed volume path
    // is exercised; it fires on local feedback, not on a confirmed write.
    onRequestedVolumeChanged: if (tracePreview) console.info("preview-volume", requestedVolume)

    function clearFeedback() {
        requestedVolume = NaN
        feedbackDevice = ""
        requestedBrightness = NaN
        brightnessDisplay = ""
    }
    function moveBrightness(v) {
        if (!brightnessEnabled) return
        if (brFader.pressed && (brightnessGestureCanceled || brightnessGestureDisplay !== String(brightnessState.displayId))) { brightnessGestureCanceled = true; return }
        requestedBrightness = v
        brightnessDisplay = String(brightnessState.displayId)
        if (systemService) systemService.invoke("brightness", "set", {value: v, displayId: brightnessDisplay})
    }
    function reconcileBrightness() {
        if (brFader.pressed && (!brightnessEnabled || brightnessGestureDisplay !== String(brightnessState.displayId))) brightnessGestureCanceled = true
        if (!isNaN(requestedBrightness) && (!brightnessEnabled || brightnessDisplay !== String(brightnessState.displayId)
                || (!brFader.pressed && Math.abs(requestedBrightness - Number(brightnessState.value)) < 0.005))) requestedBrightness = NaN
    }
    function stepFocused(deltaPct) {
        if (focusIndex < 0) return
        const fader = faders[focusIndex]
        if (fader.enabled) fader.step(deltaPct)
    }
    function moveFocus(dir) {
        focusIndex = focusIndex < 0 ? 0 : (focusIndex + dir + faders.length) % faders.length
        for (let n = 0; n < faders.length && !faders[focusIndex].enabled; n++)
            focusIndex = (focusIndex + dir + faders.length) % faders.length
    }
    function onVolumeMoved(v) {
        if (!volumeEnabled) return
        if (volFader.pressed && (volumeGestureCanceled || gestureDevice !== audioService.outputDeviceId)) return
        requestedVolume = v
        feedbackDevice = audioService.outputDeviceId
        audioService.setVolume(v)
    }
    function onVolumeCommitted() {
        reconcileVolume()
        reconcileTimer.restart()
    }
    // Drops stale feedback when the device changes or the write is confirmed.
    function reconcileVolume() {
        if (volFader.pressed && (audioService === null || !volumeEnabled
                || audioService.outputDeviceId !== gestureDevice))
            volumeGestureCanceled = true
        if (isNaN(requestedVolume)) return
        const service = audioService
        if (service === null || !service.available || !service.canSetVolume
                || service.outputDeviceId !== feedbackDevice) {
            clearFeedback()
            return
        }
        if (!volFader.pressed && service.volumeKnown
                && Math.abs(requestedVolume - service.volume) <= 0.005)
            clearFeedback()
    }

    Timer {
        id: reconcileTimer
        interval: 500
        onTriggered: if (!volFader.pressed) root.clearFeedback()
    }
    Connections {
        target: root.audioService
        enabled: root.audioService !== null
        function onStateChanged() {
            if (root.tracePreview && root.audioService.testBackend && !isNaN(root.requestedVolume)
                    && root.audioService.volumeKnown
                    && Math.abs(root.requestedVolume - root.audioService.volume) <= 0.005)
                console.info("test-audio-confirmed", root.audioService.volume)
            root.reconcileVolume()
        }
        function onErrorOccurred(operation, code, message) { root.clearFeedback() }
    }
    Connections {
        target: root.systemService
        enabled: root.systemService !== null
        function onStateChanged() { root.reconcileBrightness() }
        function onErrorOccurred(domain, operation, code, message) {
            if (domain === "brightness") { root.requestedBrightness = NaN; root.brightnessGestureCanceled = brFader.pressed }
        }
    }

    component IconChip: Button {
        id: chip
        property string glyph: ""
        property string tooltip: text
        width: 26 * root.s
        height: 26 * root.s
        opacity: enabled ? 1 : 0.35
        Accessible.name: text
        background: Rectangle {
            radius: 8 * root.s
            color: chip.hovered || chip.activeFocus ? Theme.frameBg : "transparent"
            border.width: 1
            border.color: chip.activeFocus ? Theme.onGlow : Theme.border
        }
        contentItem: GlyphIcon {
            name: chip.glyph
            color: Theme.iconDim
            stroke: 1.7
        }
        ToolTip.visible: hovered
        ToolTip.text: chip.tooltip
    }

    Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 24 * root.s
        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8 * root.s
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "MIXER"
                color: Theme.subtle
                font.family: Theme.font
                font.pixelSize: 10 * root.s
                font.weight: Font.DemiBold
                font.letterSpacing: 1.6 * root.s
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: !root.audioService && !root.systemService ? "UNAVAILABLE" : (root.audioService && root.audioService.testBackend ? "TEST" : "NATIVE")
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 8 * root.s
            }
        }
        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6 * root.s
            IconChip {
                objectName: "muteChip"
                glyph: root.audioService !== null && root.audioService.muted ? "speaker-off" : "speaker"
                text: root.muteEnabled
                    ? (root.audioService.muted ? "Unmute output" : "Mute output")
                    : "Mute not available"
                tooltip: root.audioService !== null && root.audioService.lastError.length > 0
                    ? root.audioService.lastError : text
                enabled: root.muteEnabled
                onClicked: if (root.audioService) root.audioService.setMuted(!root.audioService.muted)
            }
            IconChip { objectName: "devicePicker"; glyph: "speaker"; text: "System controls"; enabled: root.systemService !== null; onClicked: root.requestSystem() }
            IconChip { objectName: "dndChip"; glyph: "dnd"; text: "Do not disturb not connected"; enabled: false }
            IconChip { objectName: "awakeChip"; glyph: "awake"; text: "Keep-awake not connected"; enabled: false }
            IconChip { objectName: "nightChip"; glyph: "sun"; text: root.systemService && root.systemService.display && root.systemService.display.nightShiftKnown ? "Toggle Night Shift" : "Night Shift unavailable"; enabled: root.systemService !== null && root.systemService.display && root.systemService.display.nightShiftKnown === true && root.systemService.display.canSetNightShift === true; onClicked: root.systemService.invoke("display", "setNightShift", !root.systemService.display.nightShiftEnabled) }
            IconChip { glyph: "close"; text: "Close mixer"; onClicked: root.requestClose() }
            IconChip { glyph: "logout"; text: "Quit pill"; onClicked: root.quitRequested() }
        }
    }
    Rectangle {
        id: divider
        anchors.top: header.bottom
        anchors.topMargin: 9 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        height: 1
        color: Theme.hair
    }
    Row {
        anchors.top: divider.bottom
        anchors.topMargin: 10 * root.s
        anchors.left: parent.left
        anchors.right: parent.right
        height: 142 * root.s
        readonly property real colW: width / 4
        VFader {
            id: brFader
            objectName: "brightnessFader"
            width: parent.colW
            s: root.s
            icon: "sun"
            enabled: root.brightnessEnabled
            opacity: enabled ? 1 : 0.35
            value: !isNaN(root.requestedBrightness) ? root.requestedBrightness : (root.brightnessState.known ? root.brightnessState.value : 0)
            valueLabel: root.brightnessState.known ? Math.round(value * 100) + "%" : "--"
            subLabel: root.brightnessEnabled ? "Brightness" : "Unavailable"
            focused: root.active && root.focusIndex === 0
            onGestureStarted: { root.brightnessGestureDisplay = String(root.brightnessState.displayId || ""); root.brightnessGestureCanceled = false }
            onMoved: (v) => root.moveBrightness(v)
            onCommitted: { root.reconcileBrightness(); root.brightnessGestureDisplay = "" }
            HoverHandler { onHoveredChanged: if (hovered) root.focusIndex = 0 }
        }
        VFader {
            objectName: "vibranceFader"
            width: parent.colW
            s: root.s
            icon: "palette"
            subLabel: "Linux only"
            opacity: 0.35
            enabled: false
        }
        VFader {
            id: volFader
            objectName: "volumeFader"
            width: parent.colW
            s: root.s
            icon: "speaker"
            enabled: root.volumeEnabled
            opacity: root.volumeEnabled ? 1 : 0.35
            value: isNaN(root.requestedVolume) ? root.observedVolume : root.requestedVolume
            valueLabel: root.volumeReady ? Math.round(value * 100) + "%" : "--"
            subLabel: root.volumeLabel
            focused: root.active && root.focusIndex === 1
            onGestureStarted: {
                root.gestureDevice = root.audioService ? root.audioService.outputDeviceId : ""
                root.volumeGestureCanceled = false
            }
            onMoved: (v) => root.onVolumeMoved(v)
            onCommitted: root.onVolumeCommitted()
            HoverHandler { id: volHover; onHoveredChanged: if (hovered) root.focusIndex = 1 }
            ToolTip.visible: volHover.hovered && root.audioService !== null && root.audioService.lastError.length > 0
            ToolTip.text: root.audioService !== null ? root.audioService.lastError : ""
        }
        VFader {
            id: micFader
            objectName: "micFader"
            width: parent.colW
            s: root.s
            icon: "mic"
            value: 0
            valueLabel: "--"
            subLabel: "Mic unavailable"
            opacity: 0.35
            enabled: false
            focused: false
        }
    }
}
