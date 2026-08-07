pragma ComponentBehavior: Bound

import QtQuick
import "DockLayout.js" as DockLayout
import "DockTypes.js" as DockTypes

// Coordinates pointer-driven docking. Hit-tests visible surfaces, computes the
// target zone, and delegates accepted mutations to the workspace.
QtObject {
    id: root
    objectName: "dockDragController"

    required property DockWorkspace workspace
    readonly property var target: _target
    property var _target: null
    property string draggedDockId: ""
    property string draggedContainerId: ""
    property string sourceContainerId: ""
    property string sourceGroupId: ""
    property bool ignoreSourceSurface: false

    // Capture the source location and clear any stale preview when a gesture
    // starts or is canceled.
    function begin(dockId, ignoreSource) {
        draggedDockId = dockId
        draggedContainerId = ""
        const source = workspace._containerForDock(dockId)
        const group = source ? DockLayout.findGroupForDock(source.root, dockId) : null
        sourceContainerId = source ? source.id : ""
        sourceGroupId = group ? group.id : ""
        ignoreSourceSurface = !!ignoreSource
        _target = null
        workspace._hideDropPreviews()
    }

    function beginContainer(containerId, dockId) {
        begin(dockId, true)
        draggedContainerId = containerId
        sourceContainerId = containerId
        sourceGroupId = ""
    }

    function cancel() {
        draggedDockId = ""
        draggedContainerId = ""
        sourceContainerId = ""
        sourceGroupId = ""
        ignoreSourceSurface = false
        _target = null
        workspace._hideDropPreviews()
    }

    // Edge-zone helpers distinguish a container's outer band from the nested
    // node bands used for directional drops inside that container.
    // Shared by _edgeZone (fractional, per-axis band capped in pixels) and
    // _outerEdgeZone (fixed pixel band, same on both axes). Distance is
    // always normalized by its axis's band, which only matters when the
    // two bands differ (the _edgeZone case). With a single shared band
    // normalizing is a no-op on the sort order, so one function covers both.
    function _nearestEdgeZone(x, y, width, height, edgeX, edgeY) {
        const candidates = []
        if (x < edgeX)
            candidates.push({zone: "left", distance: edgeX > 0 ? x / edgeX : 1})
        if (x > width - edgeX)
            candidates.push({zone: "right", distance: edgeX > 0 ? (width - x) / edgeX : 1})
        if (y < edgeY)
            candidates.push({zone: "top", distance: edgeY > 0 ? y / edgeY : 1})
        if (y > height - edgeY)
            candidates.push({zone: "bottom", distance: edgeY > 0 ? (height - y) / edgeY : 1})
        if (!candidates.length)
            return "center"

        candidates.sort((first, second) => first.distance - second.distance)
        return candidates[0].zone
    }

    function _edgeZone(x, y, width, height) {
        const edgeX = Math.min(
            width * workspace.style.drag.edge.fraction,
            workspace.style.drag.edge.maxBandPixels
        )
        const edgeY = Math.min(
            height * workspace.style.drag.edge.fraction,
            workspace.style.drag.edge.maxBandPixels
        )
        return _nearestEdgeZone(x, y, width, height, edgeX, edgeY)
    }

    function _outerEdgeZone(x, y, width, height) {
        const band = Math.max(1, workspace.style.drag.edge.outerBandPixels)
        return _nearestEdgeZone(x, y, width, height, band, band)
    }

    // Hit-testing returns the tab group and rectangle under the pointer. Tab
    // indices are derived separately so center drops can reorder tabs.
    function _tabIndex(node, rect, point) {
        if (!node || node.kind !== "tabs" || !node.docks.length)
            return -1
        if (point.y > rect.y + workspace.style.header.height)
            return -1

        const relative = Math.max(0, Math.min(rect.width, point.x - rect.x))
        return Math.max(
            0,
            Math.min(
                node.docks.length,
                Math.round(relative / Math.max(1, rect.width) * node.docks.length)
            )
        )
    }

    function _hitNode(node, rect, point) {
        if (!node)
            return DockTypes.nodeHit({groupId: "", node: null, rect: rect})
        if (node.kind === "tabs")
            return DockTypes.nodeHit({groupId: node.id, node: node, rect: rect})
        if (node.kind !== "split" || !node.children.length)
            return null

        const horizontal = node.orientation === "horizontal"
        const splitterSize = workspace.style.splitter.size
        const axisLength = horizontal ? rect.width : rect.height
        const available = Math.max(0, axisLength - splitterSize * (node.children.length - 1))
        const lengths = DockLayout.constrainedLengths(
            node,
            available,
            workspace._dockMinimumSize,
            workspace.style.header.height,
            splitterSize
        )

        let offset = 0
        for (let i = 0; i < node.children.length; ++i) {
            const childRect = horizontal
                ? DockTypes.rect({
                    x: rect.x + offset,
                    y: rect.y,
                    width: lengths[i],
                    height: rect.height
                })
                : DockTypes.rect({
                    x: rect.x,
                    y: rect.y + offset,
                    width: rect.width,
                    height: lengths[i]
                })

            const inside = point.x >= childRect.x && point.y >= childRect.y
                && point.x <= childRect.x + childRect.width
                && point.y <= childRect.y + childRect.height

            if (inside)
                return _hitNode(node.children[i], childRect, point)

            offset += lengths[i] + splitterSize
        }

        return null
    }

    function _previewRect(rect, zone) {
        const ratio = workspace.style.split.defaultRatio
        const result = DockTypes.rect({
            x: rect.x,
            y: rect.y,
            width: rect.width,
            height: rect.height
        })

        if (zone === "left") {
            result.width *= ratio
        } else if (zone === "right") {
            result.x += result.width * (1 - ratio)
            result.width *= ratio
        } else if (zone === "top") {
            result.height *= ratio
        } else if (zone === "bottom") {
            result.y += result.height * (1 - ratio)
            result.height *= ratio
        }

        return result
    }

    // Update scans floating surfaces first, then the main canvas, and publishes
    // one accepted preview target to the workspace.
    function update(dockId, globalPoint) {
        _target = null
        workspace._hideDropPreviews()
        const surfaces = workspace._dropContainerSurfaces()

        for (let i = 0; i < surfaces.length; ++i) {
            const surface = surfaces[i]
            if (!surface || !surface.item || !surface.item.visible
                    || surface.item.width < 1 || surface.item.height < 1)
                continue

            const local = surface.item.mapFromGlobal(globalPoint)
            if (local.x < 0 || local.y < 0 || local.x > surface.item.width || local.y > surface.item.height)
                continue

            const containerRect = DockTypes.rect({
                x: 0,
                y: 0,
                width: surface.item.width,
                height: surface.item.height
            })
            const outerZone = _outerEdgeZone(
                local.x,
                local.y,
                containerRect.width,
                containerRect.height
            )
            let hit = null
            let zone = outerZone
            let outer = outerZone !== "center"
            if (!outer) {
                // First resolve the nested node under the pointer. Edge zones
                // are relative to that node, while the outer band belongs to
                // the container itself.
                hit = _hitNode(surface.state.root, containerRect, local)
                if (!hit)
                    continue

                const overTabBar = hit.node
                    && hit.node.kind === "tabs"
                    && local.y <= hit.rect.y + workspace.style.header.height

                if (overTabBar || !hit.node) {
                    zone = "center"
                } else {
                    zone = _edgeZone(
                        local.x - hit.rect.x,
                        local.y - hit.rect.y,
                        hit.rect.width,
                        hit.rect.height
                    )
                }
            } else {
                hit = _hitNode(surface.state.root, containerRect, local)
            }

            const groupId = outer ? "" : hit.groupId
            if (draggedContainerId && surface.state.id === sourceContainerId)
                continue
            if (ignoreSourceSurface && surface.state.id === sourceContainerId
                    && (outer || groupId === sourceGroupId))
                continue

            const targetRect = outer ? containerRect : hit.rect
            const tabIndex = !outer && zone === "center" ? _tabIndex(hit.node, targetRect, local) : -1
            const candidate = DockTypes.dropTarget({
                containerId: surface.state.id,
                groupId: groupId,
                zone: zone,
                outer: outer,
                tabIndex: tabIndex
            })
            const accepted = draggedContainerId
                    ? workspace._canDropFloatingContainer(draggedContainerId, candidate)
                    : workspace._canDropDock(dockId, candidate)
            if (!accepted)
                continue

            _target = candidate
            workspace._showDropPreview(
                surface.state.id,
                _previewRect(targetRect, zone),
                targetRect,
                zone
            )

            return candidate
        }

        return null
    }

    function updateContainer(containerId, globalPoint) {
        if (!draggedContainerId || draggedContainerId !== containerId)
            return null
        return update(draggedDockId, globalPoint)
    }

    // Finish resolves the last target, commits a dock operation when one was
    // accepted, and otherwise falls back to creating/updating a floating dock.
    function finishDocked(dockId, globalPoint, x, y, width, height) {
        update(dockId, globalPoint)
        const winner = _target
        workspace.cancelDockDrag()
        if (winner && workspace._dockAt(
                    dockId,
                    winner.containerId,
                    winner.groupId,
                    winner.zone,
                    winner.tabIndex,
                    winner.outer
                ))
            return true

        const item = workspace.dockById(dockId)
        if (item && item.floatable && dockId !== workspace.centralDockId)
            return workspace.floatDock(dockId, x, y, width, height)

        return false
    }

    function finishFloating(dockId, containerId, globalPoint, x, y, width, height) {
        const floatingWindow = workspace.floatingWindowForDock(dockId)
        const screenName = floatingWindow && floatingWindow.screen
                ? floatingWindow.screen.name
                : workspace._currentScreenName()

        workspace._updateFloatingGeometry(containerId, x, y, width, height, screenName)
        update(dockId, globalPoint)

        const winner = _target
        workspace.cancelDockDrag()
        if (winner)
            return workspace._dockAt(
                dockId,
                winner.containerId,
                winner.groupId,
                winner.zone,
                winner.tabIndex,
                winner.outer
            )

        return false
    }

    function finishFloatingContainer(containerId, globalPoint, x, y, width, height) {
        if (!draggedContainerId || draggedContainerId !== containerId)
            return false

        const floatingWindow = workspace.floatingWindowForDock(draggedDockId)
        const screenName = floatingWindow && floatingWindow.screen
                ? floatingWindow.screen.name
                : workspace._currentScreenName()

        workspace._updateFloatingGeometry(containerId, x, y, width, height, screenName)
        updateContainer(containerId, globalPoint)

        const winner = _target
        workspace.cancelDockDrag()
        if (winner)
            return workspace._dockFloatingContainerAt(
                containerId,
                winner.containerId,
                winner.groupId,
                winner.zone,
                winner.tabIndex,
                winner.outer
            )

        return false
    }
}
