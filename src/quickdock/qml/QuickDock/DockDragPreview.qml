pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window

// Borderless window with input passthrough used while a dock is dragged from the
// main canvas. It shows a captured image when available and a styled fallback.
Window {
    id: root

    required property DockWorkspace workspace
    property string dockId: ""
    // Named `dockTitle` rather than `title` so it does not shadow the
    // inherited Window.title, which would retitle the native preview window.
    property string dockTitle: ""
    property url iconSource: ""
    property url snapshotSource: ""
    property var _grabResult: null
    property int _captureGeneration: 0
    objectName: "dockDragPreview"

    flags: Qt.ToolTip
           | Qt.FramelessWindowHint
           | Qt.WindowTransparentForInput
           | Qt.WindowStaysOnTopHint
           | Qt.NoDropShadowWindowHint
    transientParent: workspace.Window.window
    color: "transparent"
    opacity: workspace.style.drag.preview.opacity
    visible: false

    // The style-provided delegate receives the same dock metadata as a tab.
    Loader {
        anchors.fill: parent
        sourceComponent: root.workspace.dragPreviewDelegate
        property DockWorkspace workspace: root.workspace
        property DockStyle style: root.workspace.style
        property string dockId: root.dockId
        property string title: root.dockTitle
        property url iconSource: root.iconSource
        property url snapshotSource: root.snapshotSource
    }

    // Capture the source after showing the window so the preview remains
    // responsive even when image grabbing is unsupported by the source item.
    function showPreview(nextDockId, sourceItem, geometry) {
        const item = workspace.dockById(nextDockId)
        dockId = nextDockId
        dockTitle = item ? item.title : nextDockId
        iconSource = item ? item.icon : ""
        snapshotSource = ""
        _grabResult = null
        _captureGeneration += 1
        const generation = _captureGeneration

        setGeometry(
            Math.round(geometry.x),
            Math.round(geometry.y),
            Math.max(1, Math.round(geometry.width)),
            Math.max(1, Math.round(geometry.height))
        )

        visible = true
        if (!sourceItem || typeof sourceItem.grabToImage !== "function")
            return

        sourceItem.grabToImage(
            result => {
                if (root.visible && generation === root._captureGeneration) {
                    root._grabResult = result
                    root.snapshotSource = result.url
                }
            },
            Qt.size(width, height)
        )
    }

    function movePreview(nextX, nextY) {
        if (!visible)
            return
        x = Math.round(nextX)
        y = Math.round(nextY)
    }

    function hidePreview() {
        _captureGeneration += 1
        visible = false
        snapshotSource = ""
        _grabResult = null
        dockId = ""
        dockTitle = ""
        iconSource = ""
    }
}
