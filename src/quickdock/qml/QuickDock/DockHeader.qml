pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Window

// Built-in title/tab delegate for a DockGroup. It exposes dock actions and
// turns the title area into either a dock drag or a floating-window move.
Rectangle {
    id: root

    objectName: "dockHeader_" + dockId
    required property DockWorkspace workspace
    required property string dockId
    required property Item dragFrame
    property DockFloatingWindow floatingWindow: null
    property bool windowDragEnabled: !!floatingWindow
    property bool selected: true
    property bool compact: false
    signal clicked()

    // Applications can drive the header actions from elsewhere in their UI, so
    // the dock may opt out of the built-in buttons entirely.
    readonly property bool buttonsVisible: {
        const item = workspace.dockById(dockId)
        return item ? item.headerButtonsVisible : true
    }

    readonly property Item iconVisual: dockIcon.visible ? dockIcon : (iconGlyph.visible ? iconGlyph : null)

	implicitWidth: {
		const iconWidth = iconVisual ? workspace.style.fonts.glyph.pixelSize + workspace.style.header.titleSpacing : 0
		const buttonWidth = buttonRow.visible ? workspace.style.header.titleSpacing + buttonRow.width : 0
		const padding = workspace.style.header.horizontalPadding * 2
		return padding + iconWidth + titleLabel.implicitWidth + buttonWidth
	}
    implicitHeight: workspace.style.header.height
    color: selected ? workspace.style.colors.activeHeader : workspace.style.colors.header

    // Only the tab presentation is outlined; a lone dock's header already sits
    // inside the group frame.
    border.width: compact ? workspace.style.tab.border.width : 0
    border.color: selected ? workspace.style.tab.border.activeColor
                           : workspace.style.tab.border.color

    // Title and icon metadata come from the registered DockItem, allowing the
    // same delegate to render declarative and dynamically created docks.
    Text {
        id: titleLabel
        anchors {
            left: root.iconVisual ? root.iconVisual.right : parent.left
            leftMargin: root.iconVisual ? root.workspace.style.header.titleSpacing
                                        : root.workspace.style.header.horizontalPadding
            right: buttonRow.visible ? buttonRow.left : parent.right
            rightMargin: buttonRow.visible ? root.workspace.style.header.titleSpacing
                                           : root.workspace.style.header.horizontalPadding
            verticalCenter: parent.verticalCenter
        }
        text: {
            const item = root.workspace.dockById(root.dockId)
            return item ? item.title : root.dockId
        }
        color: root.selected ? root.workspace.style.colors.activeText : root.workspace.style.colors.text
        font: root.workspace.style.fonts.title
        elide: Text.ElideRight

        HoverHandler { id: titleHover }
        Controls.ToolTip.visible: titleHover.hovered && !!Controls.ToolTip.text
        Controls.ToolTip.delay: 500
        Controls.ToolTip.text: {
            const item = root.workspace.dockById(root.dockId)
            return item ? item.toolTip : ""
        }
    }

    Image {
        id: dockIcon
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
        id: iconGlyph
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
        visible: !dockIcon.visible && text.length > 0
        color: {
            const item = root.workspace.dockById(root.dockId)
            if (item && item.iconGlyphColor.a > 0)
                return item.iconGlyphColor
            return root.selected ? root.workspace.style.colors.activeText
                                 : root.workspace.style.colors.text
        }
        font: root.workspace.style.fonts.glyph
    }

    // Row excludes invisible children from layout, so undock/maximize/close
    // pack against the right edge with no conditional anchor chains needed
    // to skip whichever of the three is hidden. (Buttons are declared
    // individually rather than via Repeater: dockCloseButton_/
    // dockMaximizeButton_ are looked up by objectName with QObject-tree
    // findChild(), which does not see Repeater-instantiated delegates.)
    Row {
        id: buttonRow
        objectName: "dockHeaderButtons_" + root.dockId
        visible: root.buttonsVisible
        anchors {
            right: parent.right
            rightMargin: root.workspace.style.header.outerMargin
            verticalCenter: parent.verticalCenter
        }
        spacing: root.workspace.style.header.button.spacing

        Rectangle {
            id: undockButton
            width: root.workspace.style.header.button.size
            height: root.workspace.style.header.button.size
            radius: root.workspace.style.button.radius
            visible: (!root.compact || root.selected)
                     && (!!root.floatingWindow || root.workspace.canFloatDock(root.dockId))
            color: undockHover.hovered ? root.workspace.style.colors.hover : "transparent"

            Text {
                anchors.centerIn: parent
                text: root.floatingWindow ? root.workspace.style.glyphs.dock
                                          : root.workspace.style.glyphs.float
                color: root.workspace.style.colors.text
                font: root.workspace.style.fonts.button
            }

            HoverHandler {
                id: undockHover
                cursorShape: Qt.PointingHandCursor
            }
            TapHandler {
                acceptedButtons: Qt.LeftButton
                onTapped: {
                    if (root.floatingWindow)
                        root.workspace.dockToFirstGroup(root.dockId)
                    else
                        root.workspace.floatDock(root.dockId)
                }
            }
        }

        Rectangle {
            id: maximizeButton
            objectName: "dockMaximizeButton_" + root.dockId
            width: root.workspace.style.header.button.size
            height: root.workspace.style.header.button.size
            radius: root.workspace.style.button.radius
            visible: !!root.floatingWindow
                     && root.windowDragEnabled
                     && (!root.compact || root.selected)
            color: maximizeHover.hovered ? root.workspace.style.colors.hover : "transparent"

            Text {
                objectName: "dockMaximizeGlyph_" + root.dockId
                anchors.centerIn: parent
                text: root.floatingWindow && root.floatingWindow.maximized
                      ? root.workspace.style.glyphs.restore
                      : root.workspace.style.glyphs.maximize
                color: root.workspace.style.colors.text
                font: root.workspace.style.fonts.button
            }

            HoverHandler {
                id: maximizeHover
                cursorShape: Qt.PointingHandCursor
            }
            TapHandler {
                acceptedButtons: Qt.LeftButton
                onTapped: root.floatingWindow.toggleMaximized()
            }
        }

        Rectangle {
            id: closeButton
            objectName: "dockCloseButton_" + root.dockId
            width: root.workspace.style.header.button.size
            height: root.workspace.style.header.button.size
            radius: root.workspace.style.button.radius
            visible: root.workspace.canCloseDock(root.dockId) && (!root.compact || root.selected)
            color: closeHover.hovered ? root.workspace.style.colors.hover : "transparent"

            Text {
                anchors.centerIn: parent
                text: root.workspace.style.glyphs.close
                color: root.workspace.style.colors.text
                font: root.workspace.style.fonts.closeButton
            }

            HoverHandler {
                id: closeHover
                cursorShape: Qt.PointingHandCursor
            }
            TapHandler {
                acceptedButtons: Qt.LeftButton
                onTapped: root.workspace.closeDock(root.dockId)
            }
        }
    }

    Item {
        id: dragSurface
        objectName: "dockDragArea_" + root.dockId

        // A multi-dock floating window has a separate title bar. Its tabs use
        // the ordinary dock-drag path, while a single dock continues to use
        // its expanded header as the native-window drag surface.
        anchors {
            left: parent.left
            leftMargin: root.windowDragEnabled ? root.workspace.style.floating.resizeGrip.size : 0
            right: buttonRow.visible ? buttonRow.left : parent.right
            top: parent.top
            topMargin: root.windowDragEnabled ? root.workspace.style.floating.resizeGrip.size : 0
            bottom: parent.bottom
        }

        property point pressGlobal: Qt.point(0, 0)
        property point frameOffset: Qt.point(0, 0)
        property bool draggingDock: false

        function globalPoint(position) {
            return mapToGlobal(position)
        }

        function beginGesture() {
            pressGlobal = globalPoint(dockDrag.centroid.pressPosition)
            frameOffset = root.dragFrame.mapFromGlobal(pressGlobal)

            if (!root.workspace.beginDockDrag(root.dockId, root.windowDragEnabled))
                return

            draggingDock = true
            if (root.windowDragEnabled) {
                if (!root.floatingWindow.beginMove(pressGlobal)) {
                    root.workspace.cancelDockDrag()
                    draggingDock = false
                }
            } else {
                root.workspace.showDragPreview(
                    root.dockId,
                    root.dragFrame,
                    pressGlobal.x - frameOffset.x,
                    pressGlobal.y - frameOffset.y,
                    root.dragFrame.width,
                    root.dragFrame.height
                )
            }
        }

        function updateGesture() {
            if (!draggingDock)
                return

            const point = globalPoint(dockDrag.centroid.position)

            if (root.windowDragEnabled) {
                if (!root.floatingWindow.continueMove(point)) {
                    root.workspace.cancelDockDrag()
                    draggingDock = false
                    return
                }
            } else {
                root.workspace.moveDragPreview(point.x - frameOffset.x, point.y - frameOffset.y)
            }

            root.workspace.updateDockDrag(root.dockId, point)
        }

        function finishGesture() {
            if (!draggingDock)
                return

            const point = globalPoint(dockDrag.centroid.position)

            if (root.windowDragEnabled) {
                if (root.floatingWindow.endMove()) {
                    root.workspace.finishFloatingDrag(
                        root.dockId,
                        root.floatingWindow.containerId,
                        point,
                        root.floatingWindow.x,
                        root.floatingWindow.y,
                        root.floatingWindow.width,
                        root.floatingWindow.height
                    )
                } else {
                    root.workspace.cancelDockDrag()
                }
            } else {
                root.workspace.finishDockedDrag(
                    root.dockId,
                    point,
                    point.x - frameOffset.x,
                    point.y - frameOffset.y,
                    root.dragFrame.width,
                    root.dragFrame.height
                )
            }

            draggingDock = false
        }

        function cancelGesture() {
            if (draggingDock) {
                if (root.windowDragEnabled)
                    root.floatingWindow.cancelMove()
                root.workspace.cancelDockDrag()
            }
            draggingDock = false
        }

        HoverHandler {
            cursorShape: dockDrag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
        }

        TapHandler {
            acceptedButtons: Qt.LeftButton
            onTapped: root.clicked()
            onDoubleTapped: {
                if (root.windowDragEnabled)
                    root.floatingWindow.toggleMaximized()
            }
        }

        DragHandler {
            id: dockDrag
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
            onCentroidChanged: {
                if (active)
                    dragSurface.updateGesture()
            }
            onCanceled: dragSurface.cancelGesture()
        }
    }

    // Inset by the outline so an outlined tab keeps its border visible.
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.border.width
        anchors.horizontalCenter: parent.horizontalCenter
        width: parent.width - root.border.width * 2
        height: root.selected ? root.workspace.style.tab.underline.activeHeight
                              : root.workspace.style.tab.underline.inactiveHeight
        color: root.selected ? root.workspace.style.colors.accent
                             : root.workspace.style.colors.border
    }
}
