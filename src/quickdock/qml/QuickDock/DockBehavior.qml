import QtQuick

// Interaction settings of a DockWorkspace, available as `workspace.behavior`.
QtObject {
    // Pointer travel before a press on a header becomes a drag.
    property int dragThreshold: 8

    // Drop zones. A group's edge bands cover `edgeFraction` of each side, up
    // to `edgeMaxBand` pixels. The container's outer band is `outerEdgeBand`
    // pixels wide.
    property real edgeFraction: 0.26
    property int edgeMaxBand: 160
    property int outerEdgeBand: 12

    // Share of the space a dock gets when it is docked by splitting.
    property real defaultSplitRatio: 0.5

    // Whether the directional compass is shown over a drop target.
    property bool dropCompassEnabled: true

    // Floating windows: the smallest allowed size, the size used when neither
    // the caller nor the dock suggests one, and where new windows appear (a
    // fraction of the workspace, offset by `floatingCascadeOffset` for each
    // window already open).
    property size floatingMinimumSize: Qt.size(220, 140)
    property size floatingDefaultSize: Qt.size(480, 320)
    property point floatingOrigin: Qt.point(0.2, 0.15)
    property point floatingCascadeOffset: Qt.point(28, 28)
}
