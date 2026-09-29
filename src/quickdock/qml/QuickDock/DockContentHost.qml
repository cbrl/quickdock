pragma ComponentBehavior: Bound

import QtQuick

// Shows one registered DockItem by reparenting it here. The item goes back to
// the workspace's parking lot when the host shows another dock or goes away,
// unless another host has already taken it.
Item {
    id: root

    required property DockWorkspace workspace
    property string dockId: ""
    property Item _dock: null

    onDockIdChanged: _attach()
    Component.onCompleted: _attach()
    Component.onDestruction: _release()

    function _release() {
        if (_dock && _dock.parent === root)
            workspace._parkDock(_dock)
        _dock = null
    }

    function _attach() {
        const next = dockId ? workspace.dockById(dockId) : null
        if (next === _dock && (!next || next.parent === root))
            return
        _release()
        _dock = next
        if (!next)
            return
        next.parent = root
        next.x = 0
        next.y = 0
        next.width = Qt.binding(() => root.width)
        next.height = Qt.binding(() => root.height)
        next.visible = true
    }
}
