pragma ComponentBehavior: Bound

import QtQuick
import QuickDock.Style 1.0

QtObject {
    property size minimumSize: Qt.size(220, 140)
    property rect defaultGeometry: Qt.rect(80, 80, 480, 320)
    readonly property DockStyleFloatingOrigin origin: DockStyleFloatingOrigin {}
    readonly property DockStyleFloatingCascade cascade: DockStyleFloatingCascade {}
    readonly property DockStyleFloatingResizeGrip resizeGrip: DockStyleFloatingResizeGrip {}
}
