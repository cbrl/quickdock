pragma ComponentBehavior: Bound

import QtQuick
import QuickDock.Style 1.0

QtObject {
    property int threshold: 8
    readonly property DockStyleDragEdge edge: DockStyleDragEdge {}
    readonly property DockStyleDragPreview preview: DockStyleDragPreview {}
}
