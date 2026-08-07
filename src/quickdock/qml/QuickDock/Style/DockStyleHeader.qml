pragma ComponentBehavior: Bound

import QtQuick
import QuickDock.Style 1.0

QtObject {
    property int height: 32
    property int horizontalPadding: 10
    property int outerMargin: 4
    property int titleSpacing: 4
    readonly property DockStyleHeaderButton button: DockStyleHeaderButton {}
}
