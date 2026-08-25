pragma ComponentBehavior: Bound

import QtQuick
import QuickDock.Style 1.0

QtObject {
    property int canvasMargin: 12
    property int radius: 0
    readonly property DockStyleBorder border: DockStyleBorder {
        width: 1
    }
}
