pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import "DockLayout.js" as DockLayout
import "DockOps.js" as DockOps
import "DockTypes.js" as DockTypes

// The docking surface and its public API. Every layout change is a pure
// operation on the current snapshot, committed through _apply. The views,
// floating windows, and signals all follow the snapshot.
Item {
    id: root

    default property list<DockItem> dockItems

    property DockStyle style: DockStyle {}
    readonly property DockBehavior behavior: DockBehavior {}

    // Replaceable components. Each delegate declares the values it uses as
    // `required property`.
    property Component headerDelegate: Component { DockHeader {} }
    property Component tabDelegate: Component { DockHeader {} }
    property Component titleBarDelegate: Component { DockTitleBar {} }
    // Optional. Created once in every floating window, below its content, to
    // integrate the frameless window with the platform: a native frame and
    // shadow, snap layouts, and the like. See DockFloatingWindow.
    property Component windowIntegrationDelegate: null
    property Component overflowMenuDelegate: Component { DockOverflowMenu {} }
    property Component containerDelegate: Component { DockContainerView {} }
    property Component dropCompassDelegate: Component { DockDropCompass {} }
    property Component containerBackgroundDelegate: null
    property Component containerDecorationDelegate: Component {
        Rectangle {
            required property DockStyle style
            required property string containerId
            color: "transparent"
            border.color: style.colors.border
            border.width: style.frame.borderWidth
            radius: containerId === "main" ? style.frame.radius : 0
        }
    }
    property Component splitterDelegate: Component {
        Rectangle {
            required property DockStyle style
            required property bool hovered
            required property bool pressed
            color: hovered || pressed ? style.colors.accent : style.colors.splitter
        }
    }
    property Component dropIndicatorDelegate: Component {
        Rectangle {
            required property DockStyle style
            color: style.colors.preview
            border.color: style.colors.accent
            border.width: style.drop.indicatorBorderWidth
            radius: style.drop.indicatorRadius
        }
    }
    property Component placeholderDelegate: Component {
        Item {
            id: placeholder
            required property DockStyle style
            implicitWidth: placeholderText.implicitWidth
            implicitHeight: placeholderText.implicitHeight

            Text {
                id: placeholderText
                text: qsTr("Drag a dock here")
                color: placeholder.style.colors.placeholder
                font: placeholder.style.fonts.placeholder
            }
        }
    }
    property Component dragPreviewDelegate: Component {
        Rectangle {
            id: dragVisual
            required property DockStyle style
            required property DockItem dock
            required property url snapshotSource

            color: style.colors.dragPreviewFallback
            border.color: style.colors.accent
            border.width: style.dragPreview.borderWidth
            radius: style.dragPreview.radius
            clip: true

            Image {
                id: snapshotImage
                anchors.fill: parent
                source: dragVisual.snapshotSource
                visible: status === Image.Ready
            }

            // Until the captured image is ready, show a bare header.
            Rectangle {
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: dragVisual.border.width
                }
                height: dragVisual.style.header.height
                visible: !snapshotImage.visible
                color: dragVisual.style.colors.activeHeader

                Text {
                    anchors {
                        fill: parent
                        leftMargin: dragVisual.style.header.horizontalPadding
                        rightMargin: dragVisual.style.header.horizontalPadding
                    }
                    verticalAlignment: Text.AlignVCenter
                    text: dragVisual.dock ? dragVisual.dock.title : ""
                    color: dragVisual.style.colors.activeText
                    font: dragVisual.style.fonts.title
                    elide: Text.ElideRight
                }
            }
        }
    }

    // The dock that anchors the main area: it cannot be closed, hidden,
    // floated, or moved, and a restored layout always docks it.
    property string centralDockId: ""
    property alias debugLayout: model.debugLayout
    property alias undoLimit: model.undoLimit

    readonly property int layoutVersion: DockLayout.layoutVersion
    readonly property var snapshot: model.snapshot
    readonly property var hiddenDocks: snapshot.hidden
    readonly property bool canUndoLayout: model.canUndo
    readonly property bool canRedoLayout: model.canRedo
    readonly property bool dragging: dragController.active
    readonly property bool hostClosing: _hostClosing

    // Structural changes: every undoable change, undo and redo, and restore.
    signal layoutChanged()
    signal splitRatioChanged(string splitId, int splitterIndex)
    // A dock became the selected dock of its container.
    signal dockActivated(string dockId)
    signal dockAdded(string dockId, var dockItem)
    signal dockShown(string dockId)
    signal dockHidden(string dockId)
    signal dockAboutToClose(string dockId, var dockItem)
    signal dockClosed(string dockId)
    signal errorOccurred(string code, string message)
    // The declared DockItems are registered and the first layout is built.
    signal initialized()

    property bool _initialized: false
    property bool _initializing: false
    property bool _hostClosing: false
    property int _nextObjectId: 0
    property var _views: ({})

    readonly property var _metrics: ({header: style.header.height, splitter: style.frame.splitterSize})

    readonly property var _messages: ({
        "dock-not-found": qsTr("Unknown dock: %1"),
        "target-not-found": qsTr("Unknown target dock: %1"),
        "target-not-visible": qsTr("Target dock %1 is not visible"),
        "dock-not-visible": qsTr("Dock %1 is not visible"),
        "invalid-zone": qsTr("Invalid dock zone: %1"),
        "dock-policy-denied": qsTr("%1 is not allowed in the %2 zone"),
        "no-placement": qsTr("Dock %1 has no allowed placement"),
        "central-dock-policy": qsTr("The central dock cannot be closed, hidden, floated, or moved"),
        "central-dock-not-found": qsTr("Unknown central dock: %1"),
        "close-not-allowed": qsTr("Dock %1 cannot be closed"),
        "float-not-allowed": qsTr("Dock %1 cannot be floated"),
        "container-not-found": qsTr("Unknown container: %1"),
        "group-not-found": qsTr("Unknown tab group: %1"),
        "split-not-found": qsTr("Unknown split: %1"),
        "dock-operation-failed": qsTr("The dock operation had no target"),
        "invalid-layout": qsTr("The docking layout is invalid"),
        "unsupported-layout-version": qsTr("Docking layout version %1 is not supported"),
        "invalid-dock": qsTr("A DockItem needs a non-empty dockId"),
        "duplicate-dock-id": qsTr("Duplicate DockItem dockId: %1"),
        "dock-id-changed": qsTr("The dockId of registered dock %1 cannot change"),
        "invalid-component": qsTr("createDock() needs a DockItem Component"),
        "dock-creation-failed": qsTr("Could not create a DockItem from the component")
    })

    DockRegistry {
        id: registry
        parkingParent: root
        onDockIdChangeRejected: dockId => root._error("dock-id-changed", [dockId])
    }

    DockModel {
        id: model
        dockIds: registry.ids
        onChanged: (previous, current, structural) => {
            floatingController.sync(current)
            if (structural)
                root.layoutChanged()
            root._emitLifecycle(previous, current)
        }
    }

    DockFloatingController {
        id: floatingController
        workspace: root
    }

    DockDragPreview {
        id: dragPreview
        workspace: root
    }

    DockDragController {
        id: dragController
        workspace: root
        preview: dragPreview
    }

    DockDelegateHost {
        anchors.fill: parent
        delegate: root.containerDelegate
        context: root._initialized ? mainContext : null
    }

    QtObject {
        id: mainContext
        readonly property DockWorkspace workspace: root
        readonly property DockStyle style: root.style
        readonly property string containerId: "main"
        readonly property var container: DockLayout.mainContainer(root.snapshot.containers)
        readonly property var floatingWindow: null
        readonly property bool renderReady: true
    }

    property Connections _hostWindowConnections: Connections {
        target: root.Window.window
        ignoreUnknownSignals: true

        function onClosing(_close) {
            Qt.callLater(root._closeFloatingWindowsIfHostClosed)
        }
    }

    Component.onCompleted: _initialize()
    onCentralDockIdChanged: {
        if (_initialized)
            _run(true, (snapshot, ctx) => DockOps.ensureCentral(snapshot, ctx))
    }

    // --- Docks ------------------------------------------------------------------

    function dockIds() {
        return registry.ids.slice()
    }

    function dockById(dockId) {
        return registry.item(dockId)
    }

    // Adds an existing DockItem next to `targetDockId` in `zone`, or to the
    // main area when that is not possible. With `takeOwnership`, closing the
    // dock destroys the item.
    function registerDock(item, targetDockId, zone, takeOwnership) {
        _initialize()
        if (item && registry.item(item.dockId) === item)
            return false
        const code = registry.add(item, takeOwnership)
        if (code)
            return _error(code, [item ? item.dockId : ""])

        const dockId = item.dockId
        const ctx = _context()
        let result = targetDockId ? DockOps.moveNextTo(snapshot, dockId, targetDockId, zone, ctx) : null
        if (!result || result.error)
            result = DockOps.dockToMain(snapshot, dockId, ctx)
        if (!_apply(result, true)) {
            registry.remove(dockId)
            return false
        }
        dockAdded(dockId, item)
        return true
    }

    // Creates a DockItem from `component` and registers it as owned.
    function createDock(component, initialProperties, targetDockId, zone) {
        _initialize()
        if (!component || typeof component.createObject !== "function") {
            _error("invalid-component")
            return null
        }
        const item = component.createObject(registry.parkingLot, initialProperties || {})
        if (!item) {
            _error("dock-creation-failed")
            return null
        }
        if (!registerDock(item, targetDockId, zone, true)) {
            item.destroy()
            return null
        }
        return item
    }

    // "docked", "floating", "hidden", or "" for an unknown dock.
    function dockState(dockId) {
        if (!dockById(dockId))
            return ""
        if (snapshot.hidden.indexOf(dockId) >= 0)
            return "hidden"
        const container = DockLayout.containerForDock(snapshot.containers, dockId)
        return !container ? "" : container.kind === "main" ? "docked" : "floating"
    }

    function containerOf(dockId) {
        const container = DockLayout.containerForDock(snapshot.containers, dockId)
        return container ? container.id : ""
    }

    function neighborsOf(dockId) {
        const container = DockLayout.containerForDock(snapshot.containers, dockId)
        return container ? DockLayout.neighborsOf(container.root, dockId) : []
    }

    function selectedDock(containerId) {
        const container = DockLayout.containerById(snapshot.containers, containerId || "main")
        return container ? container.selected : ""
    }

    function canCloseDock(dockId) {
        return DockOps.canClose(_context(), dockId)
    }

    function canFloatDock(dockId) {
        return DockOps.canFloat(_context(), dockId)
    }

    function floatingWindowForDock(dockId) {
        return floatingController.windowForDock(dockId)
    }

    // --- Layout -----------------------------------------------------------------

    function resetLayout() {
        return _run(true, (snapshot, ctx) => DockOps.reset(snapshot, dockIds(), ctx))
    }

    // Docks `dockId` next to `targetDockId`: "center" adds it as a tab,
    // "left", "right", "top", or "bottom" splits the target's group.
    function moveDock(dockId, targetDockId, zone) {
        return _run(true, (snapshot, ctx) => DockOps.moveNextTo(snapshot, dockId, targetDockId, zone, ctx))
    }

    function dockToMain(dockId) {
        return _run(true, (snapshot, ctx) => DockOps.dockToMain(snapshot, dockId, ctx))
    }

    // Docks a floating container back with its split layout intact.
    function dockContainerToMain(containerId) {
        return _run(true, (snapshot, ctx) => DockOps.dockContainerToMain(snapshot, containerId, ctx))
    }

    // Floats a dock. Omitted coordinates cascade from behavior.floatingOrigin
    // and an omitted size uses the dock's preferredSize.
    function floatDock(dockId, x, y, width, height) {
        return _run(true, (snapshot, ctx) => {
            const placed = _floatingPlacement(snapshot, dockId, x, y, width, height)
            return DockOps.float(snapshot, dockId, placed.geometry, placed.screen, ctx)
        })
    }

    function hideDock(dockId) {
        return _run(true, (snapshot, ctx) => DockOps.hide(snapshot, dockId, ctx))
    }

    function showDock(dockId) {
        return _run(true, (snapshot, ctx) => DockOps.show(snapshot, dockId, ctx))
    }

    // Removes a dock. A dock with closePolicy Hide, or one the workspace does
    // not own, is hidden. An owned one is destroyed.
    function closeDock(dockId) {
        const item = dockById(dockId)
        if (!item)
            return _error("dock-not-found", [dockId])
        if (!canCloseDock(dockId))
            return _error(dockId === centralDockId ? "central-dock-policy" : "close-not-allowed", [dockId])

        dockAboutToClose(dockId, item)
        if (item.closePolicy === DockItem.Hide || !registry.isOwned(dockId)) {
            if (!hideDock(dockId))
                return false
            dockClosed(dockId)
            return true
        }
        registry.remove(dockId)
        registry.park(item)
        _run(true, snapshot => DockOps.remove(snapshot, dockId))
        item.destructionCompleted.connect(destroyedId => Qt.callLater(() => root.dockClosed(destroyedId)))
        item.destroy()
        return true
    }

    // Shows a dock in its group and makes it its container's selected dock.
    // Selection is not an undo step.
    function activateDock(dockId) {
        return _run(false, snapshot => DockOps.activate(snapshot, dockId))
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

    function setSplitRatio(splitId, splitterIndex, ratio) {
        const before = snapshot
        if (!_run(false, snapshot => DockOps.setSplitRatio(snapshot, splitId, splitterIndex, ratio)))
            return false
        if (snapshot !== before)
            splitRatioChanged(splitId, splitterIndex)
        return true
    }

    // --- Persistence and history -----------------------------------------------

    function saveLayout() {
        return JSON.stringify(snapshot)
    }

    // Restores a layout from saveLayout(). Unknown docks are dropped, docks
    // the layout does not mention are added to the main area, and floating
    // windows are fitted to the screens that exist now.
    function restoreLayout(state) {
        _initialize()
        let parsed = null
        try {
            parsed = typeof state === "string" ? JSON.parse(state) : JSON.parse(JSON.stringify(state))
        } catch (error) {
            return _error("invalid-layout")
        }
        if (!parsed || typeof parsed !== "object")
            return _error("invalid-layout")
        if (Number(parsed.version) !== layoutVersion)
            return _error("unsupported-layout-version", [parsed.version])

        const ctx = _context()
        let next = DockOps.sanitize(parsed, dockIds(), ctx)
        if (!next)
            return _error("invalid-layout")
        const central = DockOps.ensureCentral(next, ctx)
        if (!central.error)
            next = central.snapshot
        model.set(next, true)
        return true
    }

    function undoLayout() {
        return model.undo()
    }

    function redoLayout() {
        return model.redo()
    }

    // Forgets undo and redo steps, e.g. after restoring a layout at startup.
    function clearLayoutHistory() {
        model.clearHistory()
    }

    // --- Dragging ---------------------------------------------------------------
    // DockDragArea drives these for the built-in headers and title bars.

    // Starts a drag of `options.dockId` (a preview follows the pointer) or of
    // the floating container `options.containerId` (its window follows).
    // `pressPoint` is the global press position. `source` is the item the
    // preview shows (the dock's group by default).
    function beginDrag(options) {
        return dragController.begin(options || {})
    }

    // Returns the drop target under `globalPoint`, or null.
    function moveDrag(globalPoint) {
        return dragController.move(globalPoint)
    }

    function endDrag(globalPoint) {
        return dragController.end(globalPoint)
    }

    function cancelDrag() {
        dragController.cancel()
    }

    // --- Internals --------------------------------------------------------------

    function _initialize() {
        if (_initialized || _initializing)
            return
        _initializing = true
        for (let i = 0; i < dockItems.length; ++i) {
            const code = registry.add(dockItems[i], false)
            if (code)
                _error(code, [dockItems[i].dockId])
        }
        _apply(DockOps.reset(snapshot, dockIds(), _context()), false)
        _initializing = false
        _initialized = true
        initialized()
    }

    function _context() {
        return {
            newId: prefix => root._newId(prefix),
            dock: dockId => root.dockById(dockId),
            centralDockId: centralDockId,
            defaultRatio: behavior.defaultSplitRatio,
            fitFloating: (geometry, node, screen) => root._fitFloating(geometry, node, screen)
        }
    }

    function _newId(prefix) {
        return prefix + "_" + (++_nextObjectId)
    }

    // Runs `operation(snapshot, ctx)` and commits its result.
    function _run(history, operation) {
        _initialize()
        return _apply(operation(snapshot, _context()), history)
    }

    // Commits an operation result, activating the dock it selects as part of
    // the same change. Returns false (after reporting) for an error.
    function _apply(result, history) {
        if (result.error)
            return _error(result.error, result.args)
        let next = result.snapshot
        if (result.select) {
            const selected = DockOps.activate(next, result.select)
            if (!selected.error)
                next = selected.snapshot
        }
        model.set(next, history)
        return true
    }

    function _error(code, args) {
        let message = _messages[code] || code
        const values = args || []
        for (let i = 0; i < values.length; ++i)
            message = message.arg(values[i])
        errorOccurred(code, message)
        return false
    }

    // Lifecycle signals come from comparing snapshots, so undo, redo, and
    // restore emit them like any other change.
    function _emitLifecycle(previous, current) {
        for (let i = 0; i < current.hidden.length; ++i) {
            if (previous.hidden.indexOf(current.hidden[i]) < 0)
                dockHidden(current.hidden[i])
        }
        for (let i = 0; i < previous.hidden.length; ++i) {
            const dockId = previous.hidden[i]
            if (current.hidden.indexOf(dockId) < 0 && DockLayout.containerForDock(current.containers, dockId))
                dockShown(dockId)
        }
        for (let i = 0; i < current.containers.length; ++i) {
            const container = current.containers[i]
            const before = DockLayout.containerById(previous.containers, container.id)
            if (container.selected && (!before || before.selected !== container.selected))
                dockActivated(container.selected)
        }
    }

    function _dockLimits(dockId) {
        const item = registry.item(dockId)
        return item ? {minimum: item.minimumSize, maximum: item.maximumSize} : null
    }

    function _sizeLimits(node) {
        return DockLayout.sizeLimitsOf(node, _dockLimits, _metrics)
    }

    function _floatingLimits(node) {
        return DockLayout.floatingLimits(_sizeLimits(node),
                                         DockLayout.collectDocks(node).length > 1 ? style.header.height : 0,
                                         behavior.floatingMinimumSize)
    }

    function _finite(value) {
        return value !== null && value !== undefined && value !== "" && isFinite(Number(value))
    }

    // Screens as {name, area}, from the screens that exist now.
    function _screens() {
        const screens = Qt.application.screens
        const result = []
        for (let i = 0; i < screens.length; ++i) {
            const screen = screens[i]
            result.push({name: screen.name, area: Qt.rect(screen.virtualX, screen.virtualY, screen.width, screen.height)})
        }
        return result
    }

    function _screenAt(rect) {
        const x = rect.x + rect.width / 2
        const y = rect.y + rect.height / 2
        return _screens().find(screen => x >= screen.area.x && y >= screen.area.y
                                         && x < screen.area.x + screen.area.width
                                         && y < screen.area.y + screen.area.height) || null
    }

    function _hostScreen() {
        const screens = _screens()
        return screens.find(screen => screen.name === root.Screen.name) || screens[0] || null
    }

    function _floatingOrigin(index) {
        const origin = mapToGlobal(width * behavior.floatingOrigin.x, height * behavior.floatingOrigin.y)
        return Qt.point(origin.x + index * behavior.floatingCascadeOffset.x,
                        origin.y + index * behavior.floatingCascadeOffset.y)
    }

    // Geometry for a newly floated dock. Explicit coordinates are kept (only
    // pulled onto the screen they are on). Omitted ones cascade on the host
    // screen.
    function _floatingPlacement(snapshot, dockId, x, y, width, height) {
        const item = dockById(dockId)
        const size = item ? item.preferredSize : behavior.floatingDefaultSize
        const explicit = _finite(x) && _finite(y)
        const cascade = DockLayout.withoutDock(snapshot.containers, dockId)
            .filter(container => container.kind === "floating").length
        const origin = _floatingOrigin(cascade)
        const rect = {
            x: explicit ? Number(x) : origin.x,
            y: explicit ? Number(y) : origin.y,
            width: _finite(width) ? Number(width) : size.width,
            height: _finite(height) ? Number(height) : size.height
        }
        const screen = _screenAt(rect) || (explicit ? null : _hostScreen())
        const geometry = DockLayout.fitGeometry(rect, _floatingLimits(DockTypes.tabs("", [dockId])),
                                                screen ? screen.area : null)
        const placedOn = _screenAt(geometry) || _hostScreen()
        return {geometry: geometry, screen: placedOn ? placedOn.name : ""}
    }

    // Fits saved floating geometry to its saved screen, the screen it is on,
    // or the host screen, in that order, so a restored window is reachable.
    function _fitFloating(geometry, node, screenName) {
        const saved = geometry || {}
        const origin = _floatingOrigin(0)
        const rect = {
            x: _finite(saved.x) ? Number(saved.x) : origin.x,
            y: _finite(saved.y) ? Number(saved.y) : origin.y,
            width: _finite(saved.width) ? Number(saved.width) : behavior.floatingDefaultSize.width,
            height: _finite(saved.height) ? Number(saved.height) : behavior.floatingDefaultSize.height
        }
        const screen = (screenName && _screens().find(candidate => candidate.name === screenName))
            || _screenAt(rect) || _hostScreen()
        return {
            geometry: DockLayout.fitGeometry(rect, _floatingLimits(node), screen ? screen.area : null),
            screen: screen ? screen.name : ""
        }
    }

    // Called by a floating window after it was moved or resized.
    function _setFloatingGeometry(containerId, rect, screenName) {
        const container = DockLayout.containerById(snapshot.containers, containerId)
        if (!container || container.kind !== "floating")
            return false
        const geometry = DockLayout.fitGeometry(rect, _floatingLimits(container.root), null)
        return _run(false, snapshot => DockOps.setGeometry(snapshot, containerId, geometry,
                                                           screenName || container.screen))
    }

    function _parkDock(item) {
        registry.park(item)
    }

    function _windowForContainer(containerId) {
        return floatingController.windowForContainer(containerId)
    }

    function _registerView(view) {
        for (const id in _views) {
            if (_views[id] === view)
                delete _views[id]
        }
        _views[view.containerId] = view
    }

    function _unregisterView(view) {
        if (_views[view.containerId] === view)
            delete _views[view.containerId]
    }

    // Container views in drop-test order: floating windows (the active one
    // first), then the main area.
    function _dropViews() {
        const result = []
        const windows = floatingController.windows()
        for (let i = 0; i < windows.length; ++i) {
            if (_views[windows[i].containerId])
                result.push(_views[windows[i].containerId])
        }
        if (_views.main)
            result.push(_views.main)
        return result
    }

    function _groupItemForDock(dockId) {
        const container = DockLayout.containerForDock(snapshot.containers, dockId)
        const view = container ? _views[container.id] : null
        const group = view ? DockLayout.findGroupForDock(container.root, dockId) : null
        return group ? view.groupItem(group.id) : null
    }

    function _closeFloatingWindowsIfHostClosed() {
        const host = root.Window.window
        if (host && host.visible)
            return
        _hostClosing = true
        cancelDrag()
        floatingController.closeAll()
    }
}
