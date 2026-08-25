pragma ComponentBehavior: Bound

import QtQuick

// One drop-target overlay (edge/center preview rectangle + directional
// compass), reparented onto whatever surface it decorates: the main canvas
// or a floating window's content item. Both surfaces show/hide it the same
// way.
QtObject {
    id: root

    // The two loaders share one surface and differ only in z-order. The
    // compass sits above the rectangular preview.
    required property Item surface
    required property DockWorkspace workspace
    property string previewObjectName: ""

    property Loader _preview: Loader {
        parent: root.surface
        objectName: root.previewObjectName
        z: root.workspace.style.drop.overlayZ
        visible: false
        sourceComponent: root.workspace.dropIndicatorDelegate
        property DockWorkspace workspace: root.workspace
        property DockStyle style: root.workspace.style
        property string zone: "center"
    }

    property Loader _compass: Loader {
        parent: root.surface
        z: root.workspace.style.drop.overlayZ + 1
        visible: false
        width: root.workspace.style.drop.compass.size
        height: root.workspace.style.drop.compass.size
        sourceComponent: root.workspace.dropCompassDelegate
        property string zone: "center"
        property DockStyle style: root.workspace.style
    }

    // Position and reveal the preview. The compass is optional and follows the
    // center of the hit target rather than the preview rectangle.
    function show(previewRect, targetRect, zone) {
        _preview.x = Math.round(previewRect.x)
        _preview.y = Math.round(previewRect.y)
        _preview.width = Math.round(previewRect.width)
        _preview.height = Math.round(previewRect.height)
        _preview.zone = zone
        _preview.visible = true

        // A tab insertion marker is self-explanatory and deliberately distinct
        // from the panel/split preview, so it does not use the drop compass.
        if (zone !== "tab" && root.workspace.dropCompassEnabled
                && root.workspace.dropCompassDelegate) {
            _compass.x = Math.round(
                targetRect.x + (targetRect.width - _compass.width) / 2
            )
            _compass.y = Math.round(
                targetRect.y + (targetRect.height - _compass.height) / 2
            )
            _compass.zone = zone
            _compass.visible = true
        } else {
            _compass.visible = false
        }
    }

    function hide() {
        _preview.visible = false
        _compass.visible = false
    }
}
