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
    readonly property var dockIds: DockLayout.collectDocks(floatingState ? floatingState.root : null)
    readonly property int dockCount: dockIds.length
    readonly property bool hasDedicatedTitleBar: dockCount > 1
    readonly property string activeDockId: {
        const group = DockLayout.firstGroup(floatingState ? floatingState.root : null)
        return group ? group.active : ""
    }
    readonly property DockContainer containerRenderer: containerContent.item as DockContainer
    readonly property Item dockingSurface: containerRenderer ? containerRenderer.dockingSurface : null
    readonly property size containerMinimumSize: containerRenderer
		? containerRenderer.minimumSize
		: workspace._minimumSizeOf(floatingState ? floatingState.root : null)
    readonly property size containerMaximumSize: containerRenderer
		? containerRenderer.maximumSize
		: workspace._maximumSizeOf(floatingState ? floatingState.root : null)

    // Qt Quick 3D binds a scene to its window's renderer at the moment the item is reparented into
    // that window. A window that has not yet rendered has no renderer to bind to, and the scene
    // never recovers. A View3D moved here during construction draws nothing from then on, leaving
    // only the plain Qt Quick overlays visible. Withholding the layout until this window has put
    // up a frame keeps that binding valid. Rebuilding the scene afterwards does not repair it. The
    // attachment has to be correct the first time.
    property bool _renderReady: false
    property bool _renderReadyPending: false

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

    minimumWidth: Math.max(
        workspace.style.floating.minimumSize.width,
        containerMinimumSize.width
    )
    minimumHeight: Math.max(
        workspace.style.floating.minimumSize.height,
        containerMinimumSize.height + (hasDedicatedTitleBar ? workspace.style.header.height : 0)
    )
    maximumWidth: Math.max(minimumWidth, containerMaximumSize.width)
    maximumHeight: Math.max(
        minimumHeight,
        Math.min(
            16777215,
            containerMaximumSize.height+ (hasDedicatedTitleBar ? workspace.style.header.height : 0)
        )
    )

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
        Qt.callLater(publishGeometry)
    }

    // frameSwapped is delivered from the render thread, so hand the flag flip
    // back to a clean pass of the GUI thread's event loop before the layout is
    // built. Flipping it inline still races the renderer.
    onFrameSwapped: {
        if (!_renderReady && !_renderReadyPending) {
            _renderReadyPending = true
            Qt.callLater(function() { if (root) root._renderReady = true })
        }
    }

    onXChanged: scheduleGeometryPublish()
    onYChanged: scheduleGeometryPublish()
    onWidthChanged: scheduleGeometryPublish()
    onHeightChanged: scheduleGeometryPublish()
    onMinimumWidthChanged: enforceSizeConstraints()
    onMinimumHeightChanged: enforceSizeConstraints()
    onMaximumWidthChanged: enforceSizeConstraints()
    onMaximumHeightChanged: enforceSizeConstraints()

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

    function sizeConstrainedGeometry(raw) {
        // `availableGeometry` is supplied by the native QScreen object exposed
        // through Window.screen, but qmllint resolves it as QQuickScreenInfo.
        // qmllint disable missing-property
        const available = root.screen && root.screen.availableGeometry
            ? root.screen.availableGeometry
            : Qt.rect(0, 0, 1920, 1080)
        // qmllint enable missing-property
        const width = Math.min(
            root.maximumWidth,
            available.width,
            Math.max(root.minimumWidth, Math.round(Number(raw.width)))
        )
        const height = Math.min(
            root.maximumHeight,
            available.height,
            Math.max(root.minimumHeight, Math.round(Number(raw.height)))
        )
        const x = Math.round(Number(raw.x))
        const y = Math.round(Number(raw.y))
        return Qt.rect(x, y, width, height)
    }

    function enforceSizeConstraints() {
        if (!root._ready || root.visibility !== Window.Windowed)
            return

        const constrained = sizeConstrainedGeometry(root)
        if (root.x === constrained.x && root.y === constrained.y
                && root.width === constrained.width && root.height === constrained.height)
            return

        root._applyingGeometry = true
        root.setGeometry(
            constrained.x,
            constrained.y,
            constrained.width,
            constrained.height
        )
        root._applyingGeometry = false
        Qt.callLater(root.publishGeometry)
    }

    function applyFloatingState() {
        if (!floatingState || !floatingState.geometry
                || (_ready && visibility !== Window.Windowed))
            return

        const geometry = sizeConstrainedGeometry(floatingState.geometry)
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

    // Unload workspace-bound delegates before the Window teardown clears its
    // required properties. This also lets DockContentHost park its DockItem
    // while the registry is still available.
    function prepareForDestruction() {
        containerContent.active = false
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

    QtObject {
        id: floatingContainerContext

        // Keep a direct reference rather than a binding through the Window.
        // Window teardown clears required properties before loaded delegates
        // are destroyed, while the workspace itself is still alive.
        property DockWorkspace workspace: null
        readonly property var floatingWindow: root
        readonly property string containerId: root.containerId
        readonly property var containerState: root.floatingState
        readonly property bool renderReady: root._renderReady
        readonly property string selectedDockId: root.workspace.selectedDock(root.containerId)
    }

    // Main and native top-level containers use the same renderer contract.
    // Window mechanics only consume its declared dockingSurface.
    Loader {
        id: containerContent
        anchors {
            left: parent.left
            right: parent.right
            top: floatingTitleBar.bottom
            bottom: parent.bottom
        }
        sourceComponent: root.workspace.containerDelegate
        onLoaded: {
            floatingContainerContext.workspace = root.workspace
            const container = root.containerRenderer
            if (container) {
                container.containerContext = floatingContainerContext
            } else {
                root.workspace._error(
                    "invalid-container-delegate",
                    qsTr("containerDelegate must create a DockContainer")
                )
            }
        }
    }

    DockDropOverlay {
        id: dropOverlay
        surface: root.dockingSurface
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
