pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls

// The default headerDelegate and tabDelegate: icon, title, and the float or
// dock, maximize, and close buttons, over a drag handle. `compact` is set for
// tabs, which show their buttons only while selected. `moveWindow` is set when
// the header is the only chrome of a floating window, so dragging it moves
// the window.
Rectangle {
    id: root

    required property DockWorkspace workspace
    required property DockStyle style
    required property DockItem dock
    required property string dockId
    required property bool selected
    required property bool compact
    required property var floatingWindow
    required property bool moveWindow

    // Shown when the header moves its window, which may then have the
    // platform hit-test it.
    readonly property Item maximizeButton: maximizeHeaderButton

    readonly property bool showButtons: (!dock || dock.headerButtonsVisible) && (!compact || selected)
    readonly property Item _iconItem: iconImage.visible ? iconImage : (iconGlyph.visible ? iconGlyph : null)

    objectName: "dockHeader_" + dockId
    implicitWidth: style.header.horizontalPadding * 2
                   + (_iconItem ? style.fonts.glyph.pixelSize + style.header.titleSpacing : 0)
                   + titleLabel.implicitWidth
                   + (buttonRow.visible ? style.header.titleSpacing + buttonRow.width : 0)
    implicitHeight: style.header.height
    color: selected ? style.colors.activeHeader : style.colors.header
    border.width: compact ? style.tab.borderWidth : 0
    border.color: selected ? style.tab.activeBorderColor : style.tab.borderColor

    Image {
        id: iconImage
        anchors {
            left: parent.left
            leftMargin: root.style.header.horizontalPadding
            verticalCenter: parent.verticalCenter
        }
        width: root.style.fonts.glyph.pixelSize
        height: root.style.fonts.glyph.pixelSize
        source: root.dock ? root.dock.icon : ""
        visible: source.toString().length > 0
        fillMode: Image.PreserveAspectFit
    }

    Text {
        id: iconGlyph
        anchors {
            left: parent.left
            leftMargin: root.style.header.horizontalPadding
            verticalCenter: parent.verticalCenter
        }
        width: root.style.fonts.glyph.pixelSize
        horizontalAlignment: Text.AlignHCenter
        text: root.dock ? root.dock.iconGlyph : ""
        visible: !iconImage.visible && text.length > 0
        color: root.dock && root.dock.iconGlyphColor.a > 0 ? root.dock.iconGlyphColor
             : root.selected ? root.style.colors.activeText : root.style.colors.text
        font: root.style.fonts.glyph
    }

    Text {
        id: titleLabel
        anchors {
            left: root._iconItem ? root._iconItem.right : parent.left
            leftMargin: root._iconItem ? root.style.header.titleSpacing : root.style.header.horizontalPadding
            right: buttonRow.visible ? buttonRow.left : parent.right
            rightMargin: buttonRow.visible ? root.style.header.titleSpacing : root.style.header.horizontalPadding
            verticalCenter: parent.verticalCenter
        }
        text: root.dock ? root.dock.title : root.dockId
        color: root.selected ? root.style.colors.activeText : root.style.colors.text
        font: root.style.fonts.title
        elide: Text.ElideRight

        HoverHandler { id: titleHover }
        Controls.ToolTip.visible: titleHover.hovered && Controls.ToolTip.text.length > 0
        Controls.ToolTip.delay: 500
        Controls.ToolTip.text: root.dock ? root.dock.toolTip : ""
    }

    // The drag handle covers the title. On a floating window's only header it
    // leaves the window's resize border free.
    DockDragArea {
        objectName: "dockDragArea_" + root.dockId
        anchors {
            left: parent.left
            leftMargin: root.moveWindow ? root.style.floating.gripSize : 0
            right: buttonRow.visible ? buttonRow.left : parent.right
            top: parent.top
            topMargin: root.moveWindow ? root.style.floating.gripSize : 0
            bottom: parent.bottom
        }
        workspace: root.workspace
        dockId: root.dockId
        containerId: root.moveWindow && root.floatingWindow ? root.floatingWindow.containerId : ""
    }

    // Buttons are declared one by one rather than by a Repeater so each can
    // be found by objectName.
    Row {
        id: buttonRow
        objectName: "dockHeaderButtons_" + root.dockId
        anchors {
            right: parent.right
            rightMargin: root.style.header.outerMargin
            verticalCenter: parent.verticalCenter
        }
        spacing: root.style.header.buttonSpacing
        visible: root.showButtons

        HeaderButton {
            glyph: root.floatingWindow ? root.style.glyphs.dock : root.style.glyphs.float
            visible: !!root.floatingWindow || root.workspace.canFloatDock(root.dockId)
            onClicked: {
                if (root.floatingWindow)
                    root.workspace.dockToMain(root.dockId)
                else
                    root.workspace.floatDock(root.dockId)
            }
        }

        HeaderButton {
            id: maximizeHeaderButton
            objectName: "dockMaximizeButton_" + root.dockId
            glyph: root.floatingWindow && root.floatingWindow.maximized
                   ? root.style.glyphs.restore : root.style.glyphs.maximize
            visible: root.moveWindow
            platformHovered: root.moveWindow && root.floatingWindow.maximizeButtonHovered
            platformPressed: root.moveWindow && root.floatingWindow.maximizeButtonPressed
            onClicked: root.floatingWindow.toggleMaximized()
        }

        HeaderButton {
            objectName: "dockCloseButton_" + root.dockId
            glyph: root.style.glyphs.close
            glyphFont: root.style.fonts.closeButton
            visible: root.workspace.canCloseDock(root.dockId)
            onClicked: root.workspace.closeDock(root.dockId)
        }
    }

    // Inset by the border so an outlined tab keeps its outline.
    Rectangle {
        anchors {
            bottom: parent.bottom
            bottomMargin: root.border.width
            horizontalCenter: parent.horizontalCenter
        }
        width: parent.width - root.border.width * 2
        height: root.selected ? root.style.tab.activeUnderlineHeight : root.style.tab.underlineHeight
        color: root.selected ? root.style.colors.accent : root.style.colors.border
    }

    // `platformHovered` and `platformPressed` are the state the platform
    // reports when it hit-tests the button itself.
    component HeaderButton: Rectangle {
        id: button
        property string glyph
        property font glyphFont: root.style.fonts.button
        property bool platformHovered: false
        property bool platformPressed: false
        signal clicked()

        width: root.style.header.buttonSize
        height: root.style.header.buttonSize
        radius: root.style.header.buttonRadius
        color: buttonTap.pressed || platformPressed ? Qt.darker(root.style.colors.hover, 1.15)
             : buttonHover.hovered || platformHovered ? root.style.colors.hover
             : "transparent"

        Text {
            anchors.centerIn: parent
            text: button.glyph
            color: root.style.colors.text
            font: button.glyphFont
        }

        HoverHandler {
            id: buttonHover
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            id: buttonTap
            acceptedButtons: Qt.LeftButton
            onTapped: button.clicked()
        }
    }
}
