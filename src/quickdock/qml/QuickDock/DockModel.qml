pragma ComponentBehavior: Bound

import QtQuick
import "DockLayout.js" as DockLayout
import "DockTypes.js" as DockTypes

// Snapshot store for the docking tree. All mutations replace the immutable
// snapshot and optionally record history so visual components stay stateless.
QtObject {
    id: root

    property bool debugLayout: false
    property int undoLimit: 50
    readonly property var snapshot: _snapshot
    readonly property bool canUndo: _undoStack.length > 0
    readonly property bool canRedo: _redoStack.length > 0

    signal layoutChanged()
    signal splitRatioChanged(string splitId, int splitterIndex)
    signal containerGeometryChanged(string containerId)

    property var _snapshot: DockTypes.layoutSnapshot({
        version: DockLayout.layoutVersion,
        containers: [DockTypes.mainContainer({id: "main", root: null})],
        hidden: []
    })
    property var _undoStack: []
    property var _redoStack: []

    // Debug mode freezes snapshots to expose accidental in-place mutations.
    onDebugLayoutChanged: {
        if (debugLayout)
            DockLayout.deepFreeze(_snapshot)
    }

    function _prepared(value) {
        if (debugLayout)
            DockLayout.deepFreeze(value)
        return value
    }

    function _pushUndo(value) {
        let next = _undoStack.concat([value])
        if (next.length > undoLimit)
            next = next.slice(next.length - undoLimit)
        _undoStack = next
        _redoStack = []
    }

    function replaceSnapshot(value, recordUndo) {
        if (!value || value === _snapshot)
            return false
        if (recordUndo === undefined || recordUndo)
            _pushUndo(_snapshot)
        _snapshot = _prepared(value)
        layoutChanged()
        return true
    }

    function commit(value) {
        return replaceSnapshot(value, true)
    }

    // Interactive splitter and geometry updates bypass the undo stack but
    // still notify the workspace so native surfaces remain synchronized.
    function setSplitRatio(containerId, splitId, splitterIndex, ratio) {
        const containers = _snapshot.containers
        for (let i = 0; i < containers.length; ++i) {
            const container = containers[i]
            if (container.id !== containerId)
                continue
            const nextRoot = DockLayout.withSplitRatio(
                container.root,
                splitId,
                splitterIndex,
                ratio
            )
            if (nextRoot === container.root)
                return false
            const nextContainers = containers.slice()
            nextContainers[i] = DockLayout.containerWithRoot(container, nextRoot)
            _snapshot = _prepared(DockTypes.layoutSnapshot({
                version: DockLayout.layoutVersion,
                containers: nextContainers,
                hidden: _snapshot.hidden
            }))
            splitRatioChanged(splitId, splitterIndex)
            return true
        }
        return false
    }

    function updateContainerGeometry(containerId, geometry, screenName) {
        const containers = _snapshot.containers
        for (let i = 0; i < containers.length; ++i) {
            const container = containers[i]
            if (container.id !== containerId || container.kind !== "floating")
                continue
            if (container.geometry
                    && container.geometry.x === geometry.x
                    && container.geometry.y === geometry.y
                    && container.geometry.width === geometry.width
                    && container.geometry.height === geometry.height
                    && container.screen === screenName)
                return false
            const nextContainers = containers.slice()
            nextContainers[i] = DockTypes.floatingContainer({
                id: container.id,
                geometry: geometry,
                screen: screenName || container.screen || "",
                root: container.root
            })
            _snapshot = _prepared(DockTypes.layoutSnapshot({
                version: DockLayout.layoutVersion,
                containers: nextContainers,
                hidden: _snapshot.hidden
            }))
            containerGeometryChanged(containerId)
            return true
        }
        return false
    }

    function undo() {
        if (!_undoStack.length)
            return false

        const previous = _undoStack[_undoStack.length - 1]
        _undoStack = _undoStack.slice(0, _undoStack.length - 1)
        _redoStack = _redoStack.concat([_snapshot])
        _snapshot = _prepared(previous)
        layoutChanged()

        return true
    }

    function redo() {
        if (!_redoStack.length)
            return false

        const next = _redoStack[_redoStack.length - 1]
        _redoStack = _redoStack.slice(0, _redoStack.length - 1)
        _undoStack = _undoStack.concat([_snapshot])
        _snapshot = _prepared(next)
        layoutChanged()

        return true
    }

    // Sanitize persisted trees into fresh ids and trusted DockItem references
    // before they enter the live snapshot.
    function _sanitizeNode(raw, valid, used, idFactory) {
        if (!raw || typeof raw !== "object")
            return null

        if (raw.kind === "tabs") {
            const docks = []
            const source = Array.isArray(raw.docks) ? raw.docks : []
            for (let i = 0; i < source.length; ++i) {
                const dockId = String(source[i])
                if (valid[dockId] && !used[dockId]) {
                    docks.push(dockId)
                    used[dockId] = true
                }
            }

            if (!docks.length)
                return null

            const active = docks.indexOf(String(raw.active)) >= 0 ? String(raw.active) : docks[0]
            return DockTypes.tabsNode({
                id: idFactory("tabs"),
                docks: docks,
                active: active
            })
        }

        if (raw.kind !== "split")
            return null

        const children = []
        const sourceChildren = Array.isArray(raw.children) ? raw.children : []
        for (let i = 0; i < sourceChildren.length; ++i) {
            const child = _sanitizeNode(sourceChildren[i], valid, used, idFactory)
            if (child)
                children.push(child)
        }

        if (!children.length)
            return null
        if (children.length === 1)
            return children[0]

        return DockLayout.normalize(DockTypes.splitNode({
            id: idFactory("split"),
            orientation: raw.orientation === "vertical" ? "vertical" : "horizontal",
            weights: DockLayout.normalizedWeights(raw.weights, children.length),
            children: children
        }))
    }

    function sanitizeSnapshot(raw, dockIds, idFactory, clampGeometry) {
        if (!raw || Number(raw.version) !== DockLayout.layoutVersion)
            return null

        // Rebuild the tree from trusted dock ids and fresh node ids. This
        // prevents malformed or stale persisted data from reusing an item
        // more than once or retaining references to removed DockItems.
        const valid = {}
        const used = {}
        for (let i = 0; i < dockIds.length; ++i)
            valid[dockIds[i]] = true

        let mainRoot = null
        let mainSeen = false
        const floating = []
        const source = Array.isArray(raw.containers) ? raw.containers : []
        for (let i = 0; i < source.length; ++i) {
            const saved = source[i]

            if (!saved || typeof saved !== "object")
                continue
            if (saved.kind !== "main" && saved.kind !== "floating")
                continue
            if (saved.kind === "main" && mainSeen)
                continue

            const nextRoot = _sanitizeNode(saved.root, valid, used, idFactory)
            if (saved.kind === "main") {
                mainSeen = true
                mainRoot = nextRoot
                continue
            }
            if (!nextRoot)
                continue

            const geometry = clampGeometry(saved.geometry, nextRoot)
            floating.push(DockTypes.floatingContainer({
                id: idFactory("float"),
                geometry: geometry,
                screen: saved.screen ? String(saved.screen) : "",
                root: nextRoot
            }))
        }

        const hidden = []
        const savedHidden = Array.isArray(raw.hidden) ? raw.hidden : []
        for (let i = 0; i < savedHidden.length; ++i) {
            const dockId = String(savedHidden[i])
            if (valid[dockId] && !used[dockId]) {
                hidden.push(dockId)
                used[dockId] = true
            }
        }

        let first = DockLayout.firstGroup(mainRoot)
        const restoredActive = first ? first.active : ""
        for (let i = 0; i < dockIds.length; ++i) {
            const dockId = dockIds[i]
            if (used[dockId])
                continue

            if (!first) {
                mainRoot = DockTypes.tabsNode({
                    id: idFactory("tabs"),
                    docks: [dockId],
                    active: dockId
                })
                first = mainRoot
            } else {
                mainRoot = DockLayout.withDockInserted(
                    mainRoot,
                    first.id,
                    dockId,
                    "center",
                    idFactory("tabs"),
                    idFactory("split"),
                    -1,
                    0.5
                )
                first = DockLayout.findGroup(mainRoot, first.id)
            }
        }
        if (restoredActive)
            mainRoot = DockLayout.withActiveDock(mainRoot, restoredActive)

        return DockTypes.layoutSnapshot({
            version: DockLayout.layoutVersion,
            containers: [DockTypes.mainContainer({id: "main", root: mainRoot})].concat(floating),
            hidden: hidden
        })
    }
}
