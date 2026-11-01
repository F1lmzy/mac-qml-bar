import QtQuick
import QtQuick.Controls
import "Singletons"

ScrollView {
    id: root
    objectName: "launcherPreview"
    property var blocks: []
    property bool loading: false
    property real s: 1
    clip: true
    contentWidth: availableWidth
    Accessible.name: "Selected result preview"
    function textFor(block) {
        const fallback = String(block.fallbackText || "Preview unavailable")
        if (block.type === "text") return String(block.text || fallback)
        if (block.type === "value") return String(block.label || "") + "\n" + String(block.value || fallback)
        if (block.type === "metadata") {
            const entries = (block.entries || []).slice(0, 32)
            return entries.length ? entries.map(entry => String(entry.label) + ": " + String(entry.value)).join("\n") : fallback
        }
        return fallback
    }
    Column {
        width: root.availableWidth
        spacing: 6 * root.s
        Text {
            visible: root.loading
            text: "Loading preview…"
            textFormat: Text.PlainText
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: 11 * root.s
        }
        Repeater {
            model: root.blocks.slice(0, 32)
            delegate: Column {
                required property var modelData
                width: root.availableWidth
                spacing: 4 * root.s
                Text {
                    width: parent.width
                    text: root.textFor(modelData).slice(0, 16384)
                    textFormat: Text.PlainText
                    wrapMode: Text.Wrap
                    color: Theme.cream
                    font.family: Theme.font
                    font.pixelSize: 11 * root.s
                }
                Flow {
                    width: parent.width
                    spacing: 4 * root.s
                    visible: modelData.type === "colorPalette"
                    Repeater {
                        model: (modelData.colors || []).slice(0, 32)
                        delegate: Rectangle {
                            required property var modelData
                            readonly property bool valid: /^#[0-9a-fA-F]{6}$/.test(String(modelData.value))
                            width: 20 * root.s
                            height: 20 * root.s
                            visible: valid
                            color: valid ? modelData.value : "transparent"
                            Accessible.name: String(modelData.role || "Color") + " " + String(modelData.value)
                        }
                    }
                }
                Image {
                    width: 64 * root.s
                    height: 64 * root.s
                    visible: modelData.type === "image" && String(modelData.source || "").startsWith("image://maccer-icons/")
                    source: visible ? modelData.source : ""
                    fillMode: Image.PreserveAspectFit
                    Accessible.name: String(modelData.alt || modelData.fallbackText || "Preview image")
                }
            }
        }
    }
}
