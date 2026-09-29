pragma ComponentBehavior: Bound

import QtQuick

// Turns an item into a drag handle for docking. Put it over the draggable
// part of a custom header, tab, or title bar.
//
// With `dockId`, a drag moves that dock and a preview follows the pointer;
// releasing over a drop target docks it there and releasing anywhere else
// floats it. With `containerId`, a drag moves that floating container's
// window, which docks the whole container when released over a target. A tap
// activates `dockId`, and a double tap maximizes or restores the window of
// `containerId`.
Item {
    id: root

    property DockWorkspace workspace: null
    property string dockId: ""
    property string containerId: ""
    // The item the drag preview shows. Defaults to the dock's tab group.
    property Item source: null
    readonly property bool dragging: _dragging

    property bool _dragging: false

    function _global(position) {
        return mapToGlobal(position.x, position.y)
    }

    HoverHandler {
        cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
    }

    TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: {
            if (root.workspace && root.dockId)
                root.workspace.activateDock(root.dockId)
        }
        onDoubleTapped: {
            const window = root.workspace ? root.workspace._windowForContainer(root.containerId) : null
            if (window)
                window.toggleMaximized()
        }
    }

    DragHandler {
        id: drag
        target: null
        acceptedButtons: Qt.LeftButton
        dragThreshold: root.workspace ? root.workspace.behavior.dragThreshold : 8

        onActiveChanged: {
            if (active) {
                root._dragging = !!root.workspace && root.workspace.beginDrag({
                    dockId: root.dockId,
                    containerId: root.containerId,
                    source: root.source,
                    pressPoint: root._global(centroid.pressPosition)
                })
                if (root._dragging)
                    root.workspace.moveDrag(root._global(centroid.position))
            } else if (root._dragging) {
                root._dragging = false
                // A resize grip may have taken over and canceled the drag.
                if (root.workspace.dragging)
                    root.workspace.endDrag(root._global(centroid.position))
            }
        }
        onCentroidChanged: {
            if (active && root._dragging)
                root.workspace.moveDrag(root._global(centroid.position))
        }
        onCanceled: {
            if (root._dragging) {
                root._dragging = false
                root.workspace.cancelDrag()
            }
        }
    }
}
