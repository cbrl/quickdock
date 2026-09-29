pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls

// The default overflowMenuDelegate: a button at the end of a crowded tab row
// that lists every dock of the group.
Item {
    id: root

    required property DockWorkspace workspace
    required property DockStyle style
    required property var docks
    required property string activeDock

    implicitWidth: style.header.buttonSize + style.header.outerMargin * 2

    Rectangle {
        id: button
        objectName: "dockOverflowButton"
        anchors.centerIn: parent
        width: root.style.header.buttonSize
        height: root.style.header.buttonSize
        radius: root.style.header.buttonRadius
        color: hover.hovered ? root.style.colors.hover : root.style.colors.header

        Text {
            anchors.centerIn: parent
            text: root.style.glyphs.overflow
            color: root.style.colors.text
            font: root.style.fonts.button
        }

        HoverHandler {
            id: hover
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            acceptedButtons: Qt.LeftButton
            onTapped: menu.open()
        }

        Controls.Menu {
            id: menu
            objectName: "dockOverflowMenu"
            x: button.width - width
            y: button.height

            Repeater {
                model: root.docks

                Controls.MenuItem {
                    required property string modelData
                    readonly property DockItem dock: root.workspace.dockById(modelData)
                    text: dock ? dock.title : modelData
                    checkable: true
                    checked: root.activeDock === modelData
                    onTriggered: root.workspace.activateDock(modelData)
                }
            }
        }
    }
}
