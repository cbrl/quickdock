pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import "DockLayout.js" as DockLayout
import "DockPolicy.js" as DockPolicy
import "DockTypes.js" as DockTypes

// Public docking surface and orchestration root. The workspace owns the model,
// registry, command façade, drag controller, and floating-window controller.
Item {
    id: root

    // Declarative children and style delegates make up the workspace's public
    // configuration surface. All derived state below comes from the model.
    default property list<DockItem> dockItems

    property DockStyle style: DockStyle {}
    property Component tabDelegate: style.delegates.tab
    property Component headerDelegate: style.delegates.header
    property Component floatingTitleBarDelegate: style.delegates.floatingTitleBar
    property Component splitterDelegate: style.delegates.splitter
    property Component dropIndicatorDelegate: style.delegates.dropIndicator
    property Component dragPreviewDelegate: style.delegates.dragPreview
    property Component dropCompassDelegate: style.delegates.dropCompass
    property Component placeholderDelegate: style.delegates.placeholder
    property Component floatingDecorationDelegate: style.delegates.floatingDecoration
    property Component overflowMenuDelegate: style.delegates.overflowMenu

    property string centralDockId: ""
    property bool dropCompassEnabled: true
    property alias debugLayout: model.debugLayout

    readonly property int layoutVersion: DockLayout.layoutVersion
    readonly property var snapshot: model.snapshot
    readonly property var layoutTree: _mainContainer().root
    readonly property var hiddenDocks: snapshot && snapshot.hidden ? snapshot.hidden.slice() : []
    readonly property bool hostClosing: _hostClosing
    readonly property bool canUndoLayout: model.canUndo
    readonly property bool canRedoLayout: model.canRedo

    signal layoutChanged()
    signal splitRatioChanged(string splitId, int splitterIndex)
    signal dockActivated(string dockId)
    signal errorOccurred(string code, string message)
    signal dockItemsInitialized()
    signal hostClosingRequested()
    signal dockAdded(string dockId, var dockItem)
    signal dockAboutToClose(string dockId, var dockItem)
    signal dockClosed(string dockId)
    signal dockHidden(string dockId)
    signal dockShown(string dockId)

    // Object ids are local to this workspace and identify immutable tree nodes
    // and floating containers created during the current session.
    property int _nextObjectId: 0
    property bool _hostClosing: false

    // State services. Registry and commands mutate the model. Model signal
    // handlers synchronize native floating windows and public signals.
    //
    // Every `workspace: root` below assigns this component to a
    // DockWorkspace-typed property. qmllint cannot close the cycle while it is
    // still building DockWorkspace, so it reports the assignment as
    // DockWorkspace-to-DockWorkspace incompatibility. The bindings are correct.
    // qmllint disable incompatible-type
    DockRegistry {
        id: dockRegistry
        workspace: root
    }

    DockCommands {
        id: dockCommands
        workspace: root
        dockModel: model
    }

    DockModel {
        id: model

        onLayoutChanged: {
            floatingController.syncWindows()
            root.layoutChanged()
        }
        onSplitRatioChanged: (splitId, splitterIndex) => {
            floatingController.syncWindows()
            root.splitRatioChanged(splitId, splitterIndex)
        }
        onContainerGeometryChanged: floatingController.syncWindows()
    }

    property Item _canvas: Rectangle {
        parent: root
        x: 0
        y: 0
        width: root.width
        height: root.height
        color: root.style.colors.background

        DockNode {
            anchors.fill: parent
            anchors.margins: root.layoutTree ? 0 : root.style.frame.canvasMargin
            workspace: root
            containerId: "main"
            node: root.layoutTree
        }

        Loader {
            anchors.centerIn: parent
            visible: !root.layoutTree
            sourceComponent: root.placeholderDelegate
            property DockWorkspace workspace: root
            property DockStyle style: root.style
        }
    }

    // Overlays/controllers are shared by the main canvas and floating surfaces.
    DockDropOverlay {
        id: dropOverlay
        surface: root
        workspace: root
    }

    DockDragController {
        id: dragController
        workspace: root
    }

    DockDragPreview {
        id: dragPreviewWindow
        workspace: root
    }

    DockFloatingController {
        id: floatingController
        workspace: root
        dockModel: model
        snapshot: root.snapshot
    }
    // qmllint enable incompatible-type

    property Connections _hostWindowConnections: Connections {
        target: root.Window.window
        ignoreUnknownSignals: true

        function onClosing(_close) {
            Qt.callLater(root._closeFloatingWindowsIfHostClosed)
        }
    }

    // Declarative DockItems must be registered before the initial snapshot is
    // built so resetLayout can see the complete set of ids.
    Component.onCompleted: {
        // Register declarative DockItems before the initial layout is built.
        // Dynamic items use the same registry path through createDock().
        for (let i = 0; i < dockItems.length; ++i)
            dockRegistry._registerDockReference(dockItems[i], false)

        dockRegistry.validateDockItems()
        if (!_mainContainer().root && snapshot.containers.length === 1)
            resetLayout()

        dockItemsInitialized()
    }

    onCentralDockIdChanged: Qt.callLater(_ensureCentralDock)

    // Identity, registration, and lifecycle helpers form the first public API
    // layer over DockRegistry and DockPolicy.
    function _newId(prefix) {
        _nextObjectId += 1
        return prefix + "_" + _nextObjectId
    }

    function _newGroup(docks, active) {
        const values = docks ? docks.slice() : []
        return DockTypes.tabsNode({
            id: _newId("tabs"),
            docks: values,
            active: active || (values.length ? values[0] : "")
        })
    }

    function dockIds() {
        return dockRegistry.dockIds()
    }

    function _error(code, message) {
        errorOccurred(code, message)
        return false
    }

    function dockById(dockId) {
        return dockRegistry.dockById(dockId)
    }

    function registerDock(item, targetDockId, zone, takeOwnership) {
        return dockRegistry.registerDock(item, targetDockId, zone, takeOwnership)
    }

    function createDock(component, initialProperties, targetDockId, zone) {
        return dockRegistry.createDock(component, initialProperties, targetDockId, zone)
    }

    function parkDockItem(item) {
        dockRegistry.parkDockItem(item)
    }

    function canCloseDock(dockId) {
        return DockPolicy.canClose(dockById(dockId), dockId, centralDockId)
    }

    function canFloatDock(dockId) {
        return DockPolicy.canFloat(dockById(dockId), dockId, centralDockId)
    }

    function closeDock(dockId) {
        return dockCommands.closeDock(dockId)
    }

    function hideDock(dockId) {
        return dockCommands.hideDock(dockId)
    }

    function showDock(dockId) {
        return dockCommands.showDock(dockId)
    }

    function _unregisterDock(item) {
        dockRegistry.unregisterDock(item)
    }

    function _mainContainer() {
        const containers = snapshot && Array.isArray(snapshot.containers) ? snapshot.containers : []
        return DockLayout.mainContainer(containers)
    }

    function _containerForDock(dockId) {
        return DockLayout.containerForDock(snapshot.containers, dockId)
    }

    function containerOf(dockId) {
        const container = _containerForDock(dockId)
        return container ? container.id : ""
    }

    function isDocked(dockId) {
        const container = _containerForDock(dockId)
        return !!container && container.kind === "main"
    }

    function isFloating(dockId) {
        const container = _containerForDock(dockId)
        return !!container && container.kind === "floating"
    }

    function isHidden(dockId) {
        return !!snapshot
            && Array.isArray(snapshot.hidden)
            && snapshot.hidden.indexOf(dockId) >= 0
    }

    function isVisible(dockId) {
        return !!_containerForDock(dockId)
    }

    function isDockVisible(dockId) {
        return isVisible(dockId)
    }

    function neighborsOf(dockId) {
        const container = _containerForDock(dockId)
        return container ? DockLayout.neighborsOf(container.root, dockId) : []
    }

    function resetLayout() {
        dockCommands.resetLayout()
    }

    function _ensureCentralDock() {
        return dockCommands._ensureCentralDock()
    }

    function activateDock(dockId) {
        return dockCommands.activateDock(dockId)
    }

    function setSplitRatio(splitId, splitterIndex, ratio) {
        return dockCommands.setSplitRatio(splitId, splitterIndex, ratio)
    }

    function _dockMinimumSize(dockId) {
        const item = dockById(dockId)
        if (!item)
            return DockTypes.size({width: 0, height: 0})

        return DockTypes.size({
            width: Math.max(0, Number(item.minimumSize.width) || 0),
            height: Math.max(0, Number(item.minimumSize.height) || 0)
        })
    }

    function _dockMaximumSize(dockId) {
        const item = dockById(dockId)
        return item ? item.maximumSize : null
    }

    function _minimumSizeOf(node) {
        return DockLayout.minimumSizeOf(
            node,
            _dockMinimumSize,
            style.header.height,
            style.splitter.size
        )
    }

    function _maximumSizeOf(node) {
        return DockLayout.maximumSizeOf(
            node,
            _dockMaximumSize,
            style.header.height,
            style.splitter.size
        )
    }

    function _floatingMinimumSize(node) {
        return floatingController.floatingMinimumSize(node)
    }

    function _floatingMaximumSize(node) {
        return floatingController.floatingMaximumSize(node)
    }

    function _currentScreenName() {
        return floatingController._currentScreenName()
    }

    function _clampFloatingGeometry(raw, node) {
        return floatingController._clampFloatingGeometry(raw, node)
    }

    function floatDock(dockId, x, y, width, height) {
        return floatingController.floatDock(dockId, x, y, width, height)
    }

    function _updateFloatingGeometry(containerId, x, y, width, height, screenName) {
        return floatingController.updateFloatingGeometry(
            containerId,
            x,
            y,
            width,
            height,
            screenName
        )
    }

    function floatingWindowForDock(dockId) {
        return floatingController.windowForDock(dockId)
    }

    function _closeFloatingWindows() {
        floatingController.closeFloatingWindows()
    }

    function _closeFloatingWindowsIfHostClosed() {
        const hostWindow = root.Window.window
        if (!hostWindow || !hostWindow.visible)
            _closeFloatingWindows()
    }

    function dockToFirstGroup(dockId) {
        return dockCommands.dockToFirstGroup(dockId)
    }

    function dockAsTab(dockId, targetDockId) {
        return dockCommands.dockAsTab(dockId, targetDockId)
    }

    function splitDock(dockId, targetDockId, side) {
        return dockCommands.splitDock(dockId, targetDockId, side)
    }

    function dockRelative(dockId, targetDockId, zone) {
        return dockCommands.dockRelative(dockId, targetDockId, zone)
    }

    function _canDropDock(dockId, target) {
        return dockCommands.canDropDock(dockId, target)
    }

    function _canDropFloatingContainer(containerId, target) {
        return dockCommands.canDropFloatingContainer(containerId, target)
    }

    function _dockAt(dockId, targetContainerId, targetGroupId, zone, tabIndex, outer) {
        return dockCommands._dockAt(
            dockId,
            targetContainerId,
            targetGroupId,
            zone,
            tabIndex,
            outer
        )
    }

    function dockFloatingContainer(containerId) {
        return dockCommands.dockFloatingContainer(containerId)
    }

    function _dockFloatingContainerAt(
        containerId,
        targetContainerId,
        targetGroupId,
        zone,
        tabIndex,
        outer
    ) {
        return dockCommands._dockFloatingContainerAt(
            containerId,
            targetContainerId,
            targetGroupId,
            zone,
            tabIndex,
            outer
        )
    }

    function beginDockDrag(dockId, ignoreSourceSurface) {
        if (!dockById(dockId))
            return _error("dock-not-found", qsTr("Unknown dock: %1").arg(dockId))

        if (dockId === centralDockId)
            return _error(
                "central-dock-policy",
                qsTr("The central dock cannot be moved")
            )

        dragController.begin(dockId, ignoreSourceSurface)
        return true
    }

    function beginFloatingContainerDrag(containerId, dockId) {
        if (!dockById(dockId))
            return _error("dock-not-found", qsTr("Unknown dock: %1").arg(dockId))
        dragController.beginContainer(containerId, dockId)
        return true
    }

    function showDragPreview(dockId, sourceItem, x, y, width, height) {
        dragPreviewWindow.showPreview(
            dockId,
            sourceItem,
            DockTypes.rect({x: x, y: y, width: width, height: height})
        )
    }

    function moveDragPreview(x, y) {
        dragPreviewWindow.movePreview(x, y)
    }

    function hideDragPreview() {
        dragPreviewWindow.hidePreview()
    }

    function _dropContainerSurfaces() {
        const active = []
        const floating = []
        for (let i = snapshot.containers.length - 1; i >= 0; --i) {
            const state = snapshot.containers[i]
            if (state.kind !== "floating")
                continue

            const window = floatingController.windowForContainer(state.id)
            if (!window || !window.visible)
                continue

            const surface = DockTypes.dropSurface({
                state: state,
                item: window.dockingSurface
            })

            if (window.active)
                active.push(surface)
            else
                floating.push(surface)
        }
        // Active floating windows win hit-testing ties. The main canvas is
        // checked last so a floating surface can receive a drop over it.
        return active.concat(floating).concat([
            DockTypes.dropSurface({state: _mainContainer(), item: _canvas})
        ])
    }

    function _hideDropPreviews() {
        dropOverlay.hide()
        floatingController.hideDropPreviews()
    }

    function _showDropPreview(containerId, previewRect, targetRect, zone) {
        if (containerId !== "main") {
            const window = floatingController.windowForContainer(containerId)
            if (window)
                window.showDropPreview(previewRect, targetRect, zone)
            return
        }
        dropOverlay.show(previewRect, targetRect, zone)
    }

    function updateDockDrag(dockId, globalPoint) {
        return dragController.update(dockId, globalPoint)
    }

    function updateFloatingContainerDrag(containerId, globalPoint) {
        return dragController.updateContainer(containerId, globalPoint)
    }

    function cancelDockDrag() {
        dragController.cancel()
        hideDragPreview()
    }

    function finishDockedDrag(dockId, globalPoint, x, y, width, height) {
        return dragController.finishDocked(dockId, globalPoint, x, y, width, height)
    }

    function finishFloatingDrag(dockId, containerId, globalPoint, x, y, width, height) {
        return dragController.finishFloating(
            dockId,
            containerId,
            globalPoint,
            x,
            y,
            width,
            height
        )
    }

    function finishFloatingContainerDrag(containerId, globalPoint, x, y, width, height) {
        return dragController.finishFloatingContainer(
            containerId,
            globalPoint,
            x,
            y,
            width,
            height
        )
    }

    function maximizeFloatingDock(dockId) {
        return floatingController.maximizeFloatingDock(dockId)
    }

    function restoreFloatingDock(dockId) {
        return floatingController.restoreFloatingDock(dockId)
    }

    function toggleFloatingDockMaximized(dockId) {
        return floatingController.toggleFloatingDockMaximized(dockId)
    }

    function saveLayout() {
        return dockCommands.saveLayout()
    }

    function restoreLayout(state) {
        return dockCommands.restoreLayout(state)
    }

    function undoLayout() {
        return model.undo()
    }

    function redoLayout() {
        return model.redo()
    }
}
