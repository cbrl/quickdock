pragma ComponentBehavior: Bound

import QtQuick

// The default titleBarDelegate, shown by floating windows with more than one
// dock, and by single-dock windows under behavior.singleDockTitleBar. It names
// the selected dock, docks the whole container back, maximizes the window, and
// moves the window (with all of its docks) when dragged.
Rectangle {
    id: root

    required property DockWorkspace workspace
    required property DockStyle style
    required property var floatingWindow
    required property string containerId
    required property DockItem dock
    required property bool maximized

    // Offered to the window, which may have the platform hit-test it.
    readonly property Item maximizeButton: maximizeTitleButton

    readonly property Item _iconItem: iconImage.visible ? iconImage : (iconGlyph.visible ? iconGlyph : null)

    objectName: "floatingTitleBar_" + containerId
    implicitHeight: style.header.height
    color: style.colors.activeHeader
    border.color: style.colors.border
    border.width: style.frame.borderWidth
    clip: true

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
        color: root.dock && root.dock.iconGlyphColor.a > 0 ? root.dock.iconGlyphColor : root.style.colors.activeText
        font: root.style.fonts.glyph
    }

    Text {
        anchors {
            left: root._iconItem ? root._iconItem.right : parent.left
            leftMargin: root._iconItem ? root.style.header.titleSpacing : root.style.header.horizontalPadding
            right: buttons.left
            rightMargin: root.style.header.titleSpacing
            verticalCenter: parent.verticalCenter
        }
        text: root.dock ? root.dock.title : ""
        color: root.style.colors.activeText
        font: root.style.fonts.title
        elide: Text.ElideRight
    }

    // Stops short of the window's resize border and of the buttons.
    DockDragArea {
        anchors {
            left: parent.left
            leftMargin: root.style.floating.gripSize
            right: buttons.left
            top: parent.top
            topMargin: root.style.floating.gripSize
            bottom: parent.bottom
        }
        workspace: root.workspace
        containerId: root.containerId
    }

    Row {
        id: buttons
        anchors {
            right: parent.right
            rightMargin: root.style.header.outerMargin
            verticalCenter: parent.verticalCenter
        }
        spacing: root.style.header.buttonSpacing

        TitleButton {
            objectName: "floatingDockButton_" + root.containerId
            glyph: root.style.glyphs.dock
            onClicked: root.workspace.dockContainerToMain(root.containerId)
        }

        TitleButton {
            id: maximizeTitleButton
            objectName: "floatingMaximizeButton_" + root.containerId
            glyph: root.maximized ? root.style.glyphs.restore : root.style.glyphs.maximize
            platformHovered: root.floatingWindow.maximizeButtonHovered
            platformPressed: root.floatingWindow.maximizeButtonPressed
            onClicked: root.floatingWindow.toggleMaximized()
        }
    }

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: root.style.tab.activeUnderlineHeight
        color: root.style.colors.accent
    }

    // `platformHovered` and `platformPressed` are the state the platform
    // reports when it hit-tests the button itself.
    component TitleButton: Rectangle {
        id: button
        property string glyph
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
            color: root.style.colors.activeText
            font: root.style.fonts.button
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
