pragma ComponentBehavior: Bound

import QtQuick

// Chooses the built-in floating title bar or an application delegate. Custom
// delegates receive the same window/container context through their Loader.
Item {
    id: root

    required property DockWorkspace workspace
    required property DockFloatingWindow floatingWindow
    required property string containerId
    required property string dockId
    property Component delegate: null

    readonly property string title: {
        const item = workspace.dockById(dockId)
        return item ? item.title : dockId
    }
    readonly property url iconSource: {
        const item = workspace.dockById(dockId)
        return item ? item.icon : ""
    }

    DockFloatingTitleBar {
        anchors.fill: parent
        visible: !root.delegate
        workspace: root.workspace
        floatingWindow: root.floatingWindow
        containerId: root.containerId
        dockId: root.dockId
    }

    Loader {
        objectName: "floatingTitleBarLoader_" + root.containerId
        anchors.fill: parent
        active: !!root.delegate
        sourceComponent: root.delegate

        property DockWorkspace workspace: root.workspace
        property DockStyle style: root.workspace.style
        property DockFloatingWindow floatingWindow: root.floatingWindow
        property string containerId: root.containerId
        property string dockId: root.dockId
        property string title: root.title
        property url iconSource: root.iconSource
        property bool maximized: !!root.floatingWindow && root.floatingWindow.maximized
    }
}
