pragma ComponentBehavior: Bound

import QtQuick
import QuickDock.Style 1.0

QtObject {
    property int minimumWidth: 110
    property int maximumWidth: 220
    readonly property DockStyleBorder border: DockStyleBorder {}
    readonly property DockStyleUnderline underline: DockStyleUnderline {}
}
