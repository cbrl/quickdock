pragma ComponentBehavior: Bound

import QtQuick

// The default dropCompassDelegate: a cross of five cells with the cell of the
// current drop zone highlighted.
Item {
    id: root

    required property DockStyle style
    required property string zone

    implicitWidth: style.drop.compassSize
    implicitHeight: style.drop.compassSize

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
            readonly property int cell: root.style.drop.compassCellSize
            readonly property bool current: root.zone === modelData.zone

            x: (root.width - 3 * cell - 4) / 2 + modelData.column * (cell + 2)
            y: (root.height - 3 * cell - 4) / 2 + modelData.row * (cell + 2)
            width: cell
            height: cell
            radius: root.style.header.buttonRadius
            color: current ? root.style.colors.accent : root.style.colors.header
            border.color: root.style.colors.accent
            border.width: 1
            opacity: current ? 1 : 0.85
        }
    }
}
