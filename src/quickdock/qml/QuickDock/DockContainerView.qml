pragma ComponentBehavior: Bound

import QtQuick

// The default renderer for one top-level dock container. Applications can use
// it inside a containerDelegate while composing arbitrary sibling content.
DockContainer {
    id: root

    property DockWorkspace workspace: null
    property string containerId: ""
    property var containerState: null
    property var floatingWindow: null
    property bool renderReady: true

    dockingSurface: root
    color: workspace ? workspace.style.colors.panel : "transparent"

    Loader {
        anchors.fill: parent
        sourceComponent: root.workspace ? root.workspace.containerBackgroundDelegate : null

        property DockWorkspace workspace: root.workspace
        property DockStyle style: root.workspace ? root.workspace.style : null
        property string containerId: root.containerId
    }

    DockNode {
        anchors.fill: parent
        workspace: root.workspace
        containerId: root.containerId
        floatingWindow: root.floatingWindow
        dedicatedFloatingTitleBar: root.floatingWindow ? root.floatingWindow.hasDedicatedTitleBar : false

        // Floating windows delay attachment until their renderer is ready.
        // Main-window or application-owned uses can render immediately.
        node: (root.workspace && root.renderReady && root.containerState) ? root.containerState.root : null
    }

    Loader {
        anchors.fill: parent
        sourceComponent: root.workspace ? root.workspace.containerDecorationDelegate : null

        property DockWorkspace workspace: root.workspace
        property DockStyle style: root.workspace ? root.workspace.style : null
        property string containerId: root.containerId
    }

    Loader {
        anchors.centerIn: parent
        visible: !root.containerState || !root.containerState.root
        sourceComponent: root.workspace ? root.workspace.placeholderDelegate : null

        property DockWorkspace workspace: root.workspace
        property DockStyle style: root.workspace ? root.workspace.style : null
        property string containerId: root.containerId
    }
}
