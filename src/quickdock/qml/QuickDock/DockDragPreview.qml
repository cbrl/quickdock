pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window

// Frameless, input-transparent window that follows the pointer while a docked
// dock is dragged. It shows the dragPreviewDelegate, which gets a captured
// image of the drag source once one is available.
Window {
    id: root

    required property DockWorkspace workspace
    property string dockId: ""
    property url snapshotSource: ""
    property var _grabResult: null
    property int _generation: 0

    objectName: "dockDragPreview"
    flags: Qt.ToolTip | Qt.FramelessWindowHint | Qt.WindowTransparentForInput
           | Qt.WindowStaysOnTopHint | Qt.NoDropShadowWindowHint
    transientParent: workspace.Window.window
    color: "transparent"
    opacity: workspace.style.dragPreview.opacity
    visible: false

    function showPreview(nextDockId, source, rect) {
        dockId = nextDockId
        snapshotSource = ""
        _grabResult = null
        const generation = ++_generation
        setGeometry(Math.round(rect.x), Math.round(rect.y),
                    Math.max(1, Math.round(rect.width)), Math.max(1, Math.round(rect.height)))
        visible = true
        if (!source)
            return
        source.grabToImage(result => {
            if (root.visible && generation === root._generation) {
                root._grabResult = result
                root.snapshotSource = result.url
            }
        }, Qt.size(width, height))
    }

    function movePreview(x, y) {
        if (visible) {
            root.x = Math.round(x)
            root.y = Math.round(y)
        }
    }

    function hidePreview() {
        ++_generation
        visible = false
        snapshotSource = ""
        _grabResult = null
        dockId = ""
    }

    DockDelegateHost {
        anchors.fill: parent
        delegate: root.workspace.dragPreviewDelegate
        context: QtObject {
            readonly property DockWorkspace workspace: root.workspace
            readonly property DockStyle style: root.workspace.style
            readonly property DockItem dock: root.workspace.dockById(root.dockId)
            readonly property string dockId: root.dockId
            readonly property url snapshotSource: root.snapshotSource
        }
    }
}
