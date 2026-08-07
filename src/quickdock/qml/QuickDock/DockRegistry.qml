pragma ComponentBehavior: Bound

import QtQuick

// Tracks declarative and dynamically created DockItems and provides a hidden
// parking parent while layout components decide which item is visible.
QtObject {
    id: root

    required property DockWorkspace workspace

    property var _dockRegistry: []

    property Item _parkingLot: Item {
        parent: root.workspace
        visible: false
    }

    // Lookup and validation keep dock ids unique before they enter a layout.
    function dockIds() {
        // Include declarative and dynamically registered items, preserving
        // declaration order while ignoring duplicate object references.
        const result = []
        for (let i = 0; i < _dockRegistry.length; ++i)
            result.push(_dockRegistry[i].dockId)
        for (let i = 0; i < workspace.dockItems.length; ++i) {
            if (result.indexOf(workspace.dockItems[i].dockId) < 0)
                result.push(workspace.dockItems[i].dockId)
        }
        return result
    }

    function dockById(dockId) {
        for (let i = 0; i < _dockRegistry.length; ++i) {
            if (_dockRegistry[i].dockId === dockId)
                return _dockRegistry[i]
        }
        for (let i = 0; i < workspace.dockItems.length; ++i) {
            if (workspace.dockItems[i].dockId === dockId)
                return workspace.dockItems[i]
        }
        return null
    }

    function validateDockItems() {
        const seen = {}
        const items = _dockRegistry.concat(workspace.dockItems)
        for (let i = 0; i < items.length; ++i) {
            const item = items[i]
            if (!item.dockId || !item.dockId.trim())
                throw new Error("Every DockItem must have a non-empty dockId")
            if (seen[item.dockId] && seen[item.dockId] !== item)
                throw new Error("Duplicate DockItem dockId: " + item.dockId)
            seen[item.dockId] = item
        }
    }

    function _registerDockReference(item, takeOwnership) {
        if (!item || typeof item.dockId !== "string" || !item.dockId.trim())
            return workspace._error(
                "invalid-dock",
                qsTr("registerDock() requires a DockItem with a non-empty dockId")
            )

        const existing = dockById(item.dockId)
        if (existing && existing !== item)
            return workspace._error(
                "duplicate-dock-id",
                qsTr("Duplicate DockItem dockId: %1").arg(item.dockId)
            )

        if (_dockRegistry.indexOf(item) >= 0)
            return false

        item._workspaceOwned = !!takeOwnership
        _dockRegistry = _dockRegistry.concat([item])
        parkDockItem(item)

        return true
    }

    // Registration is transactional. Add the reference, ask the workspace to
    // place it, and roll back the registry if policy rejects that placement.
    function registerDock(item, targetDockId, zone, takeOwnership) {
        if (!_registerDockReference(item, takeOwnership))
            return false

        // Try the requested target first. A new dock falls back to the first
        // available group when that target is missing or policy rejects it.
        let placed = false
        if (targetDockId)
            placed = workspace.dockRelative(item.dockId, targetDockId, zone || "center")
        if (!placed)
            placed = workspace.dockToFirstGroup(item.dockId)
        if (!placed) {
            _dockRegistry = _dockRegistry.filter(candidate => candidate !== item)
            return false
        }
        workspace.dockAdded(item.dockId, item)
        if (item.dockId === workspace.centralDockId)
            workspace._ensureCentralDock()
        return true
    }

    // Dynamic creation uses the parking area as its temporary parent until the
    // normal registration path attaches the item to a visible DockGroup.
    function createDock(component, initialProperties, targetDockId, zone) {
        if (!component || typeof component.createObject !== "function") {
            workspace._error(
                "invalid-component",
                qsTr("createDock() requires a DockItem Component")
            )
            return null
        }
        const item = component.createObject(_parkingLot, initialProperties || {})
        if (!item) {
            workspace._error(
                "dock-creation-failed",
                qsTr("Could not create a DockItem from the supplied component")
            )
            return null
        }
        if (!registerDock(item, targetDockId, zone, true)) {
            item.destroy()
            return null
        }
        return item
    }

    function unregisterDock(item) {
        _dockRegistry = _dockRegistry.filter(candidate => candidate !== item)
    }

    function parkDockItem(item) {
        if (!item)
            return
        item.visible = false
        item.parent = _parkingLot
        item.x = 0
        item.y = 0
    }
}
