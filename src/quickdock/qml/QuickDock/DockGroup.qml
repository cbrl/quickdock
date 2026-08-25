pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Window

// Renders one tabs node. A header row selects/operates docks, while the
// content host owns the active DockItem's visual parent.
Rectangle {
    id: root

    required property DockWorkspace workspace
    required property string containerId
    property DockFloatingWindow floatingWindow: null
    property bool dedicatedFloatingTitleBar: false
    property var node: null
    readonly property string nodeId: node && node.kind === "tabs" ? node.id : ""
    readonly property string activeDock: node && node.kind === "tabs" ? node.active : ""
    readonly property real minimumTabsWidth: node && node.kind === "tabs"
        ? node.docks.length * workspace.style.tab.minimumWidth : 0
    readonly property bool tabsOverflow: node && node.kind === "tabs"
        && (minimumTabsWidth > width || tabRow.width > width)
    property string _registeredNodeId: ""

    color: workspace.style.colors.panel
    border.color: workspace.style.colors.border
    border.width: workspace.style.frame.border.width
    clip: true

    function _refreshRegistration() {
        if (_registeredNodeId === nodeId)
            return
        if (_registeredNodeId)
            workspace._unregisterDockGroup(containerId, _registeredNodeId, root)
        _registeredNodeId = nodeId
        if (_registeredNodeId)
            workspace._registerDockGroup(root)
    }

    // Resolve an insertion against the rendered tabs rather than estimating
    // it from the width of the complete group. When reordering in place, the
    // dragged tab is omitted so the returned index is already the final index.
    function tabDropInfo(globalPoint, excludedDockId) {
        if (!tabFlickable.visible || !node || node.kind !== "tabs")
            return null

        const point = tabRow.mapFromGlobal(globalPoint)
        const slots = []
        for (let i = 0; i < tabRepeater.count; ++i) {
            const slot = tabRepeater.itemAt(i)
            if (slot && slot.modelData !== excludedDockId)
                slots.push(slot)
        }
        if (!slots.length)
            return null

        let index = 0
        while (index < slots.length
                && point.x >= slots[index].x + slots[index].width / 2)
            ++index

        const boundary = index < slots.length
            ? slots[index].x
            : slots[slots.length - 1].x + slots[slots.length - 1].width
        const inViewport = tabFlickable.mapFromItem(tabRow, boundary, 0)
        const markerX = Math.max(0, Math.min(tabFlickable.width, inViewport.x))
        const markerTop = Math.max(0, Math.min(
            tabFlickable.height / 2,
            workspace.style.drop.indicator.tabMargin
        ))
        const markerGlobal = tabFlickable.mapToGlobal(markerX, markerTop)

        return {
            index: index,
            x: markerGlobal.x,
            y: markerGlobal.y,
            height: Math.max(1, tabFlickable.height - markerTop * 2)
        }
    }

    onNodeIdChanged: _refreshRegistration()
    Component.onCompleted: _refreshRegistration()
    Component.onDestruction: {
        if (_registeredNodeId)
            workspace._unregisterDockGroup(containerId, _registeredNodeId, root)
    }

    // A single-dock group uses the full header delegate. Multi-dock groups
    // replace it with a horizontally scrollable tab row.
    Item {
        id: header
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: root.workspace.style.frame.border.width
        }
            height: root.workspace.style.header.height

        DockHeaderSlot {
            anchors.fill: parent
            visible: !!root.node
                && root.node.kind === "tabs"
                && root.node.docks.length === 1
            workspace: root.workspace
            dockId: root.activeDock
            dragFrame: root
            floatingWindow: root.floatingWindow
            windowDragEnabled: !!root.floatingWindow && !root.dedicatedFloatingTitleBar
            delegate: root.workspace.headerDelegate
            onClicked: root.workspace.activateDock(dockId)
        }

        Flickable {
            id: tabFlickable
            anchors {
                left: parent.left
                right: overflowButton.visible || customOverflow.active
                       ? overflowButton.left
                       : parent.right
                top: parent.top
                bottom: parent.bottom
            }
            visible: !!root.node && root.node.kind === "tabs" && root.node.docks.length >= 2
            contentWidth: Math.max(tabRow.width, root.minimumTabsWidth)
            contentHeight: height
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            Row {
                id: tabRow
                objectName: "dockTabRow_" + root.nodeId
                height: parent.height

                Repeater {
                    id: tabRepeater
                    model: root.node && root.node.kind === "tabs" ? root.node.docks : []

                    Item {
                        id: tabSlot
                        required property string modelData
                        width: Math.max(
                            root.workspace.style.tab.minimumWidth,
                            Math.min(
                                root.workspace.style.tab.maximumWidth,
                                headerSlot.implicitWidth
                            )
                        )
                        height: tabRow.height

                        DockHeaderSlot {
                            id: headerSlot
                            anchors.fill: parent
                            workspace: root.workspace
                            dockId: tabSlot.modelData
                            dragFrame: root
                            floatingWindow: root.floatingWindow
                            windowDragEnabled: !!root.floatingWindow
                                               && !root.dedicatedFloatingTitleBar
                            selected: root.activeDock === dockId
                            compact: true
                            delegate: root.workspace.tabDelegate
                            onClicked: root.workspace.activateDock(dockId)
                        }
                    }
                }
            }
        }

        Rectangle {
            id: overflowButton
            objectName: "dockOverflowButton_" + root.nodeId
            anchors {
                right: parent.right
                rightMargin: root.workspace.style.header.outerMargin
                verticalCenter: parent.verticalCenter
            }
            width: root.workspace.style.header.button.size
            height: root.workspace.style.header.button.size
            radius: root.workspace.style.button.radius
            visible: root.tabsOverflow && !root.workspace.overflowMenuDelegate
            color: overflowHover.hovered ? root.workspace.style.colors.hover : root.workspace.style.colors.header

            Text {
                anchors.centerIn: parent
                text: root.workspace.style.glyphs.overflow
                color: root.workspace.style.colors.text
                font: root.workspace.style.fonts.button
            }

            HoverHandler {
                id: overflowHover
                cursorShape: Qt.PointingHandCursor
            }
            TapHandler {
                acceptedButtons: Qt.LeftButton
                onTapped: overflowMenu.open()
            }

            Controls.Menu {
                id: overflowMenu
                objectName: "dockOverflowMenu_" + root.nodeId
                x: overflowButton.width - width
                y: overflowButton.height

                Repeater {
                    model: (root.node && root.node.kind === "tabs") ? root.node.docks : []

                    Controls.MenuItem {
                        required property string modelData
                        text: {
                            const item = root.workspace.dockById(modelData)
                            return item ? item.title : modelData
                        }
                        checkable: true
                        checked: root.activeDock === modelData
                        onTriggered: root.workspace.activateDock(modelData)
                    }
                }
            }
        }

        // Applications may replace the built-in overflow menu with a custom
        // delegate that receives the current dock list and active dock id.
        Loader {
            id: customOverflow
            anchors {
                right: parent.right
                top: parent.top
                bottom: parent.bottom
            }
            active: !!root.workspace.overflowMenuDelegate && root.tabsOverflow
            sourceComponent: root.workspace.overflowMenuDelegate
            property DockWorkspace workspace: root.workspace
            property DockStyle style: root.workspace.style
            property var docks: (root.node && root.node.kind === "tabs") ? root.node.docks : []
            property string activeDock: root.activeDock
        }
    }

    // Only the active tab is attached to the content host. Inactive DockItems
    // remain parked by the registry until they become active.
    DockContentHost {
        anchors {
            left: parent.left
            right: parent.right
            top: header.bottom
            bottom: parent.bottom
            margins: root.workspace.style.frame.border.width
            topMargin: 0
        }
        workspace: root.workspace
        dockId: root.activeDock
    }
}
