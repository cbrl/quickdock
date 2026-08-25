pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects

// The default renderer for one top-level dock container. Applications can use
// it inside a containerDelegate while composing arbitrary sibling content.
DockContainer {
    id: root

    property DockWorkspace workspace: null
    property string containerId: ""
    property var containerState: null
    property var floatingWindow: null
    property bool renderReady: true
    readonly property real frameRadius: containerId === "main" && workspace
        ? workspace.style.frame.radius
        : 0
    readonly property bool _roundedMaskAvailable: GraphicsInfo.api !== GraphicsInfo.Software

    // Loader delegates receive containerContext after construction. Retain the
    // valid workspace for this view's lifetime so child teardown never sees a
    // transient null required property.
    onContainerContextChanged: {
        if (containerContext && containerContext.workspace)
            workspace = containerContext.workspace
    }

    dockingSurface: root
    color: workspace ? workspace.style.colors.panel : "transparent"
    radius: frameRadius
    clip: true

    Item {
        id: clippedContent
        anchors.fill: parent
        layer.enabled: root._roundedMaskAvailable && root.frameRadius > 0 && width > 0 && height > 0
        layer.smooth: true
        layer.effect: MultiEffect {
            autoPaddingEnabled: false
            maskEnabled: true
            maskSource: roundedMask
        }

        Loader {
            anchors.fill: parent
            sourceComponent: root.workspace ? root.workspace.containerBackgroundDelegate : null

            property DockWorkspace workspace: root.workspace
            property DockStyle style: root.workspace ? root.workspace.style : null
            property string containerId: root.containerId
        }

        Loader {
            anchors.fill: parent
            active: !!root.workspace
            sourceComponent: Component {
                DockNode {
                    workspace: root.workspace
                    containerId: root.containerId
                    floatingWindow: root.floatingWindow
                    dedicatedFloatingTitleBar: root.floatingWindow ? root.floatingWindow.hasDedicatedTitleBar : false

                    // Floating windows delay attachment until their renderer is ready.
                    // Main-window or application-owned uses can render immediately.
                    node: (root.renderReady && root.containerState) ? root.containerState.root : null
                }
            }
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

    // Rectangle.clip is rectangular even when radius is non-zero. Mask the
    // complete dock tree so headers, split groups, and custom backgrounds all
    // follow the main container's rounded outer edge.
    Item {
        id: roundedMask
        anchors.fill: clippedContent
        visible: false
        layer.enabled: true
        layer.smooth: true
        layer.samples: 4

        Rectangle {
            anchors.fill: parent
            radius: root.frameRadius
            color: "white"
            antialiasing: true
        }
    }
}
