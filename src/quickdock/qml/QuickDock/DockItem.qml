pragma ComponentBehavior: Bound

import QtQuick

// Public dock interface. Metadata and policy live on this object. The default
// content alias lets applications declare arbitrary child visuals.
Item {
    id: root

    enum ClosePolicy {
        Destroy,
        Hide
    }

    required property string dockId
    property string title: dockId
    property size minimumSize: Qt.size(240, 160)
    property size maximumSize: Qt.size(16777215, 16777215)
    property size preferredSize: Qt.size(480, 320)
    property string toolTip: ""
    property url icon: ""

    // Text alternative to `icon` for applications whose icon language is a
    // glyph font. Used by the built-in header only when `icon` is unset.
    property string iconGlyph: ""

    // Optional tint for `iconGlyph`, letting a dock signal application state
    // through its icon. Fully transparent means "follow the header text".
    property color iconGlyphColor: "transparent"

    // Hides the header/tab action buttons without changing what the dock is
    // allowed to do.
    property bool headerButtonsVisible: true

    property bool closable: true
    property bool floatable: true
    property bool tabbable: true

    property var allowedZones: ["center", "left", "right", "top", "bottom"]
    property int closePolicy: DockItem.Destroy
    property bool _workspaceOwned: false // Set by DockWorkspace.createDock() or registerDock(..., true).
    default property alias content: contentHost.data

    signal destructionCompleted(string destroyedDockId)

    // Give layout calculations a useful lower bound even before content has a
    // concrete size, while still allowing larger declared content to expand.
    implicitWidth: Math.max(minimumSize.width, contentHost.childrenRect.width)
    implicitHeight: Math.max(minimumSize.height, contentHost.childrenRect.height)

    Item {
        id: contentHost
        anchors.fill: parent
    }

    Component.onDestruction: destructionCompleted(dockId)
}
