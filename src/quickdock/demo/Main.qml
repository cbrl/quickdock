pragma ComponentBehavior: Bound

import QtCore
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import QuickDock 1.0

// Small host application that demonstrates the public workspace API and persists
// the user's layout between runs.
ApplicationWindow {
    id: window

    width: 1180
    height: 760
    minimumWidth: 760
    minimumHeight: 500
    visible: true
    title: qsTr("Qt Quick Docking Demo")
    color: "#11141a"

    // The demo's settings object stores only the serialized layout. All live
    // docking state remains owned by DockWorkspace.
    Settings {
        id: settings
        category: "DockingDemo"
        property string layoutState: ""
    }

    // Shared toolbar button used by the demo actions below.
    component ToolButton: Rectangle {
        required property string label
        signal clicked()

        implicitWidth: toolLabel.implicitWidth + 24
        implicitHeight: 30
        radius: 4
        color: toolHover.hovered ? "#3a4353" : "#292f3a"
        border.color: "#465064"

        Text {
            id: toolLabel
            anchors.centerIn: parent
            text: parent.label
            color: "#e8edf5"
            font.pixelSize: 12
        }

        HoverHandler {
            id: toolHover
            cursorShape: Qt.PointingHandCursor
        }
        TapHandler {
            acceptedButtons: Qt.LeftButton
            onTapped: parent.clicked()
        }
    }

    // Toolbar for reset, persistence, and theme actions.
    header: Rectangle {
        height: 48
        color: "#1c2028"
        border.color: "#343b48"

        RowLayout {
            anchors {
                fill: parent
                leftMargin: 12
                rightMargin: 12
            }
            spacing: 8

            Text {
                text: qsTr("DOCKING LAB")
                color: "#f3f6fa"
                font.pixelSize: 13
                font.weight: Font.Bold
                Layout.rightMargin: 12
            }

            ToolButton {
                label: qsTr("Reset")
                onClicked: window.createDemoLayout()
            }

            ToolButton {
                label: qsTr("Save")
                onClicked: {
                    settings.layoutState = workspace.saveLayout()
                    statusText.text = qsTr("Layout saved")
                }
            }

            ToolButton {
                label: qsTr("Restore")
                onClicked: {
                    const restored = workspace.restoreLayout(settings.layoutState)
                    statusText.text = restored ? qsTr("Layout restored")
                                               : qsTr("No saved layout")
                }
            }

            ToolButton {
                label: qsTr("Theme")
                onClicked: {
                    workspace.style.preset = workspace.style.preset === DockStyle.Dark
                            ? DockStyle.Light : DockStyle.Dark
                    statusText.text = workspace.style.preset === DockStyle.Dark
                            ? qsTr("Dark theme") : qsTr("Light theme")
                }
            }

            Item { Layout.fillWidth: true }

            Text {
                id: statusText
                text: qsTr("Drag a tab or title to rearrange")
                color: "#9da8b8"
                font.pixelSize: 12
            }
        }
    }

    // The workspace is the single docking surface. The declared DockItems are
    // created from the sample components after this object completes.
    DockWorkspace {
        id: workspace
        anchors.fill: parent
        onDockClosed: dockId => statusText.text = qsTr("%1 destroyed").arg(dockId)
    }

    Component {
        id: editorDockComponent
        DockItem {
            dockId: "editor"
            title: qsTr("Scene")
            preferredSize: Qt.size(620, 420)

            Rectangle {
                anchors.fill: parent
                color: "#181c24"

                Column {
                    anchors.centerIn: parent
                    spacing: 12

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 220
                        height: 150
                        radius: 12
                        color: "#252b36"
                        border.color: "#4d9dff"

                        Rectangle {
                            anchors.centerIn: parent
                            width: 82
                            height: 82
                            rotation: 45
                            color: "#4d9dff"
                            opacity: 0.78
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: qsTr("Main scene surface")
                        color: "#dfe5ee"
                        font.pixelSize: 18
                    }
                }
            }
        }
    }

    Component {
        id: outlineDockComponent
        DockItem {
            dockId: "outline"
            title: qsTr("Outline")
            preferredSize: Qt.size(330, 440)

            Rectangle {
                anchors.fill: parent
                color: "#1b2028"

                ListView {
                    anchors {
                        fill: parent
                        margins: 12
                    }
                    spacing: 4
                    model: [qsTr("Camera rig"), qsTr("  ↳ Lens"), qsTr("  ↳ Sensor"),
                            qsTr("Lighting"), qsTr("Telemetry"), qsTr("Overlays")]

                    delegate: Rectangle {
                        id: outlineRow
                        required property string modelData
                        required property int index
                        width: ListView.view.width
                        height: 34
                        radius: 4
                        color: index === 0 ? "#303a49" : "transparent"

                        Text {
                            anchors {
                                left: parent.left
                                leftMargin: 10
                                verticalCenter: parent.verticalCenter
                            }
                            text: outlineRow.modelData
                            color: outlineRow.index === 0 ? "#f3f6fa" : "#abb4c1"
                        }
                    }
                }
            }
        }
    }

    Component {
        id: inspectorDockComponent
        DockItem {
            dockId: "inspector"
            title: qsTr("Inspector")
            preferredSize: Qt.size(360, 500)

            Rectangle {
                anchors.fill: parent
                color: "#1b2028"

                ColumnLayout {
                    anchors {
                        fill: parent
                        margins: 16
                    }
                    spacing: 12

                    Text {
                        text: qsTr("TRANSFORM")
                        color: "#7db5ff"
                        font.pixelSize: 11
                        font.weight: Font.Bold
                    }

                    Repeater {
                        model: [qsTr("Position X"), qsTr("Position Y"),
                                qsTr("Rotation"), qsTr("Opacity")]

                        RowLayout {
                            id: inspectorRow
                            required property string modelData
                            Layout.fillWidth: true

                            Text {
                                text: inspectorRow.modelData
                                color: "#b8c0cc"
                                Layout.fillWidth: true
                            }

                            TextField {
                                text: inspectorRow.modelData === qsTr("Opacity") ? "1.00" : "0.00"
                                color: "#e8edf5"
                                selectByMouse: true
                                Layout.preferredWidth: 92
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }
        }
    }

    Component {
        id: consoleDockComponent
        DockItem {
            dockId: "console"
            title: qsTr("Telemetry")
            preferredSize: Qt.size(650, 280)

            Rectangle {
                anchors.fill: parent
                color: "#151920"

                Column {
                    anchors {
                        fill: parent
                        margins: 14
                    }
                    spacing: 8

                    Repeater {
                        model: [
                            ["10:42:18.032", qsTr("INFO"), qsTr("Scene initialized")],
                            ["10:42:18.104", qsTr("DATA"),
                             qsTr("IMU  quaternion=(0.02, 0.12, 0.01, 0.99)")],
                            ["10:42:18.137", qsTr("DATA"), qsTr("Camera frame  1920 × 1080")],
                            ["10:42:18.154", qsTr("INFO"), qsTr("Render pass completed in 7.4 ms")]
                        ]

                        Row {
                            id: telemetryRow
                            required property var modelData
                            spacing: 14

                            Text {
                                text: telemetryRow.modelData[0]
                                color: "#6f7b8d"
                                font.family: "monospace"
                            }
                            Text {
                                text: telemetryRow.modelData[1]
                                color: telemetryRow.modelData[1] === qsTr("DATA")
                                       ? "#73d5a1" : "#7db5ff"
                                font.family: "monospace"
                            }
                            Text {
                                text: telemetryRow.modelData[2]
                                color: "#bdc6d3"
                                font.family: "monospace"
                            }
                        }
                    }
                }
            }
        }
    }

    // Build the sample registry before applying the first layout snapshot.
    function createDemoDocks() {
        workspace.createDock(editorDockComponent)
        workspace.createDock(outlineDockComponent)
        workspace.createDock(inspectorDockComponent)
        workspace.createDock(consoleDockComponent)
    }

    // Arrange the sample docks into a repeatable layout for the Reset action.
    function createDemoLayout() {
        workspace.resetLayout()
        workspace.splitDock("inspector", "editor", "right")
        workspace.splitDock("console", "editor", "bottom")
        workspace.dockAsTab("outline", "inspector")
        workspace.activateDock("inspector")
        statusText.text = qsTr("Demo layout reset")
    }

    // Restore persisted state when possible, otherwise seed the demo layout.
    Component.onCompleted: {
        createDemoDocks()
        if (!settings.layoutState || !workspace.restoreLayout(settings.layoutState))
            createDemoLayout()
    }

    onClosing: settings.layoutState = workspace.saveLayout()
}
