pragma ComponentBehavior: Bound

import QtQuick

// Contract for an application-supplied top-level container renderer. The
// application owns its visual composition and identifies the exact item that
// participates in docking hit-testing. Size constraints describe the complete
// rendered container; application compositions can derive them from the dock
// tree constraints exposed below.
Rectangle {
    property var containerContext: null
    property Item dockingSurface: null

    readonly property size dockingMinimumSize: {
        const context = containerContext
        return context && context.workspace && context.containerState
            ? context.workspace._minimumSizeOf(context.containerState.root)
            : Qt.size(0, 0)
    }
    readonly property size dockingMaximumSize: {
        const context = containerContext
        return context && context.workspace && context.containerState
            ? context.workspace._maximumSizeOf(context.containerState.root)
            : Qt.size(16777215, 16777215)
    }

    property size minimumSize: dockingMinimumSize
    property size maximumSize: dockingMaximumSize
    color: "transparent"
}
