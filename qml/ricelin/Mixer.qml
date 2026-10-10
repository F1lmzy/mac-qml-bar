import QtQuick
import QtQuick.Controls.Basic
import "Singletons"

// Adapted Ricelin Mixer header and filament-fader layout. No hardware/service
// imports remain. All enabled faders modify only these local preview values.
PillSurface {
    id: root
    objectName: "mixerSurface"
    mTop: 13
    mLeft: 14
    mRight: 14
    mBottom: 12
    property bool tracePreview: false
    property real previewBrightness: 0.7
    property real previewVolume: 0.45
    property real previewMic: 0.6
    property int focusIndex: -1
    // Keyboard navigation deliberately skips the disabled fourth visual column.
    readonly property var faders: [brFader, volFader, micFader]
    signal quitRequested()

    onActiveChanged: focusIndex = active ? 0 : -1
    onFocusIndexChanged: if (tracePreview) console.info("preview-focus", focusIndex)
    onPreviewBrightnessChanged: if (tracePreview) console.info("preview-brightness", previewBrightness)
    onPreviewVolumeChanged: if (tracePreview) console.info("preview-volume", previewVolume)
    onPreviewMicChanged: if (tracePreview) console.info("preview-mic", previewMic)
    function stepFocused(deltaPct) {
        if (focusIndex >= 0) faders[focusIndex].step(deltaPct)
    }
    function moveFocus(dir) {
        focusIndex = focusIndex < 0 ? 0 : (focusIndex + dir + faders.length) % faders.length
    }

    component IconChip: Button {
        id: chip
        property string glyph: ""
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
        ToolTip.text: text
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
                text: "調"
                color: Theme.cream
                font.family: Theme.fontJp
                font.weight: Font.Medium
                font.pixelSize: 16 * root.s
            }
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
                text: "PREVIEW"
                color: Theme.faint
                font.family: Theme.font
                font.pixelSize: 8 * root.s
            }
        }
        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6 * root.s
            IconChip { objectName: "devicePicker"; glyph: "speaker"; text: "Device selection not connected"; enabled: false }
            IconChip { objectName: "dndChip"; glyph: "dnd"; text: "Do not disturb not connected"; enabled: false }
            IconChip { objectName: "awakeChip"; glyph: "awake"; text: "Keep-awake not connected"; enabled: false }
            IconChip { objectName: "nightChip"; glyph: "sun"; text: "Night light not connected"; enabled: false }
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
            value: root.previewBrightness
            valueLabel: Math.round(value * 100) + "%"
            subLabel: "Brightness"
            focused: root.active && root.focusIndex === 0
            onMoved: (v) => root.previewBrightness = v
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
            value: root.previewVolume
            valueLabel: Math.round(value * 100) + "%"
            subLabel: "Volume"
            focused: root.active && root.focusIndex === 1
            onMoved: (v) => root.previewVolume = v
            HoverHandler { onHoveredChanged: if (hovered) root.focusIndex = 1 }
        }
        VFader {
            id: micFader
            objectName: "micFader"
            width: parent.colW
            s: root.s
            icon: "mic"
            value: root.previewMic
            valueLabel: Math.round(value * 100) + "%"
            subLabel: "Mic"
            focused: root.active && root.focusIndex === 2
            onMoved: (v) => root.previewMic = v
            HoverHandler { onHoveredChanged: if (hovered) root.focusIndex = 2 }
        }
    }
}
