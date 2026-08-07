pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import "DockLayout.js" as DockLayout

// Native top-level surface for one floating layout container. It owns window
// gestures and delegates the layout content back to the shared DockWorkspace.
Window {
    id: root

    required property DockWorkspace workspace
    required property string containerId
    required property var floatingState
    readonly property var dockIds: DockLayout.collectDocks(
        floatingState ? floatingState.root : null
    )
    readonly property int dockCount: dockIds.length
    readonly property bool hasDedicatedTitleBar: dockCount > 1
    readonly property string activeDockId: {
        const group = DockLayout.firstGroup(floatingState ? floatingState.root : null)
        return group ? group.active : ""
    }
    property alias dockingSurface: contentFrame
    property bool _ready: false
    property bool _applyingGeometry: false
    property bool _movingWindow: false
    property bool _resizingWindow: false
    property bool _geometryPublishPending: false
    // Frameless windows on some platforms report maximize as FullScreen.
    readonly property bool maximized: visibility === Window.Maximized || visibility === Window.FullScreen
    property point _moveStartGlobal: Qt.point(0, 0)
    property point _moveStartPosition: Qt.point(0, 0)
    property point _resizeStartGlobal: Qt.point(0, 0)
    property rect _resizeStartGeometry: Qt.rect(0, 0, 0, 0)
    objectName: "floatingDockWindow_" + containerId

    minimumWidth: workspace._floatingMinimumSize(floatingState ? floatingState.root : null).width
    minimumHeight: workspace._floatingMinimumSize(floatingState ? floatingState.root : null).height
    maximumWidth: workspace._floatingMaximumSize(floatingState ? floatingState.root : null).width
    maximumHeight: workspace._floatingMaximumSize(floatingState ? floatingState.root : null).height

    flags: Qt.Window | Qt.FramelessWindowHint
    transientParent: workspace.Window.window
    visible: true
    color: workspace.style.colors.panel
    title: activeTitle()

    // Apply snapshot geometry/state changes while avoiding feedback loops from
    // the native window's own x/y/size notifications.
    onFloatingStateChanged: applyFloatingState()
    onVisibilityChanged: {
        if (_ready && root.visibility === Window.Windowed)
            applyFloatingState()
    }
    Component.onCompleted: {
        applyFloatingState()
        _ready = true
    }

    onXChanged: scheduleGeometryPublish()
    onYChanged: scheduleGeometryPublish()
    onWidthChanged: scheduleGeometryPublish()
    onHeightChanged: scheduleGeometryPublish()

    Timer {
        id: resizeSettleTimer
        interval: 250
        repeat: false
        onTriggered: root.endResize()
    }

    onClosing: close => {
        if (workspace.hostClosing) {
            close.accepted = true
        } else {
            close.accepted = false
            workspace.dockFloatingContainer(containerId)
        }
    }

    Connections {
        target: root.workspace
        ignoreUnknownSignals: true

        function onHostClosingRequested() {
            root.close()
        }
    }

    // Window title and persisted geometry are derived from the active snapshot.
    function activeTitle() {
        const item = workspace.dockById(activeDockId)
        return item ? item.title : activeDockId
    }

    function applyFloatingState() {
        if (!floatingState || !floatingState.geometry
                || (_ready && visibility !== Window.Windowed))
            return

        const geometry = floatingState.geometry
        if (x === geometry.x && y === geometry.y
                && width === geometry.width && height === geometry.height)
            return

        _applyingGeometry = true
        setGeometry(
            geometry.x,
            geometry.y,
            geometry.width,
            geometry.height
        )
        _applyingGeometry = false
    }

    function scheduleGeometryPublish() {
        if (!_ready || _applyingGeometry || _movingWindow)
            return
        if (visibility !== Window.Windowed)
            return
        if (_resizingWindow) {
            resizeSettleTimer.restart()
            return
        }
        if (_geometryPublishPending)
            return
        _geometryPublishPending = true
        Qt.callLater(publishGeometry)
    }

    function publishGeometry() {
        _geometryPublishPending = false
        if (!_ready || _applyingGeometry || _movingWindow || _resizingWindow
                || visibility !== Window.Windowed)
            return

        workspace._updateFloatingGeometry(
            containerId,
            x,
            y,
            width,
            height,
            screen ? screen.name : ""
        )
    }

    // These handlers implement a client-side move gesture for frameless
    // windows and cooperate with the native resize path below.
    function beginMove(globalPoint) {
        if (_resizingWindow)
            return false
        if (maximized)
            showNormal()

        _movingWindow = true
        _moveStartGlobal = globalPoint
        _moveStartPosition = Qt.point(x, y)
        return true
    }

    function continueMove(globalPoint) {
        if (!_movingWindow)
            return false

        const dx = globalPoint.x - _moveStartGlobal.x
        const dy = globalPoint.y - _moveStartGlobal.y

        _applyingGeometry = true
        setGeometry(
            Math.round(_moveStartPosition.x + dx),
            Math.round(_moveStartPosition.y + dy),
            width,
            height
        )
        _applyingGeometry = false
        return true
    }

    function endMove() {
        if (!_movingWindow)
            return false
        _movingWindow = false
        publishGeometry()
        return true
    }

    function cancelMove() {
        if (!_movingWindow)
            return false

        _movingWindow = false
        _applyingGeometry = true
        setGeometry(
            Math.round(_moveStartPosition.x),
            Math.round(_moveStartPosition.y),
            width,
            height
        )
        _applyingGeometry = false
        return true
    }

    function toggleMaximized() {
        if (maximized)
            showNormal()
        else
            showMaximized()
    }

    function beginResize(globalPoint) {
        _resizingWindow = true
        _resizeStartGlobal = globalPoint
        _resizeStartGeometry = Qt.rect(x, y, width, height)
    }

    function systemResizeEdges(edges) {
        let result = 0
        if (edges.indexOf("left") >= 0)
            result |= Qt.LeftEdge
        if (edges.indexOf("right") >= 0)
            result |= Qt.RightEdge
        if (edges.indexOf("top") >= 0)
            result |= Qt.TopEdge
        if (edges.indexOf("bottom") >= 0)
            result |= Qt.BottomEdge
        return result
    }

    function beginResizeGesture(edges, globalPoint) {
        // The top resize grip overlaps the title bar. Both DragHandlers can
        // therefore recognize the same pointer movement before the platform
        // takes ownership of a native resize. A resize wins that contest:
        // roll back the tentative title-bar move and invalidate its dock drag.
        if (cancelMove())
            workspace.cancelDockDrag()

        _resizingWindow = true
        if (startSystemResize(systemResizeEdges(edges)))
            return true

        beginResize(globalPoint)
        return false
    }

    function continueResize(edges, globalPoint) {
        const dx = globalPoint.x - _resizeStartGlobal.x
        const dy = globalPoint.y - _resizeStartGlobal.y
        const start = _resizeStartGeometry

        let nextX = start.x
        let nextY = start.y
        let nextWidth = start.width
        let nextHeight = start.height

        if (edges.indexOf("left") >= 0) {
            nextWidth = Math.max(minimumWidth, start.width - dx)
            nextX = start.x + start.width - nextWidth
        } else if (edges.indexOf("right") >= 0) {
            nextWidth = Math.max(minimumWidth, start.width + dx)
        }

        if (edges.indexOf("top") >= 0) {
            nextHeight = Math.max(minimumHeight, start.height - dy)
            nextY = start.y + start.height - nextHeight
        } else if (edges.indexOf("bottom") >= 0) {
            nextHeight = Math.max(minimumHeight, start.height + dy)
        }

        _applyingGeometry = true
        setGeometry(
            Math.round(nextX),
            Math.round(nextY),
            Math.round(nextWidth),
            Math.round(nextHeight)
        )
        _applyingGeometry = false
    }

    function endResize() {
        if (!_resizingWindow)
            return
        resizeSettleTimer.stop()
        _resizingWindow = false
        publishGeometry()
    }

    function showDropPreview(previewRect, targetRect, zone) {
        dropOverlay.show(previewRect, targetRect, zone)
    }

    function hideDropPreview() {
        dropOverlay.hide()
    }

    // Multi-dock containers get window-level chrome. This keeps native-window
    // movement and maximize/dock actions separate from the individual tabs.
    DockFloatingTitleBarSlot {
        id: floatingTitleBar
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        height: root.hasDedicatedTitleBar ? root.workspace.style.header.height : 0
        visible: root.hasDedicatedTitleBar
        workspace: root.workspace
        // Same self-referential cycle qmllint cannot close as in DockWorkspace.
        floatingWindow: root // qmllint disable incompatible-type
        containerId: root.containerId
        dockId: root.activeDockId
        delegate: root.workspace.floatingTitleBarDelegate
    }

    // The content frame renders the same DockNode tree as the main workspace.
    // Its origin excludes the dedicated title bar so drop hit-testing remains
    // aligned with the recursive layout geometry.
    Rectangle {
        id: contentFrame
        anchors {
            left: parent.left
            right: parent.right
            top: floatingTitleBar.bottom
            bottom: parent.bottom
        }
        color: root.workspace.style.colors.panel

        DockNode {
            anchors.fill: parent
            workspace: root.workspace
            containerId: root.containerId
            // Same self-referential cycle qmllint cannot close as in DockWorkspace.
        floatingWindow: root // qmllint disable incompatible-type
            dedicatedFloatingTitleBar: root.hasDedicatedTitleBar
            node: root.floatingState ? root.floatingState.root : null
        }

        Loader {
            anchors.fill: parent
            sourceComponent: root.workspace.floatingDecorationDelegate
            property DockWorkspace workspace: root.workspace
            property DockStyle style: root.workspace.style
            property string containerId: root.containerId
        }
    }

    DockDropOverlay {
        id: dropOverlay
        surface: contentFrame
        workspace: root.workspace
        previewObjectName: "floatingDropPreview_" + root.containerId
    }

    // Transparent edge and corner handlers provide a platform-independent
    // fallback when a native system resize cannot claim the pointer.
    Repeater {
        model: ["left", "right", "top", "bottom",
                "topLeft", "topRight", "bottomLeft", "bottomRight"]

        Item {
            id: resizeArea
            required property string modelData
            readonly property bool leftEdge: modelData.indexOf("Left") >= 0 || modelData === "left"
            readonly property bool rightEdge: modelData.indexOf("Right") >= 0 || modelData === "right"
            readonly property bool topEdge: modelData.indexOf("top") === 0 || modelData === "top"
            readonly property bool bottomEdge: modelData.indexOf("bottom") === 0 || modelData === "bottom"
            readonly property bool corner: (leftEdge || rightEdge) && (topEdge || bottomEdge)
            readonly property int thickness: root.workspace.style.floating.resizeGrip.size
            z: root.workspace.style.floating.resizeGrip.z + (corner ? 1 : 0)
            x: leftEdge ? 0
                        : rightEdge ? root.width - thickness
                        : thickness
            y: topEdge ? 0
                       : bottomEdge ? root.height - thickness
                       : thickness
            width: corner ? thickness
                          : (modelData === "top" || modelData === "bottom"
                              ? Math.max(0, root.width - 2 * thickness) : thickness)
            height: corner ? thickness
                           : (modelData === "left" || modelData === "right"
                               ? Math.max(0, root.height - 2 * thickness) : thickness)

            readonly property int resizeCursor: {
                if ((leftEdge && topEdge) || (rightEdge && bottomEdge))
                    return Qt.SizeFDiagCursor
                if ((rightEdge && topEdge) || (leftEdge && bottomEdge))
                    return Qt.SizeBDiagCursor
                return leftEdge || rightEdge ? Qt.SizeHorCursor : Qt.SizeVerCursor
            }

            function globalPoint(position) {
                return mapToGlobal(position)
            }

            HoverHandler {
                cursorShape: resizeArea.resizeCursor
            }

            DragHandler {
                id: resizeDrag
                target: null
                acceptedButtons: Qt.LeftButton
                property bool nativeResize: false

                onActiveChanged: {
                    if (active) {
                        nativeResize = root.beginResizeGesture(
                            resizeArea.modelData.toLowerCase(),
                            resizeArea.globalPoint(centroid.pressPosition)
                        )
                        if (!nativeResize)
                            resizeArea.continueGesture(centroid.position)
                    } else if (nativeResize) {
                        resizeSettleTimer.restart()
                    } else {
                        root.endResize()
                    }
                }
                onCentroidChanged: {
                    if (active && !nativeResize)
                        resizeArea.continueGesture(centroid.position)
                }
                onCanceled: {
                    if (nativeResize)
                        resizeSettleTimer.restart()
                    else
                        root.endResize()
                }
            }

            function continueGesture(position) {
                if (!resizeDrag.nativeResize) {
                    root.continueResize(modelData.toLowerCase(), globalPoint(position))
                }
            }
        }
    }
}
