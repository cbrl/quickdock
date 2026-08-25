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
        // A container drag must never dock back into its own surface. Unlike a
        // dock drag, it has no source group to exclude.
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

    // A global drag point needs a separate local coordinate for each native
    // window. The surface order supplied by the workspace already puts active
    // floating windows first, so this list also defines hit-test priority.
	function _visibleLocalSurfaces(globalPoint) {
        const surfaces = workspace._dropContainerSurfaces()

		let results = [];
        for (let i = 0; i < surfaces.length; ++i) {
            const surface = surfaces[i]
            if (!surface || !surface.item || !surface.item.visible || surface.item.width < 1 || surface.item.height < 1)
                continue

            const local = surface.item.mapFromGlobal(globalPoint)
            if (local.x < 0 || local.y < 0 || local.x > surface.item.width || local.y > surface.item.height)
                continue

			results.push({ surface: surface, localPoint: local });
		}

		return results;
	}

    // Update scans floating surfaces first, then the main canvas, and publishes
    // one accepted preview target to the workspace.
    function update(dockId, globalPoint) {
        _target = null
        workspace._hideDropPreviews()
        const surfaces = _visibleLocalSurfaces(globalPoint)

        for (let i = 0; i < surfaces.length; ++i) {
            const surface = surfaces[i].surface
			const local = surfaces[i].localPoint

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

            // A whole floating container cannot target itself. A dock drag may
            // also opt out of its source surface, so pulling a header away has
            // a reliable path to creating a floating window.
            if (draggedContainerId && surface.state.id === sourceContainerId)
                continue
            if (ignoreSourceSurface && surface.state.id === sourceContainerId && (outer || groupId === sourceGroupId))
                continue

            const targetRect = outer ? containerRect : hit.rect
            const overTabBar = !outer
				&& zone === "center"
				&& hit.node
                && hit.node.kind === "tabs"
                && local.y <= hit.rect.y + workspace.style.header.height
            const excludedDockId = overTabBar && surface.state.id === sourceContainerId && hit.groupId === sourceGroupId
                ? dockId
				: ""
            // Tab insertion is treated as a center drop. Policy checks and
            // model mutations are the same, while the view provides a precise
            // insertion boundary and a distinct visual marker.
            const tabDrop = overTabBar
                ? workspace._tabDropInfo(
                    surface.state.id,
                    hit.groupId,
                    globalPoint,
                    excludedDockId
                )
				: null

            // A tab-bar insertion always comes from DockGroup's rendered-tab
            // geometry. Other center drops leave tabIndex at -1, which the
            // command layer treats as an append (or activation in-place).
            let tabIndex = tabDrop ? tabDrop.index : -1

            // DockCommands accepts an insertion boundary in the current list
            // and removes the source tab before moving it. Convert the final
            // index calculated without that tab back to that boundary.
            if (tabDrop && excludedDockId) {
                const sourceIndex = hit.node.docks.indexOf(excludedDockId)
                if (sourceIndex >= 0 && tabIndex > sourceIndex)
                    ++tabIndex
            }

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
            if (tabDrop) {
                // tabDrop is in global coordinates because a DockGroup may
                // live in either the main window or a floating window. Convert
                // it only after the winning surface is known.
                const marker = surface.item.mapFromGlobal(Qt.point(tabDrop.x, tabDrop.y))
                const markerWidth = workspace.style.drop.indicator.tabWidth
                workspace._showDropPreview(
                    surface.state.id,
                    DockTypes.rect({
                        x: marker.x - markerWidth / 2,
                        y: marker.y,
                        width: markerWidth,
                        height: tabDrop.height
                    }),
                    targetRect,
                    "tab"
                )
            } else {
                workspace._showDropPreview(
                    surface.state.id,
                    _previewRect(targetRect, zone),
                    targetRect,
                    zone
                )
            }

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

        // Persist the native window's final geometry before attempting a drop.
        // If no target accepts it, the floating container remains where the
        // user released it.
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

        // As with a single floating dock, save the move even when the release
        // does not result in docking the container.
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
