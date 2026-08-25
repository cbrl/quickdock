pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import "DockLayout.js" as DockLayout
import "DockTypes.js" as DockTypes

// Owns floating windows and the geometry rules (size limits, screen clamping,
// and cascade placement) that apply only to floating containers. It creates
// and destroys DockFloatingWindow instances to match the snapshot.
QtObject {
    id: root
    objectName: "dockFloatingController"

    required property DockWorkspace workspace
    required property DockModel dockModel
    required property var snapshot

    property var _windows: ({})

    property Component _windowComponent: Component {
        DockFloatingWindow {}
    }

    // Keep native windows synchronized with the immutable container snapshot.
    onSnapshotChanged: syncWindows()
    Component.onCompleted: syncWindows()
    Component.onDestruction: _destroyAllWindows()

    function _windowList() {
        return Object.keys(_windows).map(id => _windows[id])
    }

    function syncWindows() {
        const wanted = {}
        const containers = snapshot && Array.isArray(snapshot.containers) ? snapshot.containers : []

        for (let i = 0; i < containers.length; ++i) {
            const container = containers[i]
            if (container.kind !== "floating")
                continue

            wanted[container.id] = true
            const existing = _windows[container.id]
            if (existing) {
                // The snapshot is the source of truth. Keep the native window
                // instance so Qt does not lose transient-parent state mid-use.
                existing.floatingState = container
                continue
            }

            const window = _windowComponent.createObject(
                null,
                {
                    workspace: workspace,
                    containerId: container.id,
                    floatingState: container
                }
            )

            if (window)
                _windows[container.id] = window
        }

        // Snapshot changes can remove a floating container. Destroy only
        // windows that are no longer represented, preserving live instances
        // so their native window state and transient-parent relationship stay intact.
        const ids = Object.keys(_windows)
        for (let i = 0; i < ids.length; ++i) {
            const id = ids[i]
            if (wanted[id])
                continue

            const removed = _windows[id]
            delete _windows[id]
            if (removed) {
                removed.prepareForDestruction()
                removed.destroy()
            }
        }
    }

    function windowForDock(dockId) {
        // Floating layouts can contain splits and tabs, so the container id is
        // found from the tree rather than from a one-dock window assumption.
        const windows = _windowList()
        for (let i = 0; i < windows.length; ++i) {
            if (DockLayout.collectDocks(windows[i].floatingState.root).indexOf(dockId) >= 0)
                return windows[i]
        }
        return null
    }

    function windowForContainer(containerId) {
        return _windows[containerId] || null
    }

    function hideDropPreviews() {
        const windows = _windowList()
        for (let i = 0; i < windows.length; ++i)
            windows[i].hideDropPreview()
    }

    function closeAll() {
        const windows = _windowList()
        for (let i = 0; i < windows.length; ++i)
            windows[i].close()
    }

    function _destroyAllWindows() {
        const windows = _windowList()
        for (let i = 0; i < windows.length; ++i) {
            windows[i].prepareForDestruction()
            windows[i].destroy()
        }
        _windows = {}
    }

    function _currentScreenName() {
        const window = workspace.Window.window

        // `screen` is a Q_PROPERTY on QWindow that qmllint does not see through
        // the QQuickWindow type returned by the Window attached object.
        // qmllint disable missing-property
        return window && window.screen ? window.screen.name : ""
        // qmllint enable missing-property
    }

    // A multi-dock floating container renders its title bar outside the layout
    // tree, so reserve that height at the native-window boundary.
    function _floatingTitleBarHeight(node) {
        return DockLayout.collectDocks(node).length > 1 ? workspace.style.header.height : 0;
    }

    function floatingMinimumSize(node) {
        const size = workspace._minimumSizeOf(node);
        const titleBarHeight = _floatingTitleBarHeight(node);

        const width = Math.max(workspace.style.floating.minimumSize.width, size.width);
        const height = Math.max(workspace.style.floating.minimumSize.height, size.height + titleBarHeight);

        return DockTypes.size({
            width: width,
            height: height
        });
    }

    function floatingMaximumSize(node) {
        const minimum = floatingMinimumSize(node);
        const maximum = workspace._maximumSizeOf(node);
        const titleBarHeight = _floatingTitleBarHeight(node);

        const width = Math.max(minimum.width, maximum.width);
        const height = Math.max(
            minimum.height,
            // Qt uses 16,777,215 as the largest supported QML item dimension.
            Math.min(16777215, maximum.height + titleBarHeight)
        );

        return DockTypes.size({ width: width, height: height });
    }

    function _clampFloatingGeometry(raw, node) {
        const style = workspace.style
        const fallback = style.floating.defaultGeometry
        const minimum = floatingMinimumSize(node)
        const maximum = floatingMaximumSize(node)

        let available = null
        const window = workspace.Window.window

        // See _currentScreenName() for why `screen` is not statically resolved.
        // qmllint disable missing-property
        if (window && window.screen)
            available = window.screen.availableGeometry
        // qmllint enable missing-property

        if (!available || available.width <= 0 || available.height <= 0)
            available = Qt.rect(0, 0, 1920, 1080)

        // Restore trusted dimensions first, then constrain them to both the
        // dock's policy limits and the available area of the current screen.
        let width = isFinite(Number(raw && raw.width))
                ? Math.max(minimum.width, Math.round(Number(raw.width)))
                : Math.max(minimum.width, fallback.width)
        let height = isFinite(Number(raw && raw.height))
                ? Math.max(minimum.height, Math.round(Number(raw.height)))
                : Math.max(minimum.height, fallback.height)

        width = Math.min(width, maximum.width, available.width)
        height = Math.min(height, maximum.height, available.height)

        let x = isFinite(Number(raw && raw.x))
                ? Math.round(Number(raw.x)) : fallback.x
        let y = isFinite(Number(raw && raw.y))
                ? Math.round(Number(raw.y)) : fallback.y

        // Keep restored/default windows reachable after a display layout has
        // changed. Width and height are already limited to the same area.
        x = Math.max(available.x, Math.min(x, available.x + available.width - width))
        y = Math.max(available.y, Math.min(y, available.y + available.height - height))

        return DockTypes.rect({x: x, y: y, width: width, height: height})
    }

    function floatDock(dockId, x, y, width, height) {
        x = Number(x);
        y = Number(y);
        width = Number(width);
        height = Number(height);

        const item = workspace.dockById(dockId)
        if (!item)
            return workspace._error(
                "dock-not-found",
                qsTr("Unknown dock: %1").arg(dockId)
            )

        if (!item.floatable || dockId === workspace.centralDockId)
            return workspace._error(
                "float-not-allowed",
                qsTr("Dock %1 cannot be floated").arg(dockId)
            )

        const style = workspace.style

        // Remove first so re-floating an existing dock does not count its old
        // container when choosing the next cascade position.
        const removal = DockLayout.withoutDock(snapshot.containers, dockId)
        const floatingCount = removal.filter(container => container.kind === "floating").length
        const origin = workspace.mapToGlobal(
            Qt.point(
                Math.max(
                    style.floating.origin.minimumOffset,
                    workspace.width * style.floating.origin.fraction.x
                ),
                Math.max(
                    style.floating.origin.minimumOffset,
                    workspace.height * style.floating.origin.fraction.y
                )
            )
        )

        const preferred = item.preferredSize
        const floatingRoot = workspace._newGroup([dockId], dockId)
        const minimum = floatingMinimumSize(floatingRoot)
        const maximum = floatingMaximumSize(floatingRoot)
        const hasExplicitPosition = isFinite(x) && isFinite(y)

        const defaultX = origin.x + floatingCount * style.floating.cascade.offset.x
        const defaultY = origin.y + floatingCount * style.floating.cascade.offset.y
        const rawGeometry = DockTypes.rect({
            x: isFinite(x) ? x : defaultX,
            y: isFinite(y) ? y : defaultY,
            width: isFinite(width) ? width : preferred.width,
            height: isFinite(height) ? height : preferred.height
        })

        const requestedWidth = isFinite(rawGeometry.width) ? rawGeometry.width : style.floating.defaultGeometry.width
        const requestedHeight = isFinite(rawGeometry.height) ? rawGeometry.height : style.floating.defaultGeometry.height
        const targetScreenName = _currentScreenName()

        let geometry = null
        if (hasExplicitPosition) {
            // Explicit coordinates are often supplied by an application that
            // manages its own multi-screen placement. Honor that position but
            // still enforce the dock's content-size contract.
            geometry = DockTypes.rect({
                x: Math.round(rawGeometry.x),
                y: Math.round(rawGeometry.y),
                width: Math.min(
                    maximum.width,
                    Math.max(
                        minimum.width,
                        Math.round(requestedWidth)
                    )
                ),
                height: Math.min(
                    maximum.height,
                    Math.max(
                        minimum.height,
                        Math.round(requestedHeight)
                    )
                )
            })
        } else {
            geometry = _clampFloatingGeometry(rawGeometry, floatingRoot)
        }

        const containerId = workspace._newId("float")
        const containers = removal.concat([
            DockTypes.floatingContainer({
                id: containerId,
                geometry: geometry,
                screen: targetScreenName,
                root: floatingRoot,
                selected: dockId
            })
        ])
        dockModel.commit(DockLayout.snapshotWith(containers, snapshot.hidden))
        workspace._dockSelected(dockId)

        return true
    }

    function updateFloatingGeometry(containerId, x, y, width, height, screenName) {
        if (![x, y, width, height].every(value => isFinite(Number(value))))
            return workspace._error(
                "invalid-geometry",
                qsTr("Invalid floating-window geometry")
            )

        const container = DockLayout.containerById(snapshot.containers, containerId)
        if (!container || container.kind !== "floating")
            return workspace._error(
                "container-not-found",
                qsTr("Unknown floating container: %1").arg(containerId)
            )

        const minimum = floatingMinimumSize(container.root)
        const maximum = floatingMaximumSize(container.root)
        const geometry = DockTypes.rect({
            x: Math.round(Number(x)),
            y: Math.round(Number(y)),
            width: Math.min(
                maximum.width,
                Math.max(
                    minimum.width,
                    Math.round(Number(width))
                )
            ),
            height: Math.min(
                maximum.height,
                Math.max(
                    minimum.height,
                    Math.round(Number(height))
                )
            )
        })

        return dockModel.updateContainerGeometry(
            containerId,
            geometry,
            screenName || _currentScreenName()
        )
    }

    // Closing is coordinated with the host window so native child windows do
    // not outlive their workspace.
    function closeFloatingWindows() {
        if (workspace.hostClosing)
            return

        workspace._hostClosing = true
        workspace.cancelDockDrag()
        workspace.hostClosingRequested()
        closeAll()
    }

    function _withFloatingWindow(dockId, method) {
        // Keep the public maximize/restore operations consistent: resolve the
        // owning window once and return the same error for docked docks.
        const window = windowForDock(dockId)
        if (!window)
            return workspace._error(
                "dock-not-floating",
                qsTr("Dock %1 is not floating").arg(dockId)
            )

        window[method]()
        return true
    }

    function maximizeFloatingDock(dockId) {
        return _withFloatingWindow(dockId, "showMaximized")
    }

    function restoreFloatingDock(dockId) {
        return _withFloatingWindow(dockId, "showNormal")
    }

    function toggleFloatingDockMaximized(dockId) {
        return _withFloatingWindow(dockId, "toggleMaximized")
    }
}
