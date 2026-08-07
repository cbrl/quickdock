pragma ComponentBehavior: Bound

import QtQuick

// Lightweight host that moves a registered DockItem between the workspace's
// parking area and the visible content area of a tab group.
Item {
    id: root

    required property DockWorkspace workspace
    required property string dockId
    property var dockItem: null

    // Keep the DockItem parented to exactly one host as layout ownership moves.
    function attachDock() {
        const nextDock = workspace.dockById(dockId)

        // The workspace parks every declared DockItem during initialization.
        // Component completion order can mean this host attached first, so a
        // matching retained reference is only current if we still own it.
        if (dockItem === nextDock && (!dockItem || dockItem.parent === root))
            return

        // A newly created host can reparent the DockItem before this host is
        // destroyed. Never park an item after another host has taken ownership.
        if (dockItem && dockItem.parent === root)
            workspace.parkDockItem(dockItem)

        dockItem = nextDock
        if (dockItem) {
            dockItem.parent = root
            dockItem.x = 0
            dockItem.y = 0
            dockItem.width = Qt.binding(function() { return root.width })
            dockItem.height = Qt.binding(function() { return root.height })
            dockItem.visible = true
        }
    }

    onDockIdChanged: attachDock()
    onWorkspaceChanged: attachDock()
    Component.onCompleted: attachDock()

    // Reattach after registry initialization, when declarative DockItems have
    // been registered and the initial layout can select this host's dock.
    Connections {
        target: root.workspace
        ignoreUnknownSignals: true

        function onDockItemsInitialized() {
            root.attachDock()
        }
    }

    Component.onDestruction: {
        if (dockItem && dockItem.parent === root)
            workspace.parkDockItem(dockItem)
    }
}
