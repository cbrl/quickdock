pragma ComponentBehavior: Bound

import QtQuick
import QuickDock.Style 1.0

QtObject {
    readonly property DockStyleDropIndicator indicator: DockStyleDropIndicator {}
    readonly property DockStyleDropCompass compass: DockStyleDropCompass {}
    property int overlayZ: 10000
}
