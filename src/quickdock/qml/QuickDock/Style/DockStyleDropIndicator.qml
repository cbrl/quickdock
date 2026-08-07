pragma ComponentBehavior: Bound

import QtQuick
import QuickDock.Style 1.0

QtObject {
    readonly property DockStyleBorder border: DockStyleBorder {
        width: 2
    }
    property int radius: 3
}
