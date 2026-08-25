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

    // Declarative children, component delegates, and style tokens make up the
    // workspace's public configuration surface. All derived state below comes
    // from the model.
    default property list<DockItem> dockItems

    property DockStyle style: DockStyle {}

    // qmllint disable missing-property
    property Component tabDelegate: null
    property Component headerDelegate: null
    property Component floatingTitleBarDelegate: null
    property Component splitterDelegate: Component {
        Rectangle {
            color: (parent.hovered || parent.pressed)
                ? root.style.colors.accent
                : root.style.colors.splitter
        }
    }
    property Component dropIndicatorDelegate: Component {
        Rectangle {
            color: root.style.colors.preview
            border.color: root.style.colors.accent
            border.width: root.style.drop.indicator.border.width
            radius: root.style.drop.indicator.radius
        }
    }
    property Component dragPreviewDelegate: Component {
        Rectangle {
            id: dragVisual
            color: root.style.colors.dragPreviewFallback
            border.color: root.style.colors.accent
            border.width: root.style.drag.preview.border.width
            radius: root.style.drag.preview.radius
            clip: true

            Image {
                id: snapshotImage
                anchors.fill: parent
                source: dragVisual.parent.snapshotSource
                visible: status === Image.Ready
                fillMode: Image.Stretch
                smooth: true
            }

            Rectangle {
                id: fallbackHeader
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: root.style.drag.preview.border.width
                }
                height: root.style.header.height
                visible: !snapshotImage.visible
                color: root.style.colors.activeHeader

                Image {
                    id: fallbackIcon
                    anchors {
                        left: parent.left
                        leftMargin: root.style.header.horizontalPadding
                        verticalCenter: parent.verticalCenter
                    }
                    width: root.style.fonts.glyph.pixelSize
                    height: root.style.fonts.glyph.pixelSize
                    source: dragVisual.parent.iconSource
                    visible: source.toString().length > 0
                    fillMode: Image.PreserveAspectFit
                }

                Text {
                    anchors {
                        left: fallbackIcon.visible ? fallbackIcon.right : parent.left
                        leftMargin: fallbackIcon.visible
                                    ? root.style.header.titleSpacing
                                    : root.style.header.horizontalPadding
                        right: parent.right
                        rightMargin: root.style.header.horizontalPadding
                        verticalCenter: parent.verticalCenter
                    }
                    text: dragVisual.parent.title
                    color: root.style.colors.activeText
                    font: root.style.fonts.title
                    elide: Text.ElideRight
                }
            }
        }
    }
    property Component dropCompassDelegate: Component {
        Item {
            id: compass

            Repeater {
                model: [
                    {zone: "top", column: 1, row: 0},
                    {zone: "left", column: 0, row: 1},
                    {zone: "center", column: 1, row: 1},
                    {zone: "right", column: 2, row: 1},
                    {zone: "bottom", column: 1, row: 2}
                ]

                Rectangle {
                    required property var modelData
                    width: root.style.drop.compass.cellSize
                    height: root.style.drop.compass.cellSize
                    x: modelData.column * (root.style.drop.compass.cellSize + 2)
                    y: modelData.row * (root.style.drop.compass.cellSize + 2)
                    radius: root.style.button.radius
                    color: (compass.parent.zone === modelData.zone)
                        ? root.style.colors.accent
                        : root.style.colors.header
                    border.color: root.style.colors.accent
                    border.width: 1
                    opacity: (compass.parent.zone === modelData.zone) ? 1 : 0.85
                }
            }
        }
    }
    property Component placeholderDelegate: Component {
        Text {
            text: qsTr("Drag a dock here")
            color: root.style.colors.text
            opacity: root.style.placeholder.opacity
            font: root.style.fonts.placeholder
        }
    }
    property Component containerBackgroundDelegate: null
    property Component containerDecorationDelegate: Component {
        Rectangle {
            color: "transparent"
            border.color: root.style.colors.border
            border.width: root.style.frame.border.width
            radius: parent && parent.containerId === "main"
                ? root.style.frame.radius
                : 0
        }
    }
    property Component overflowMenuDelegate: null
    // qmllint enable missing-property

    // Renders every top-level container, including `main`. The loaded item is
    // given a `containerContext` object and exposes the item that renders the
    // dock tree as `dockingSurface`. The default is a DockContainerView.
    property Component containerDelegate: Component {
        DockContainerView {
            containerId: containerContext ? containerContext.containerId : ""
            containerState: containerContext ? containerContext.containerState : null
            floatingWindow: containerContext ? containerContext.floatingWindow : null
            renderReady: containerContext ? containerContext.renderReady : false
        }
    }

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
    signal selectionChanged(var selections)
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
        onSelectionChanged: selections => root.selectionChanged(selections)
    }

    QtObject {
        id: mainContainerContext

        readonly property DockWorkspace workspace: root
        readonly property var floatingWindow: null
        readonly property string containerId: "main"
        readonly property var containerState: root._mainContainer()
        readonly property bool renderReady: true
        readonly property string selectedDockId: root.selectedDock(containerId)
    }

    property Item _canvas: Item {
        parent: root
        x: 0
        y: 0
        width: root.width
        height: root.height

        Loader {
            id: mainContainerContent
            anchors.fill: parent
            sourceComponent: root.containerDelegate
            onLoaded: {
                const container = item as DockContainer
                if (container) {
                    container.containerContext = mainContainerContext
                } else {
                    root._error(
                        "invalid-container-delegate",
                        qsTr("containerDelegate must create a DockContainer")
                    )
                }
            }
        }
    }

    readonly property Item _mainDockingSurface: {
        const container = mainContainerContent.item as DockContainer
        return container ? container.dockingSurface : null
    }

    // Visible DockGroups publish their actual tab geometry for drag hit tests.
    // The key includes the container because node ids are only model identities.
    property var _dockGroupViews: ({})

    function _dockGroupViewKey(containerId, groupId) {
        return containerId + "\n" + groupId
    }

    function _registerDockGroup(group) {
        if (group && group.nodeId)
            _dockGroupViews[_dockGroupViewKey(group.containerId, group.nodeId)] = group
    }

    function _unregisterDockGroup(containerId, groupId, group) {
        const key = _dockGroupViewKey(containerId, groupId)
        if (_dockGroupViews[key] === group)
            delete _dockGroupViews[key]
    }

    function _tabDropInfo(containerId, groupId, globalPoint, excludedDockId) {
        const group = _dockGroupViews[_dockGroupViewKey(containerId, groupId)]
        return group ? group.tabDropInfo(globalPoint, excludedDockId) : null
    }

    // Overlays/controllers are shared by the main canvas and floating surfaces.
    DockDropOverlay {
        id: dropOverlay
        surface: root._mainDockingSurface
        workspace: root
        previewObjectName: "dockDropPreview_main"
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

    function focusDock(dockId) {
        if (!activateDock(dockId))
            return false
        const window = floatingWindowForDock(dockId)
        if (window) {
            window.raise()
            window.requestActivate()
        }
        return true
    }

    function selectedDock(containerId) {
        const container = DockLayout.containerById(snapshot.containers, containerId)
        return container ? container.selected || "" : ""
    }

    function selections() {
        return model.selectionMap()
    }

    function _dockSelected(dockId) {
        model.selectDock(dockId)
        dockActivated(dockId)
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
            DockTypes.dropSurface({state: _mainContainer(), item: _mainDockingSurface})
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
