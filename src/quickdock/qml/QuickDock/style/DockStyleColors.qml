import QtQuick

// Colors. DockStyle fills these from its preset palette.
QtObject {
    property color panel: "transparent"
    property color header: "transparent"
    property color activeHeader: "transparent"
    property color text: "transparent"
    property color activeText: "transparent"
    property color border: "transparent"
    property color splitter: "transparent"
    property color accent: "transparent"
    property color hover: "transparent"
    // Fill of a drop preview, the drag preview before its image is ready, and
    // the "drag a dock here" text of an empty container.
    property color preview: "transparent"
    property color dragPreviewFallback: "transparent"
    property color placeholder: "transparent"
}
