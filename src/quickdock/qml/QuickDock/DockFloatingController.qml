pragma ComponentBehavior: Bound

import QtQuick
import "DockLayout.js" as DockLayout

// Keeps one DockFloatingWindow per floating container in the snapshot. A
// window survives snapshot changes so its native state is not lost.
QtObject {
    id: root

    required property DockWorkspace workspace
    property var _windows: ({})

    property Component _windowComponent: Component {
        DockFloatingWindow {}
    }

    Component.onDestruction: {
        for (const id in _windows)
            _destroy(_windows[id])
        _windows = {}
    }

    function _destroy(window) {
        window.prepareForDestruction()
        window.destroy()
    }

    function sync(snapshot) {
        const wanted = {}
        for (let i = 0; i < snapshot.containers.length; ++i) {
            const container = snapshot.containers[i]
            if (container.kind !== "floating")
                continue
            wanted[container.id] = true
            if (_windows[container.id]) {
                _windows[container.id].container = container
                continue
            }
            const window = _windowComponent.createObject(null, {
                workspace: workspace,
                containerId: container.id,
                container: container
            })
            if (window)
                _windows[container.id] = window
        }
        for (const id in _windows) {
            if (!wanted[id]) {
                const window = _windows[id]
                delete _windows[id]
                _destroy(window)
            }
        }
    }

    function windowForContainer(containerId) {
        return _windows[containerId] || null
    }

    function windowForDock(dockId) {
        for (const id in _windows) {
            if (DockLayout.findGroupForDock(_windows[id].container.root, dockId))
                return _windows[id]
        }
        return null
    }

    // Floating windows, the active one first.
    function windows() {
        const result = Object.keys(_windows).map(id => _windows[id])
        return result.filter(window => window.active).concat(result.filter(window => !window.active))
    }

    function closeAll() {
        const windows = root.windows()
        for (let i = 0; i < windows.length; ++i)
            windows[i].close()
    }
}
