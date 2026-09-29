pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import "DockLayout.js" as DockLayout

// Native frameless window for one floating container. The snapshot owns its
// geometry: the window applies snapshot changes and publishes its own moves
// and resizes back once a gesture ends. A window with more than one dock gets
// a title bar, as does one with a single dock when behavior.singleDockTitleBar
// is set. Otherwise the dock's header moves the window.
//
// The workspace's windowIntegrationDelegate, when set, is created once in the
// window to integrate it with the platform: a native frame and shadow, snap
// layouts, and the like.
Window {
    id: root

    required property DockWorkspace workspace
    required property string containerId
    required property var container

    readonly property var dockIds: DockLayout.collectDocks(container ? container.root : null)
    readonly property bool hasTitleBar: dockIds.length > 1
		|| (dockIds.length === 1 && workspace.behavior.singleDockTitleBar)
    readonly property string selectedDockId: container ? container.selected : ""
    readonly property DockItem selectedDock: workspace.dockById(selectedDockId)
    // Frameless windows on some platforms report maximize as FullScreen.
    readonly property bool maximized: visibility === Window.Maximized || visibility === Window.FullScreen

    // The maximize button of the window's chrome while it is shown, or null.
    // A title bar or header delegate offers one as its `maximizeButton`.
    // An integration may let the platform hit-test it (Windows 11 opens its
    // snap layouts over it), and the button then gets no pointer events of its
    // own. The integration reports the button's hover and press state here
    // instead, and the chrome shows it.
    readonly property Item maximizeButton: {
        const button = hasTitleBar ? titleBar.value("maximizeButton", null) : _headerMaximizeButton
        return button && button.visible ? button : null
    }
    property bool maximizeButtonHovered: false
    property bool maximizeButtonPressed: false

    // Without a title bar, the header of the window's only dock is its
    // chrome. That dock's DockGroup sets the header's maximize button here.
    property Item _headerMaximizeButton: null

    // Window size limits: the container delegate's own minimumSize and
    // maximumSize when it declares them, the dock tree's otherwise.
    readonly property var limits: {
        const minimum = content.value("minimumSize", null)
        const maximum = content.value("maximumSize", null)
        const inner = minimum && maximum
            ? {minimum: minimum, maximum: maximum}
            : workspace._sizeLimits(container ? container.root : null)

        // A lone dock's title bar takes the place of its header, which the
        // dock tree's limits already count.
        return DockLayout.floatingLimits(
			inner,
			dockIds.length > 1 ? workspace.style.header.height : 0,
            workspace.behavior.floatingMinimumSize
		)
    }

    // "move" and "resize" are pointer gestures driven here. "systemResize" is
    // a resize the platform runs, which ends once the geometry settles.
    property string _gesture: ""
    property int _resizeEdges: 0
    property point _gestureStart: Qt.point(0, 0)
    property rect _startGeometry: Qt.rect(0, 0, 0, 0)
    property bool _applying: false
    property bool _publishPending: false
    property bool _ready: false
    property bool _alive: true

    // Qt Quick 3D binds a scene to its window's renderer when the item is
    // reparented into the window. Before the first frame there is no renderer,
    // and a View3D moved in then never draws. The layout is withheld until the
    // window has put up a frame. Rebuilding it later does not repair the scene.
    property bool _renderReady: false
    property bool _renderReadyPending: false

    objectName: "floatingDockWindow_" + containerId
    minimumWidth: limits.minimum.width
    minimumHeight: limits.minimum.height
    maximumWidth: limits.maximum.width
    maximumHeight: limits.maximum.height
    flags: Qt.Window | Qt.FramelessWindowHint
    transientParent: workspace.Window.window
    visible: true
    color: workspace.style.colors.panel
    title: selectedDock ? selectedDock.title : selectedDockId

    // Changes during construction wait for Component.onCompleted, when all
    // required properties are set.
    onContainerChanged: {
        if (_ready)
            _applyGeometry()
    }
    onLimitsChanged: {
        if (_ready)
            _applyGeometry()
    }
    onVisibilityChanged: {
        if (_ready && root.visibility === Window.Windowed)
            _applyGeometry()
    }
    onXChanged: _schedulePublish()
    onYChanged: _schedulePublish()
    onWidthChanged: _schedulePublish()
    onHeightChanged: _schedulePublish()
    Component.onCompleted: {
        _applyGeometry()
        _ready = true
        Qt.callLater(_publish)
    }

    // frameSwapped arrives from the render thread. Flip the flag from a clean
    // pass of the GUI event loop, since flipping it inline still races.
    onFrameSwapped: {
        if (!_renderReady && !_renderReadyPending) {
            _renderReadyPending = true
            Qt.callLater(() => { root._renderReady = true })
        }
    }

    onClosing: close => {
        close.accepted = workspace.hostClosing
        if (!close.accepted)
            workspace.dockContainerToMain(containerId)
    }

    // An integration with a toggleMaximized() of its own does it instead, and
    // returns true when it did.
    function toggleMaximized() {
        const integrationToggle = integrationHost.value("toggleMaximized", null)
        if (typeof integrationToggle === "function" && integrationToggle())
            return
        if (maximized)
            showNormal()
        else
            showMaximized()
    }

    // Unloads the delegates while the workspace is still alive, so every
    // DockItem goes back to the parking lot before the window is destroyed.
    function prepareForDestruction() {
        _alive = false
    }

    function _setGeometry(x, y, width, height) {
        _applying = true
        setGeometry(Math.round(x), Math.round(y), Math.round(width), Math.round(height))
        _applying = false
    }

    function _applyGeometry() {
        if (!_alive || !container || !container.geometry || _gesture || (_ready && visibility !== Window.Windowed))
            return
        const saved = container.geometry
        const rect = DockLayout.fitGeometry(saved, limits, null)
        if (rect.x !== x || rect.y !== y || rect.width !== width || rect.height !== height)
            _setGeometry(rect.x, rect.y, rect.width, rect.height)
        // New size limits can change the saved size. Save the fitted one.
        if (_ready && (rect.width !== saved.width || rect.height !== saved.height))
            Qt.callLater(_publish)
    }

    function _schedulePublish() {
        if (!_ready || _applying || visibility !== Window.Windowed)
            return
        if (_gesture === "systemResize")
            settleTimer.restart()
        if (_gesture || _publishPending)
            return
        _publishPending = true
        Qt.callLater(_publish)
    }

    function _publish() {
        _publishPending = false
        if (_ready && _alive && !_gesture && visibility === Window.Windowed)
            workspace._setFloatingGeometry(containerId, Qt.rect(x, y, width, height), screen ? screen.name : "")
    }

    // --- Moving (the drag controller drives this during a window drag) ---

    function beginMove(globalPoint) {
        if (_gesture)
            return false
        if (maximized)
            toggleMaximized()
        _gesture = "move"
        _gestureStart = globalPoint
        _startGeometry = Qt.rect(x, y, width, height)
        return true
    }

    function continueMove(globalPoint) {
        if (_gesture !== "move")
            return false
        _setGeometry(_startGeometry.x + globalPoint.x - _gestureStart.x,
                     _startGeometry.y + globalPoint.y - _gestureStart.y, width, height)
        return true
    }

    function endMove() {
        if (_gesture !== "move")
            return false
        _gesture = ""
        _publish()
        return true
    }

    function cancelMove() {
        if (_gesture !== "move")
            return false
        _gesture = ""
        _setGeometry(_startGeometry.x, _startGeometry.y, width, height)
        return true
    }

    // --- Resizing: `edges` is a combination of Qt.Edge flags ---

    function beginResize(edges, globalPoint) {
        _gesture = "resize"
        _resizeEdges = edges
        _gestureStart = globalPoint
        _startGeometry = Qt.rect(x, y, width, height)
    }

    function continueResize(globalPoint) {
        if (_gesture !== "resize")
            return
        const dx = globalPoint.x - _gestureStart.x
        const dy = globalPoint.y - _gestureStart.y
        const start = _startGeometry
        let next = Qt.rect(start.x, start.y, start.width, start.height)
        if (_resizeEdges & Qt.LeftEdge) {
            next.width = Math.max(minimumWidth, start.width - dx)
            next.x = start.x + start.width - next.width
        } else if (_resizeEdges & Qt.RightEdge) {
            next.width = Math.max(minimumWidth, start.width + dx)
        }
        if (_resizeEdges & Qt.TopEdge) {
            next.height = Math.max(minimumHeight, start.height - dy)
            next.y = start.y + start.height - next.height
        } else if (_resizeEdges & Qt.BottomEdge) {
            next.height = Math.max(minimumHeight, start.height + dy)
        }
        _setGeometry(next.x, next.y, next.width, next.height)
    }

    function endResize() {
        if (_gesture !== "resize" && _gesture !== "systemResize")
            return
        settleTimer.stop()
        _gesture = ""
        _publish()
    }

    // A grip prefers the platform's own resize and falls back to beginResize.
    // The top grip overlaps the title bar, so a resize also cancels a drag
    // that the same press may have started there.
    function _beginResizeGesture(edges, globalPoint) {
        if (workspace.dragging)
            workspace.cancelDrag()
        if (startSystemResize(edges)) {
            _gesture = "systemResize"
            settleTimer.restart()
            return true
        }
        beginResize(edges, globalPoint)
        return false
    }

    Timer {
        id: settleTimer
        interval: 250
        onTriggered: root.endResize()
    }

    // Declared first so it stays below the title bar and content.
    DockDelegateHost {
        id: integrationHost
        anchors.fill: parent
        delegate: root._alive ? root.workspace.windowIntegrationDelegate : null
        context: QtObject {
            readonly property DockWorkspace workspace: root.workspace
            readonly property DockStyle style: root.workspace.style
            readonly property var floatingWindow: root
            readonly property string containerId: root.containerId
        }
    }

    DockDelegateHost {
        id: titleBar
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        height: root.hasTitleBar ? root.workspace.style.header.height : 0
        visible: root.hasTitleBar
        delegate: root._alive && root.hasTitleBar ? root.workspace.titleBarDelegate : null
        context: QtObject {
            readonly property DockWorkspace workspace: root.workspace
            readonly property DockStyle style: root.workspace.style
            readonly property var floatingWindow: root
            readonly property string containerId: root.containerId
            readonly property DockItem dock: root.selectedDock
            readonly property bool maximized: root.maximized
        }
    }

    DockDelegateHost {
        id: content
        anchors {
            left: parent.left
            right: parent.right
            top: titleBar.bottom
            bottom: parent.bottom
        }
        delegate: root._alive ? root.workspace.containerDelegate : null
        context: QtObject {
            readonly property DockWorkspace workspace: root.workspace
            readonly property DockStyle style: root.workspace.style
            readonly property string containerId: root.containerId
            readonly property var container: root.container
            readonly property var floatingWindow: root
            readonly property bool renderReady: root._renderReady
        }
    }

    // Invisible resize border along each edge and corner.
    Repeater {
        model: [Qt.LeftEdge, Qt.RightEdge, Qt.TopEdge, Qt.BottomEdge,
                Qt.TopEdge | Qt.LeftEdge, Qt.TopEdge | Qt.RightEdge,
                Qt.BottomEdge | Qt.LeftEdge, Qt.BottomEdge | Qt.RightEdge]

        Item {
            id: grip
            required property int modelData
            readonly property bool leftEdge: !!(modelData & Qt.LeftEdge)
            readonly property bool rightEdge: !!(modelData & Qt.RightEdge)
            readonly property bool topEdge: !!(modelData & Qt.TopEdge)
            readonly property bool bottomEdge: !!(modelData & Qt.BottomEdge)
            readonly property int size: root.workspace.style.floating.gripSize

            z: (leftEdge || rightEdge) && (topEdge || bottomEdge) ? 101 : 100
            x: leftEdge ? 0 : rightEdge ? root.width - size : size
            y: topEdge ? 0 : bottomEdge ? root.height - size : size
            width: leftEdge || rightEdge ? size : Math.max(0, root.width - 2 * size)
            height: topEdge || bottomEdge ? size : Math.max(0, root.height - 2 * size)

            HoverHandler {
                cursorShape: (grip.leftEdge && grip.topEdge) || (grip.rightEdge && grip.bottomEdge) ? Qt.SizeFDiagCursor
                           : (grip.rightEdge && grip.topEdge) || (grip.leftEdge && grip.bottomEdge) ? Qt.SizeBDiagCursor
                           : grip.leftEdge || grip.rightEdge ? Qt.SizeHorCursor : Qt.SizeVerCursor
            }

            DragHandler {
                target: null
                acceptedButtons: Qt.LeftButton

                onActiveChanged: {
                    if (active) {
                        if (!root._beginResizeGesture(grip.modelData, grip.mapToGlobal(centroid.pressPosition)))
                            root.continueResize(grip.mapToGlobal(centroid.position))
                    } else if (root._gesture === "systemResize") {
                        settleTimer.restart()
                    } else {
                        root.endResize()
                    }
                }
                onCentroidChanged: {
                    if (active)
                        root.continueResize(grip.mapToGlobal(centroid.position))
                }
                onCanceled: {
                    if (root._gesture === "systemResize")
                        settleTimer.restart()
                    else
                        root.endResize()
                }
            }
        }
    }
}
