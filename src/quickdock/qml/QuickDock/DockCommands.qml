pragma ComponentBehavior: Bound

import QtQuick
import "DockLayout.js" as DockLayout
import "DockPolicy.js" as DockPolicy
import "DockTypes.js" as DockTypes

// Every snapshot mutation the workspace exposes, funneled through
// dockModel.commit(). Read-only queries and pure algebra live elsewhere
// (DockWorkspace, DockLayout.js). This is for state transitions only.
QtObject {
    id: root

    required property DockWorkspace workspace
    required property DockModel dockModel

    readonly property var snapshot: workspace.snapshot

    // Removes dockId from containers, re-adds it to the main container via
    // placement policy, and returns the updated containers array (or null
    // if placement failed).
    function _withDockAddedToMain(containers, dockId, centralOverride) {
        const mainIndex = containers.findIndex(container => container.kind === "main")
        const main = containers[mainIndex]
        const nextRoot = _rootWithDockAdded(main.root, dockId, centralOverride)
        if (!nextRoot)
            return null
        containers[mainIndex] = DockLayout.containerWithRoot(main, nextRoot)
        return containers
    }

    function _rootWithDockAdded(mainRoot, dockId, centralOverride) {
        if (!mainRoot)
            return workspace._newGroup([dockId], dockId)

        const item = workspace.dockById(dockId)
        const target = DockLayout.firstGroup(mainRoot)

        if (DockPolicy.canJoinGroup(item, target, workspace.dockById)) {
            return DockLayout.withDockInserted(
                mainRoot,
                target.id,
                dockId,
                "center",
                workspace._newId("tabs"),
                workspace._newId("split"),
                -1,
                workspace.style.split.defaultRatio
            )
        }

        const zone = centralOverride ? "right" : DockPolicy.preferredSplitZone(item)
        if (!zone) {
            workspace._error(
                "dock-policy-denied",
                qsTr("Dock %1 has no allowed placement zone").arg(dockId)
            )
            return null
        }

        return DockLayout.withDockInsertedAtRoot(
            mainRoot,
            dockId,
            zone,
            workspace._newId("tabs"),
            workspace._newId("split"),
            workspace.style.split.defaultRatio
        )
    }

    function resetLayout() {
        // Insert the central dock first so policy-driven placement can use it
        // as the stable anchor while rebuilding the rest of the main tree.
        let ids = workspace.dockIds()
        const centralDockId = workspace.centralDockId
        if (centralDockId && ids.indexOf(centralDockId) >= 0) {
            ids = [centralDockId].concat(ids.filter(id => id !== centralDockId))
        }

        let rootNode = null
        for (let i = 0; i < ids.length; ++i)
            rootNode = _rootWithDockAdded(rootNode, ids[i], ids[i] === centralDockId)

        dockModel.commit(DockTypes.layoutSnapshot({
            version: DockLayout.layoutVersion,
            containers: [DockTypes.mainContainer({id: "main", root: rootNode})],
            hidden: []
        }))
    }

    function _ensureCentralDock() {
        const centralDockId = workspace.centralDockId
        if (!centralDockId)
            return true

        if (!workspace.dockById(centralDockId))
            return workspace._error(
                "central-dock-not-found",
                qsTr("Unknown central dock: %1").arg(centralDockId)
            )
        if (workspace.isDocked(centralDockId) && !workspace.isHidden(centralDockId))
            return true

        const containers = _withDockAddedToMain(
            DockLayout.withoutDock(snapshot.containers, centralDockId),
            centralDockId,
            true
        )
        if (!containers)
            return false

        const hidden = snapshot.hidden.filter(id => id !== centralDockId)
        return dockModel.commit(DockLayout.snapshotWith(containers, hidden))
    }

    function activateDock(dockId) {
        const container = DockLayout.containerForDock(snapshot.containers, dockId)
        if (!container)
            return workspace._error(
                "dock-not-visible",
                qsTr("Dock %1 is not visible").arg(dockId)
            )

        const nextRoot = DockLayout.withActiveDock(container.root, dockId)
        if (nextRoot === container.root) {
            workspace._dockSelected(dockId)
            return true
        }

        const containers = snapshot.containers.slice()
        const index = containers.indexOf(container)

        containers[index] = DockLayout.containerWithRoot(container, nextRoot)
        containers[index].selected = dockId
        dockModel.commit(DockLayout.snapshotWith(containers, snapshot.hidden))
        workspace._dockSelected(dockId)

        return true
    }

    function setSplitRatio(splitId, splitterIndex, ratio) {
        for (let i = 0; i < snapshot.containers.length; ++i) {
            const container = snapshot.containers[i]
            if (DockLayout.findNode(container.root, splitId))
                return dockModel.setSplitRatio(container.id, splitId, splitterIndex, ratio)
        }

        return workspace._error(
            "split-not-found",
            qsTr("Unknown split node: %1").arg(splitId)
        )
    }

    function showDock(dockId) {
        if (!workspace.dockById(dockId))
            return workspace._error(
                "dock-not-found",
                qsTr("Unknown dock: %1").arg(dockId)
            )

        if (!workspace.isHidden(dockId))
            return workspace.isVisible(dockId)

        const hidden = snapshot.hidden.filter(id => id !== dockId)
        const containers = _withDockAddedToMain(
            snapshot.containers.slice(),
            dockId,
            false
        )
        if (!containers)
            return false

        dockModel.commit(DockLayout.snapshotWith(containers, hidden))
        workspace.dockShown(dockId)
        workspace._dockSelected(dockId)

        return true
    }

    function hideDock(dockId) {
        if (!workspace.dockById(dockId))
            return workspace._error(
                "dock-not-found",
                qsTr("Unknown dock: %1").arg(dockId)
            )
        if (dockId === workspace.centralDockId)
            return workspace._error(
                "central-dock-policy",
                qsTr("The central dock cannot be hidden")
            )
        if (workspace.isHidden(dockId))
            return true
        if (!DockLayout.containerForDock(snapshot.containers, dockId))
            return workspace._error(
                "dock-not-visible",
                qsTr("Dock %1 is not visible").arg(dockId)
            )

        const containers = DockLayout.withoutDock(snapshot.containers, dockId)
        const hidden = snapshot.hidden.concat([dockId])

        workspace.parkDockItem(workspace.dockById(dockId))
        dockModel.commit(DockLayout.snapshotWith(containers, hidden))
        workspace.dockHidden(dockId)

        return true
    }

    function closeDock(dockId) {
        const item = workspace.dockById(dockId)
        if (!item)
            return workspace._error(
                "dock-not-found",
                qsTr("Unknown dock: %1").arg(dockId)
            )
        if (!workspace.canCloseDock(dockId))
            return workspace._error(
                "close-not-allowed",
                qsTr("Dock %1 cannot be closed").arg(dockId)
            )

        workspace.dockAboutToClose(dockId, item)
        if (item.closePolicy === DockItem.Hide || !item._workspaceOwned) {
            if (!hideDock(dockId))
                return false
            workspace.dockClosed(dockId)
            return true
        }

        const containers = DockLayout.withoutDock(snapshot.containers, dockId)
        workspace._unregisterDock(item)
        workspace.parkDockItem(item)

        const nextSnapshot = DockLayout.snapshotWith(containers, snapshot.hidden.filter(id => id !== dockId))
        dockModel.commit(nextSnapshot)

        item.destructionCompleted.connect(function(destroyedDockId) {
            Qt.callLater(function() {
                workspace.dockClosed(destroyedDockId)
            })
        })
        item.destroy()

        return true
    }

    function dockToFirstGroup(dockId) {
        if (!workspace.dockById(dockId))
            return workspace._error(
                "dock-not-found",
                qsTr("Unknown dock: %1").arg(dockId)
            )

        const containers = _withDockAddedToMain(
            DockLayout.withoutDock(snapshot.containers, dockId),
            dockId,
            false
        )
        if (!containers)
            return false

        dockModel.commit(DockLayout.snapshotWith(containers, snapshot.hidden))
        workspace._dockSelected(dockId)

        return true
    }

    function dockAsTab(dockId, targetDockId) {
        return dockRelative(dockId, targetDockId, "center")
    }

    function splitDock(dockId, targetDockId, side) {
        return dockRelative(dockId, targetDockId, side)
    }

    function dockRelative(dockId, targetDockId, zone) {
        const validZones = ["center", "left", "right", "top", "bottom"]
        if (!workspace.dockById(dockId))
            return workspace._error(
                "dock-not-found",
                qsTr("Unknown dock: %1").arg(dockId)
            )
        if (!workspace.dockById(targetDockId))
            return workspace._error(
                "target-not-found",
                qsTr("Unknown target dock: %1").arg(targetDockId)
            )
        if (validZones.indexOf(zone) < 0)
            return workspace._error(
                "invalid-zone",
                qsTr("Invalid dock zone: %1").arg(zone)
            )

        const targetContainer = DockLayout.containerForDock(snapshot.containers, targetDockId)
        const targetGroup = targetContainer
                ? DockLayout.findGroupForDock(targetContainer.root, targetDockId)
                : null

        if (!targetGroup)
            return workspace._error(
                "target-not-visible",
                qsTr("Target dock %1 is not visible").arg(targetDockId)
            )

        return _dockAt(dockId, targetContainer.id, targetGroup.id, zone, -1, false)
    }

    function canDropDock(dockId, target) {
        const item = workspace.dockById(dockId)
        if (!item || !target || dockId === workspace.centralDockId)
            return false
        if (!DockPolicy.zoneAllowed(item, target.zone))
            return false
        if (target.zone !== "center")
            return true

        const container = DockLayout.containerById(snapshot.containers, target.containerId)
        if (!container)
            return false
        if (!container.root || !target.groupId)
            return true
        if (!item.tabbable)
            return false

        const group = DockLayout.findGroup(container.root, target.groupId)
        if (!group)
            return false

        return DockPolicy.groupAcceptsTabbable(group, dockId, workspace.dockById)
    }

    function canDropFloatingContainer(containerId, target) {
        const source = DockLayout.containerById(snapshot.containers, containerId)
        if (!source || source.kind !== "floating" || !target || target.containerId === containerId)
            return false
        if (target.zone === "center" && (!source.root || source.root.kind !== "tabs"))
            return false

        const docks = DockLayout.collectDocks(source.root)
        if (!docks.length)
            return false
        for (let i = 0; i < docks.length; ++i) {
            if (!canDropDock(docks[i], target))
                return false
        }
        return true
    }

    function _dockAt(dockId, targetContainerId, targetGroupId, zone, tabIndex, outer) {
        const source = DockLayout.containerForDock(snapshot.containers, dockId)
        const sourceGroup = source
                ? DockLayout.findGroupForDock(source.root, dockId)
                : null

        const targetPolicy = DockTypes.dropTarget({
            containerId: targetContainerId,
            groupId: targetGroupId,
            zone: zone,
            outer: !!outer,
            tabIndex: tabIndex
        })

        if (!canDropDock(dockId, targetPolicy))
            return workspace._error(
                "dock-policy-denied",
                qsTr("Dock %1 is not allowed in the %2 zone").arg(dockId).arg(zone)
            )

        if (source && source.id === targetContainerId) {
            if (sourceGroup && sourceGroup.id === targetGroupId && !outer) {
                if (zone === "center") {
                    if (tabIndex < 0)
                        return activateDock(dockId)
                    const fromIndex = sourceGroup.docks.indexOf(dockId)
                    let toIndex = Math.max(
                        0,
                        Math.min(
                            sourceGroup.docks.length,
                            Math.floor(tabIndex)
                        )
                    )
                    if (fromIndex < toIndex)
                        toIndex -= 1
                    let nextRoot = DockLayout.withTabMoved(
                        source.root,
                        sourceGroup.id,
                        fromIndex,
                        toIndex
                    )
                    if (nextRoot === source.root)
                        return activateDock(dockId)
                    nextRoot = DockLayout.withActiveDock(nextRoot, dockId)
                    const containers = snapshot.containers.slice()
                    const sourceIndex = containers.indexOf(source)
                    containers[sourceIndex] = DockLayout.containerWithRoot(source, nextRoot)
                    dockModel.commit(DockLayout.snapshotWith(containers, snapshot.hidden))
                    workspace._dockSelected(dockId)
                    return true
                }
                if (sourceGroup.docks.length === 1)
                    return true
            }
        }

        const containers = DockLayout.withoutDock(snapshot.containers, dockId)
        const targetIndex = containers.findIndex(
            container => container.id === targetContainerId
        )
        if (targetIndex < 0)
            return workspace._error(
                "container-not-found",
                qsTr("Unknown target container: %1").arg(targetContainerId)
            )

        const target = containers[targetIndex]
        if (!outer && target.root && !DockLayout.findGroup(target.root, targetGroupId))
            return workspace._error(
                "group-not-found",
                qsTr("Unknown target tab group: %1").arg(targetGroupId)
            )

        let nextRoot = null
        if (outer) {
            nextRoot = DockLayout.withDockInsertedAtRoot(
                target.root,
                dockId,
                zone,
                workspace._newId("tabs"),
                workspace._newId("split"),
                workspace.style.split.defaultRatio
            )
        } else if (!target.root) {
            nextRoot = workspace._newGroup([dockId], dockId)
        } else {
            nextRoot = DockLayout.withDockInserted(
                target.root,
                targetGroupId,
                dockId,
                zone,
                workspace._newId("tabs"),
                workspace._newId("split"),
                tabIndex,
                workspace.style.split.defaultRatio
            )
        }

        if (nextRoot === target.root)
            return workspace._error(
                "dock-operation-failed",
                qsTr("The requested dock operation had no target")
            )

        containers[targetIndex] = DockLayout.containerWithRoot(target, nextRoot)
        dockModel.commit(DockLayout.snapshotWith(containers, snapshot.hidden))
        workspace._dockSelected(dockId)

        return true
    }

    function _dockFloatingContainerAt(
        containerId,
        targetContainerId,
        targetGroupId,
        zone,
        tabIndex,
        outer
    ) {
        const source = DockLayout.containerById(snapshot.containers, containerId)
        const targetPolicy = DockTypes.dropTarget({
            containerId: targetContainerId,
            groupId: targetGroupId,
            zone: zone,
            outer: !!outer,
            tabIndex: tabIndex
        })

        if (!canDropFloatingContainer(containerId, targetPolicy))
            return workspace._error(
                "dock-policy-denied",
                qsTr("The floating container is not allowed in the %1 zone").arg(zone)
            )

        const containers = snapshot.containers.filter(container => container.id !== containerId)
        const targetIndex = containers.findIndex(container => container.id === targetContainerId)
        if (targetIndex < 0)
            return workspace._error(
                "container-not-found",
                qsTr("Unknown target container: %1").arg(targetContainerId)
            )

        const target = containers[targetIndex]
        if (!outer && target.root && !DockLayout.findGroup(target.root, targetGroupId))
            return workspace._error(
                "group-not-found",
                qsTr("Unknown target tab group: %1").arg(targetGroupId)
            )

        let nextRoot = null
        if (outer) {
            nextRoot = DockLayout.withNodeInsertedAtRoot(
                target.root,
                source.root,
                zone,
                workspace._newId("split"),
                workspace.style.split.defaultRatio
            )
        } else if (!target.root) {
            nextRoot = source.root
        } else {
            nextRoot = DockLayout.withNodeInserted(
                target.root,
                targetGroupId,
                source.root,
                zone,
                workspace._newId("split"),
                tabIndex,
                workspace.style.split.defaultRatio
            )
        }

        if (nextRoot === target.root)
            return workspace._error(
                "dock-operation-failed",
                qsTr("The floating container could not be inserted at the target")
            )

        containers[targetIndex] = DockLayout.containerWithRoot(target, nextRoot)
        dockModel.commit(DockLayout.snapshotWith(containers, snapshot.hidden))

        const activeGroup = DockLayout.firstGroup(source.root)
        if (activeGroup)
            workspace._dockSelected(activeGroup.active)
        return true
    }

    function dockFloatingContainer(containerId) {
        const container = DockLayout.containerById(snapshot.containers, containerId)
        if (!container || container.kind !== "floating")
            return workspace._error(
                "container-not-found",
                qsTr("Unknown floating container: %1").arg(containerId)
            )

        const docks = DockLayout.collectDocks(container.root)
        let value = snapshot
        for (let i = 0; i < docks.length; ++i) {
            // Move one dock at a time so each insertion is checked against
            // the current placement policy and preserves the snapshot order.
            const containers = _withDockAddedToMain(
                DockLayout.withoutDock(value.containers, docks[i]),
                docks[i],
                false
            )
            if (!containers)
                return false
            value = DockLayout.snapshotWith(containers, value.hidden)
        }

        dockModel.commit(value)
        return true
    }

    function saveLayout() {
        return JSON.stringify(snapshot)
    }

    function restoreLayout(state) {
        try {
            const parsed = typeof state === "string"
                    ? JSON.parse(state)
                    : JSON.parse(JSON.stringify(state))

            if (Number(parsed.version) !== DockLayout.layoutVersion)
                return workspace._error(
                    "unsupported-layout-version",
                    qsTr("The docking layout version is not supported")
                )

            const next = dockModel.sanitizeSnapshot(
                parsed,
                workspace.dockIds(),
                workspace._newId,
                workspace._clampFloatingGeometry
            )
            if (!next)
                return workspace._error(
                    "invalid-layout",
                    qsTr("The docking layout is invalid")
                )

            dockModel.commitRestored(next)
            _ensureCentralDock()
            for (let i = 0; i < next.containers.length; ++i)
                _emitActiveDocks(next.containers[i].root)

            return true
        } catch (error) {
            return workspace._error("invalid-layout", qsTr("Could not restore docking layout: %1").arg(error))
        }
    }

    function _emitActiveDocks(node) {
        if (!node)
            return
        if (node.kind === "tabs") {
            workspace._dockSelected(node.active)
            return
        }

        for (let i = 0; i < node.children.length; ++i)
            _emitActiveDocks(node.children[i])
    }
}
