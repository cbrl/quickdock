pragma ComponentBehavior: Bound

import QtQuick

// Window-level chrome for a floating container with multiple docks. Unlike a
// dock header, this component moves and docks the complete container subtree.
Rectangle {
    id: root

    required property DockWorkspace workspace
    required property DockFloatingWindow floatingWindow
    required property string containerId
    required property string dockId

    objectName: "floatingTitleBar_" + containerId
    readonly property Item iconVisual: titleIcon.visible ? titleIcon : (titleGlyph.visible ? titleGlyph : null)
    color: workspace.style.colors.activeHeader
    border.color: workspace.style.colors.border
    border.width: workspace.style.frame.border.width
    clip: true

    Image {
        id: titleIcon
        anchors {
            left: parent.left
            leftMargin: root.workspace.style.header.horizontalPadding
            verticalCenter: parent.verticalCenter
        }
        width: root.workspace.style.fonts.glyph.pixelSize
        height: root.workspace.style.fonts.glyph.pixelSize
        source: {
            const item = root.workspace.dockById(root.dockId)
            return item ? item.icon : ""
        }
        visible: source.toString().length > 0
        fillMode: Image.PreserveAspectFit
    }

    // Glyph-font applications supply DockItem.iconGlyph instead of an image.
    Text {
        id: titleGlyph
        anchors {
            left: parent.left
            leftMargin: root.workspace.style.header.horizontalPadding
            verticalCenter: parent.verticalCenter
        }
        width: root.workspace.style.fonts.glyph.pixelSize
        horizontalAlignment: Text.AlignHCenter
        text: {
            const item = root.workspace.dockById(root.dockId)
            return item ? item.iconGlyph : ""
        }
        visible: !titleIcon.visible && text.length > 0
        color: {
            const item = root.workspace.dockById(root.dockId)
            return item && item.iconGlyphColor.a > 0
                ? item.iconGlyphColor
                : root.workspace.style.colors.activeText
        }
        font: root.workspace.style.fonts.glyph
    }

    Text {
        anchors {
            left: root.iconVisual ? root.iconVisual.right : parent.left
            leftMargin: root.iconVisual
                        ? root.workspace.style.header.titleSpacing
                        : root.workspace.style.header.horizontalPadding
            right: titleButtons.left
            rightMargin: root.workspace.style.header.titleSpacing
            verticalCenter: parent.verticalCenter
        }
        text: {
            const item = root.workspace.dockById(root.dockId)
            return item ? item.title : root.dockId
        }
        color: root.workspace.style.colors.activeText
        font: root.workspace.style.fonts.title
        elide: Text.ElideRight
    }

    // These are container actions. Individual dock and close actions remain
    // on the tabs immediately below this title bar.
    Row {
        id: titleButtons
        anchors {
            right: parent.right
            rightMargin: root.workspace.style.header.outerMargin
            verticalCenter: parent.verticalCenter
        }
            spacing: root.workspace.style.header.button.spacing

        Rectangle {
            id: dockContainerButton
            objectName: "floatingDockButton_" + root.containerId
            width: root.workspace.style.header.button.size
            height: root.workspace.style.header.button.size
            radius: root.workspace.style.button.radius
            color: dockContainerHover.hovered ? root.workspace.style.colors.hover : "transparent"

            Text {
                anchors.centerIn: parent
                text: root.workspace.style.glyphs.dock
                color: root.workspace.style.colors.activeText
                font: root.workspace.style.fonts.button
            }

            HoverHandler {
                id: dockContainerHover
                cursorShape: Qt.PointingHandCursor
            }
            TapHandler {
                acceptedButtons: Qt.LeftButton
                onTapped: root.workspace.dockFloatingContainer(root.containerId)
            }
        }

        Rectangle {
            id: maximizeContainerButton
            objectName: "floatingMaximizeButton_" + root.containerId
            width: root.workspace.style.header.button.size
            height: root.workspace.style.header.button.size
            radius: root.workspace.style.button.radius
            color: maximizeContainerHover.hovered
                   ? root.workspace.style.colors.hover
                   : "transparent"

            Text {
                objectName: "floatingMaximizeGlyph_" + root.containerId
                anchors.centerIn: parent
                text: root.floatingWindow.maximized
                      ? root.workspace.style.glyphs.restore
                      : root.workspace.style.glyphs.maximize
                color: root.workspace.style.colors.activeText
                font: root.workspace.style.fonts.button
            }

            HoverHandler {
                id: maximizeContainerHover
                cursorShape: Qt.PointingHandCursor
            }
            TapHandler {
                acceptedButtons: Qt.LeftButton
                onTapped: root.floatingWindow.toggleMaximized()
            }
        }
    }

    // The remaining title area owns the whole-container move/drop gesture. It
    // stops short of the top resize grip and the action buttons.
    Item {
        id: dragSurface
        anchors {
            left: parent.left
            leftMargin: root.workspace.style.floating.resizeGrip.size
            right: titleButtons.left
            top: parent.top
            topMargin: root.workspace.style.floating.resizeGrip.size
            bottom: parent.bottom
        }
        property bool moving: false

        function globalPoint(position) {
            return mapToGlobal(position)
        }

        function beginGesture() {
            const point = globalPoint(titleMove.centroid.pressPosition)
            if (!root.workspace.beginFloatingContainerDrag(root.containerId, root.dockId))
                return

            moving = root.floatingWindow.beginMove(point)
            if (!moving)
                root.workspace.cancelDockDrag()
        }

        function updateGesture() {
            if (!moving)
                return

            const point = globalPoint(titleMove.centroid.position)
            if (!root.floatingWindow.continueMove(point)) {
                root.workspace.cancelDockDrag()
                moving = false
                return
            }
            root.workspace.updateFloatingContainerDrag(root.containerId, point)
        }

        function finishGesture() {
            if (!moving)
                return

            const point = globalPoint(titleMove.centroid.position)
            root.floatingWindow.endMove()
            root.workspace.finishFloatingContainerDrag(
                root.containerId,
                point,
                root.floatingWindow.x,
                root.floatingWindow.y,
                root.floatingWindow.width,
                root.floatingWindow.height
            )
            moving = false
        }

        function cancelGesture() {
            if (moving)
                root.floatingWindow.cancelMove()
            root.workspace.cancelDockDrag()
            moving = false
        }

        HoverHandler {
            cursorShape: titleMove.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        }

        TapHandler {
            acceptedButtons: Qt.LeftButton
            onDoubleTapped: root.floatingWindow.toggleMaximized()
        }

        DragHandler {
            id: titleMove
            target: null
            acceptedButtons: Qt.LeftButton
            dragThreshold: root.workspace.style.drag.threshold

            onActiveChanged: {
                if (active) {
                    dragSurface.beginGesture()
                    dragSurface.updateGesture()
                } else {
                    dragSurface.finishGesture()
                }
            }
            onCentroidChanged: if (active) dragSurface.updateGesture()
            onCanceled: dragSurface.cancelGesture()
        }
    }

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: root.workspace.style.tab.underline.activeHeight
        color: root.workspace.style.colors.accent
    }
}
