pragma ComponentBehavior: Bound

import QtQuick

// One tab group: a header (the full header for a single dock, a scrollable
// tab row otherwise) above the content of the active dock.
Rectangle {
    id: root

    required property DockWorkspace workspace
    required property var floatingWindow
    required property string groupId
    property var node: null

    readonly property var docks: node ? node.docks : []
    readonly property string activeDock: node ? node.active : ""
    readonly property bool tabbed: docks.length > 1
    // A floating window with a single dock has no title bar. Its header moves the window.
    readonly property bool moveWindow: !!floatingWindow && !floatingWindow.hasTitleBar
    readonly property bool tabsOverflow: tabbed
        && (docks.length * workspace.style.tab.minimumWidth > width || tabRow.width > width)

    color: workspace.style.colors.panel
    border.color: workspace.style.colors.border
    border.width: workspace.style.frame.borderWidth
    clip: true

    // Where a tab dropped at `globalPoint` would go, measured against the
    // rendered tabs. `excludedDockId` is the tab being reordered: it is left
    // out, so the index is the final index of the moved tab. Returns the
    // index and the marker position in global coordinates, or null.
    function tabDropInfo(globalPoint, excludedDockId) {
        if (!tabbed)
            return null
        const point = tabRow.mapFromGlobal(globalPoint)
        const slots = []
        for (let i = 0; i < tabRepeater.count; ++i) {
            const slot = tabRepeater.itemAt(i) as DockTab
            if (slot && slot.dockId !== excludedDockId)
                slots.push(slot)
        }
        if (!slots.length)
            return null

        let index = 0
        while (index < slots.length && point.x >= slots[index].x + slots[index].width / 2)
            ++index
        const boundary = index < slots.length
            ? slots[index].x
            : slots[slots.length - 1].x + slots[slots.length - 1].width
        const inViewport = tabFlickable.mapFromItem(tabRow, boundary, 0)
        const markerX = Math.max(0, Math.min(tabFlickable.width, inViewport.x))
        const markerTop = Math.max(0, Math.min(tabFlickable.height / 2, workspace.style.drop.tabMarkerMargin))
        const markerGlobal = tabFlickable.mapToGlobal(markerX, markerTop)
        return {
            index: index,
            x: markerGlobal.x,
            y: markerGlobal.y,
            height: Math.max(1, tabFlickable.height - markerTop * 2)
        }
    }

    component DockTab: Item {
        id: tab
        required property string modelData
        readonly property string dockId: modelData

        width: Math.max(root.workspace.style.tab.minimumWidth,
                        Math.min(root.workspace.style.tab.maximumWidth, tabHost.implicitWidth))
        height: tabRow.height

        DockDelegateHost {
            id: tabHost
            anchors.fill: parent
            delegate: root.workspace.tabDelegate
            context: QtObject {
                readonly property DockWorkspace workspace: root.workspace
                readonly property DockStyle style: root.workspace.style
                readonly property DockItem dock: root.workspace.dockById(tab.dockId)
                readonly property string dockId: tab.dockId
                readonly property bool selected: root.activeDock === tab.dockId
                readonly property bool compact: true
                readonly property var floatingWindow: root.floatingWindow
                readonly property bool moveWindow: false
            }
        }
    }

    Item {
        id: header
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: root.workspace.style.frame.borderWidth
        }
        height: root.workspace.style.header.height

        DockDelegateHost {
            anchors.fill: parent
            visible: !root.tabbed
            delegate: root.node && !root.tabbed ? root.workspace.headerDelegate : null
            context: QtObject {
                readonly property DockWorkspace workspace: root.workspace
                readonly property DockStyle style: root.workspace.style
                readonly property DockItem dock: root.workspace.dockById(root.activeDock)
                readonly property string dockId: root.activeDock
                readonly property bool selected: true
                readonly property bool compact: false
                readonly property var floatingWindow: root.floatingWindow
                readonly property bool moveWindow: root.moveWindow
            }
        }

        Flickable {
            id: tabFlickable
            anchors {
                left: parent.left
                right: overflow.visible ? overflow.left : parent.right
                top: parent.top
                bottom: parent.bottom
            }
            visible: root.tabbed
            contentWidth: tabRow.width
            contentHeight: height
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            Row {
                id: tabRow
                objectName: "dockTabRow_" + root.groupId
                height: parent.height

                Repeater {
                    id: tabRepeater
                    model: root.tabbed ? root.docks : []
                    delegate: DockTab {}
                }
            }
        }

        DockDelegateHost {
            id: overflow
            anchors {
                right: parent.right
                top: parent.top
                bottom: parent.bottom
            }
            width: implicitWidth
            visible: root.tabsOverflow
            delegate: root.tabsOverflow ? root.workspace.overflowMenuDelegate : null
            context: QtObject {
                readonly property DockWorkspace workspace: root.workspace
                readonly property DockStyle style: root.workspace.style
                readonly property var docks: root.docks
                readonly property string activeDock: root.activeDock
            }
        }
    }

    // Only the active dock is shown. The others wait in the parking lot.
    DockContentHost {
        anchors {
            left: parent.left
            right: parent.right
            top: header.bottom
            bottom: parent.bottom
            margins: root.workspace.style.frame.borderWidth
            topMargin: 0
        }
        workspace: root.workspace
        dockId: root.activeDock
    }
}
