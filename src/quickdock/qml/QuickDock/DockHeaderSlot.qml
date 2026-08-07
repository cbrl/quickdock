pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window

// Picks DockHeader or a custom delegate for one header/tab slot and exposes
// the shared delegate contract (workspace, dockId, dragFrame, floatingWindow,
// windowDragEnabled, selected, compact).
// implicitWidth always reflects the built-in DockHeader's natural size, even
// while a custom delegate is rendering instead, since callers size tabs from
// it either way.
Item {
    id: root

    required property DockWorkspace workspace
    required property string dockId
    required property Item dragFrame
    property DockFloatingWindow floatingWindow: null
    property bool windowDragEnabled: !!floatingWindow
    property bool selected: true
    property bool compact: false
    property Component delegate: null
    signal clicked()

    // Keep the built-in header alive as a sizing/interaction fallback while a
    // custom delegate is loaded into the overlaying Loader.
    implicitWidth: header.implicitWidth

    DockHeader {
        id: header
        anchors.fill: parent
        visible: !root.delegate
        workspace: root.workspace
        dockId: root.dockId
        dragFrame: root.dragFrame
        floatingWindow: root.floatingWindow
        windowDragEnabled: root.windowDragEnabled
        selected: root.selected
        compact: root.compact
        onClicked: root.clicked()
    }

    Loader {
        anchors.fill: parent
        active: !!root.delegate
        sourceComponent: root.delegate
        property DockWorkspace workspace: root.workspace
        property string dockId: root.dockId
        property Item dragFrame: root.dragFrame
        property DockFloatingWindow floatingWindow: root.floatingWindow
        property bool windowDragEnabled: root.windowDragEnabled
        property bool selected: root.selected
        property bool compact: root.compact
    }
}
