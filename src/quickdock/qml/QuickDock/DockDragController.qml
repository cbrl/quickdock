pragma ComponentBehavior: Bound

import QtQuick
import "DockLayout.js" as DockLayout
import "DockOps.js" as DockOps

// Runs one drag at a time. A drag moves a payload: a dock, with a preview
// window following the pointer, or a whole floating container, whose own
// window follows the pointer. The container view under the pointer decides
// the drop target from the same geometry it renders.
QtObject {
    id: root

    required property DockWorkspace workspace
    required property DockDragPreview preview

    readonly property bool active: !!_session
    readonly property var target: _target

    // {payload: {dockId} | {containerId}, window, offset, size}
    property var _session: null
    property var _target: null
    property DockContainerView _overlayView: null

    function begin(options) {
        cancel()
        const press = options.pressPoint || Qt.point(0, 0)
        if (options.containerId) {
            const window = workspace._windowForContainer(options.containerId)
            if (!window)
                return workspace._error("container-not-found", [options.containerId])
            if (!window.beginMove(press))
                return false
            _session = {payload: {containerId: options.containerId}, window: window}
            return true
        }

        const dockId = options.dockId || ""
        const item = workspace.dockById(dockId)
        if (!item)
            return workspace._error("dock-not-found", [dockId])
        if (dockId === workspace.centralDockId)
            return workspace._error("central-dock-policy")
        const source = options.source || workspace._groupItemForDock(dockId)
        const offset = source ? source.mapFromGlobal(press.x, press.y) : Qt.point(0, 0)
        const size = source ? Qt.size(source.width, source.height) : item.preferredSize
        _session = {payload: {dockId: dockId}, window: null, offset: offset, size: size}
        preview.showPreview(dockId, source, Qt.rect(press.x - offset.x, press.y - offset.y, size.width, size.height))
        return true
    }

    // Follows the pointer and returns the drop target under it, or null.
    function move(globalPoint) {
        if (!_session)
            return null
        if (_session.window)
            _session.window.continueMove(globalPoint)
        else
            preview.movePreview(globalPoint.x - _session.offset.x, globalPoint.y - _session.offset.y)
        _target = _hitTest(globalPoint)
        return _target
    }

    // Drops on the target under the pointer. Without one, a dock floats where
    // its preview was released and a floating container stays where it was
    // moved to.
    function end(globalPoint) {
        if (!_session)
            return false
        move(globalPoint)
        const session = _session
        const target = _target
        _finish()
        if (session.window)
            session.window.endMove()
        if (target)
            return workspace._run(true, (snapshot, ctx) => DockOps.move(snapshot, session.payload, target, ctx))
        if (session.window)
            return true
        const dockId = session.payload.dockId
        return workspace.canFloatDock(dockId)
            && workspace.floatDock(dockId, globalPoint.x - session.offset.x, globalPoint.y - session.offset.y,
                                   session.size.width, session.size.height)
    }

    function cancel() {
        if (!_session)
            return
        const session = _session
        _finish()
        if (session.window)
            session.window.cancelMove()
    }

    function _finish() {
        _session = null
        _target = null
        _showOverlay(null)
        preview.hidePreview()
    }

    function _showOverlay(view, previewRect, targetRect, zone) {
        if (_overlayView && _overlayView !== view)
            _overlayView.hideDropPreview()
        _overlayView = view
        if (view)
            view.showDropPreview(previewRect, targetRect, zone)
    }

    // The first container view under the pointer. Returns null when there is
    // no target (a splitter, or a drop its policy rejects).
    function _hitTest(globalPoint) {
        const views = workspace._dropViews()
        for (let i = 0; i < views.length; ++i) {
            const view = views[i]
            if (view.containerId === _session.payload.containerId
                    || !view.visible || view.width < 1 || view.height < 1)
                continue
            const local = view.mapFromGlobal(globalPoint.x, globalPoint.y)
            if (local.x >= 0 && local.y >= 0 && local.x <= view.width && local.y <= view.height)
                return _targetIn(view, local, globalPoint)
        }
        _showOverlay(null)
        return null
    }

    function _groupAt(geometry, point) {
        for (const id in geometry.groups) {
            const group = geometry.groups[id]
            if (point.x >= group.x && point.y >= group.y
                    && point.x <= group.x + group.width && point.y <= group.y + group.height)
                return group
        }
        return null
    }

    function _targetIn(view, local, globalPoint) {
        const behavior = workspace.behavior
        const target = {containerId: view.containerId, groupId: "", zone: "center", outer: false, tabIndex: -1}
        let targetRect = Qt.rect(0, 0, view.width, view.height)
        let tabDrop = null
        const outerZone = DockLayout.outerEdgeZone(local.x, local.y, view.width, view.height, behavior.outerEdgeBand)

        if (view.container.root && outerZone !== "center") {
            target.zone = outerZone
            target.outer = true
        } else if (view.container.root) {
            const group = _groupAt(view.geometry, local)
            if (!group) {
                _showOverlay(null)
                return null
            }
            targetRect = Qt.rect(group.x, group.y, group.width, group.height)
            target.groupId = group.node.id
            if (local.y <= group.y + workspace.style.header.height) {
                // Over the tab bar: a center drop at the tab boundary under the pointer.
                const dockId = _session.payload.dockId || ""
                const groupItem = view.groupItem(group.node.id)
                const excluded = group.node.docks.indexOf(dockId) >= 0 ? dockId : ""
                tabDrop = groupItem ? groupItem.tabDropInfo(globalPoint, excluded) : null
                if (tabDrop)
                    target.tabIndex = tabDrop.index
            } else {
                target.zone = DockLayout.edgeZone(local.x - group.x, local.y - group.y, group.width, group.height,
                                                  behavior.edgeFraction, behavior.edgeMaxBand)
            }
        }

        if (!DockOps.canMove(workspace.snapshot, _session.payload, target, workspace._context())) {
            _showOverlay(null)
            return null
        }
        if (tabDrop) {
            const marker = view.mapFromGlobal(tabDrop.x, tabDrop.y)
            const width = workspace.style.drop.tabMarkerWidth
            _showOverlay(view, Qt.rect(marker.x - width / 2, marker.y, width, tabDrop.height), targetRect, "tab")
        } else {
            _showOverlay(view, DockLayout.previewRect(targetRect, target.zone, behavior.defaultSplitRatio),
                         targetRect, target.zone)
        }
        return target
    }
}
