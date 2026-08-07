pragma ComponentBehavior: Bound

import QtQuick

QtObject {
    id: root
    required property var style

    // Header and tab delegates replace DockHeader. Visual-only delegates use
    // the Loader-parent contract supplied by their host.
    //
    // Each delegate below reads its inputs (`hovered`, `zone`, `title`,
    // `snapshotSource`, ...) off the Loader that instantiates it. qmllint only
    // sees the static Item base type of `parent`, so every one of those reads
    // is reported as a missing property. The contract is documented in the
    // styling guide. Changes to it must be checked against the hosts in
    // DockNode.qml, DockDragPreview.qml, and DockDropOverlay.qml.
    // qmllint disable missing-property
    property Component tab: null
    property Component header: null
    property Component floatingTitleBar: null
    property Component splitter: Component {
        Rectangle {
            color: (parent.hovered || parent.pressed)
                   ? root.style.colors.accent : root.style.colors.splitter
        }
    }
    property Component dropIndicator: Component {
        Rectangle {
            color: root.style.colors.preview
            border.color: root.style.colors.accent
            border.width: root.style.drop.indicator.border.width
            radius: root.style.drop.indicator.radius
        }
    }
    property Component dragPreview: Component {
        Rectangle {
            id: dragVisual
            color: root.style.colors.dragPreviewFallback
            border.color: root.style.colors.accent
            border.width: root.style.drag.preview.border.width
            radius: root.style.drag.preview.radius
            clip: true

            Image {
                id: snapshotImage
                anchors.fill: parent
                source: dragVisual.parent.snapshotSource
                visible: status === Image.Ready
                fillMode: Image.Stretch
                smooth: true
            }

            Rectangle {
                id: fallbackHeader
                anchors {
                    left: parent.left
                    right: parent.right
                        top: parent.top
                        margins: root.style.drag.preview.border.width
                }
                height: root.style.header.height
                visible: !snapshotImage.visible
                color: root.style.colors.activeHeader

                Image {
                    id: fallbackIcon
                    anchors {
                        left: parent.left
                        leftMargin: root.style.header.horizontalPadding
                        verticalCenter: parent.verticalCenter
                    }
                    width: root.style.fonts.glyph.pixelSize
                    height: root.style.fonts.glyph.pixelSize
                    source: dragVisual.parent.iconSource
                    visible: source.toString().length > 0
                    fillMode: Image.PreserveAspectFit
                }

                Text {
                    anchors {
                        left: fallbackIcon.visible ? fallbackIcon.right : parent.left
                        leftMargin: fallbackIcon.visible
                                    ? root.style.header.titleSpacing
                                    : root.style.header.horizontalPadding
                        right: parent.right
                        rightMargin: root.style.header.horizontalPadding
                        verticalCenter: parent.verticalCenter
                    }
                    text: dragVisual.parent.title
                    color: root.style.colors.activeText
                    font: root.style.fonts.title
                    elide: Text.ElideRight
                }
            }
        }
    }
    property Component dropCompass: Component {
        Item {
            id: compass

            Repeater {
                model: [
                    {zone: "top", column: 1, row: 0},
                    {zone: "left", column: 0, row: 1},
                    {zone: "center", column: 1, row: 1},
                    {zone: "right", column: 2, row: 1},
                    {zone: "bottom", column: 1, row: 2}
                ]

                Rectangle {
                    required property var modelData
                    width: root.style.drop.compass.cellSize
                    height: root.style.drop.compass.cellSize
                    x: modelData.column * (root.style.drop.compass.cellSize + 2)
                    y: modelData.row * (root.style.drop.compass.cellSize + 2)
                    radius: root.style.button.radius
                    color: (compass.parent.zone === modelData.zone)
                           ? root.style.colors.accent : root.style.colors.header
                    border.color: root.style.colors.accent
                    border.width: 1
                    opacity: (compass.parent.zone === modelData.zone) ? 1 : 0.85
                }
            }
        }
    }
    property Component placeholder: Component {
        Text {
            text: qsTr("Drag a dock here")
            color: root.style.colors.text
            opacity: root.style.placeholder.opacity
            font: root.style.fonts.placeholder
        }
    }
    property Component floatingDecoration: Component {
        Rectangle {
            color: "transparent"
            border.color: root.style.colors.border
            border.width: root.style.frame.border.width
        }
    }
    property Component overflowMenu: null
}
