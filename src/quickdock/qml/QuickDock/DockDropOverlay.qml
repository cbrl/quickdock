pragma ComponentBehavior: Bound

import QtQuick

// Drop feedback over one container view: the indicator for the area a drop
// would fill (or the marker between tabs) and the compass over the target.
Item {
    id: root

    required property DockWorkspace workspace
    required property string containerId

    z: 1000

    function show(previewRect, targetRect, zone) {
        indicator.x = Math.round(previewRect.x)
        indicator.y = Math.round(previewRect.y)
        indicator.width = Math.round(previewRect.width)
        indicator.height = Math.round(previewRect.height)
        indicator.zone = zone
        indicator.visible = true

        // A tab marker is self-explanatory and gets no compass.
        compass.zone = zone
        compass.visible = zone !== "tab" && workspace.behavior.dropCompassEnabled
        compass.x = Math.round(targetRect.x + (targetRect.width - compass.width) / 2)
        compass.y = Math.round(targetRect.y + (targetRect.height - compass.height) / 2)
    }

    function hide() {
        indicator.visible = false
        compass.visible = false
    }

    Item {
        id: indicator
        objectName: "dockDropPreview_" + root.containerId
        property string zone: "center"
        visible: false

        DockDelegateHost {
            anchors.fill: parent
            delegate: root.workspace.dropIndicatorDelegate
            context: QtObject {
                readonly property DockWorkspace workspace: root.workspace
                readonly property DockStyle style: root.workspace.style
                readonly property string zone: indicator.zone
            }
        }
    }

    Item {
        id: compass
        property string zone: "center"
        visible: false
        width: root.workspace.style.drop.compassSize
        height: root.workspace.style.drop.compassSize

        DockDelegateHost {
            anchors.fill: parent
            delegate: root.workspace.dropCompassDelegate
            context: QtObject {
                readonly property DockWorkspace workspace: root.workspace
                readonly property DockStyle style: root.workspace.style
                readonly property string zone: compass.zone
            }
        }
    }
}
