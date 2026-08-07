pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import "DockLayout.js" as DockLayout

// Recursive renderer for one layout node. Leaf nodes become DockGroups. Split
// nodes lay out child DockNodes and own the adjacent splitter handles.
Item {
    id: root

    required property DockWorkspace workspace
    required property string containerId
    property var node: null
    property DockFloatingWindow floatingWindow: null
    property bool dedicatedFloatingTitleBar: false
    readonly property bool isSplit: !!node && node.kind === "split"
    readonly property bool horizontal: isSplit && node.orientation === "horizontal"
    readonly property int childCount: isSplit ? node.children.length : 0

    // Keep the visual resize local while a handler owns the pointer. Replacing
    // the snapshot on every move would recreate nested splitter delegates.
    property var _dragLengths: null
    property var _dragStartLengths: []
    property int _dragSplitterIndex: -1

    objectName: node && node.id ? "dockNode_" + node.id : "dockNode_empty"

    // Size helpers derive constrained child lengths without mutating the model.
    function _availableLength() {
        const axis = horizontal ? width : height
        return Math.max(0, axis - Math.max(0, childCount - 1) * workspace.style.splitter.size)
    }

    function _minimumAt(index) {
        if (!isSplit || index < 0 || index >= childCount)
            return 0
        const size = workspace._minimumSizeOf(node.children[index])
        return horizontal ? size.width : size.height
    }

    // Keep this as a binding so Qt only re-evaluates it when node, size, or
    // _dragLengths changes. Calling constrainedLengths from childLength() or
    // childOffset() would recurse through the whole subtree on every relayout.
    readonly property var childLengths: {
        if (_dragLengths && _dragLengths.length === childCount)
            return _dragLengths
        return DockLayout.constrainedLengths(
            node,
            _availableLength(),
            workspace._dockMinimumSize,
            workspace.style.header.height,
            workspace.style.splitter.size
        )
    }

    function childLength(index) {
        return index >= 0 && index < childLengths.length ? childLengths[index] : 0
    }

    function childOffset(index) {
        let result = 0
        for (let i = 0; i < index && i < childLengths.length; ++i)
            result += childLengths[i] + workspace.style.splitter.size
        return result
    }

    function beginSplitterDrag(index) {
        const lengths = childLengths
        if (index < 0 || index + 1 >= lengths.length)
            return false

        _dragSplitterIndex = index
        _dragLengths = lengths.slice()
        _dragStartLengths = lengths.slice()
        return true
    }

    function updateSplitterDrag(index, translation) {
        if (!_dragLengths || _dragSplitterIndex !== index)
            return

        // Only the two panes adjacent to the active splitter move. Their
        // combined length remains fixed while each pane respects its minimum.
        const pairLength = _dragLengths[index] + _dragLengths[index + 1]
        if (pairLength <= 0)
            return

        const minimumFirst = _minimumAt(index)
        const minimumSecond = _minimumAt(index + 1)
        const lower = Math.min(pairLength, minimumFirst)
        const upper = Math.max(lower, pairLength - minimumSecond)
        const initial = _dragStartLengths[index]
        const desired = initial + translation
        const bounded = Math.max(lower, Math.min(upper, desired))
        const next = _dragLengths.slice()

        next[index] = bounded
        next[index + 1] = pairLength - bounded
        _dragLengths = next
    }

    function finishSplitterDrag(index) {
        if (!_dragLengths || _dragSplitterIndex !== index)
            return

        const pairLength = _dragLengths[index] + _dragLengths[index + 1]
        const ratio = pairLength > 0 ? _dragLengths[index] / pairLength : 0.5

        _dragLengths = null
        _dragStartLengths = []
        _dragSplitterIndex = -1

        workspace.setSplitRatio(node.id, index, ratio)
    }

    function cancelSplitterDrag(index) {
        if (_dragSplitterIndex !== index)
            return
        _dragLengths = null
        _dragStartLengths = []
        _dragSplitterIndex = -1
    }

    // A leaf is loaded as a DockGroup. Split children are created lazily so the
    // recursive delegate tree follows the current snapshot structure.
    Loader {
        anchors.fill: parent
        active: !root.isSplit
        sourceComponent: Component {
            DockGroup {
                anchors.fill: parent
                workspace: root.workspace
                containerId: root.containerId
                floatingWindow: root.floatingWindow
                dedicatedFloatingTitleBar: root.dedicatedFloatingTitleBar
                node: root.node
            }
        }
    }

    Item {
        id: splitContainer
        anchors.fill: parent
        visible: root.isSplit

        // Child loaders update their existing DockNode instance when possible,
        // avoiding unnecessary delegate churn during splitter movement.
        Repeater {
            model: root.childCount

            Loader {
                id: childLoader
                required property int index
                property var childNode: {
                    if (root.isSplit && index < root.node.children.length)
                        return root.node.children[index]
                    return null
                }
                objectName: {
                    if (root.node && root.node.id) {
                        if (index === 0)
                            return "dockFirst_" + root.node.id
                        else if (index === 1)
                            return "dockSecond_" + root.node.id
                        else
                            return "dockChild_" + root.node.id + "_" + index
                    }
                    return ""
                }
                x: root.horizontal ? root.childOffset(index) : 0
                y: root.horizontal ? 0 : root.childOffset(index)
                width: root.horizontal ? root.childLength(index) : splitContainer.width
                height: root.horizontal ? splitContainer.height : root.childLength(index)

                function createNode() {
                    if (item) {
                        item.workspace = root.workspace
                        item.containerId = root.containerId
                        item.floatingWindow = root.floatingWindow
                        item.dedicatedFloatingTitleBar = root.dedicatedFloatingTitleBar
                        item.node = childNode
                    } else {
                        setSource(
                            "DockNode.qml",
                            {
                                workspace: root.workspace,
                                containerId: root.containerId,
                                floatingWindow: root.floatingWindow,
                                dedicatedFloatingTitleBar: root.dedicatedFloatingTitleBar,
                                node: childNode
                            }
                        )
                    }
                }

                onChildNodeChanged: createNode()
                Component.onCompleted: createNode()
            }
        }

        Repeater {
            model: Math.max(0, root.childCount - 1)

            // Each splitter exposes a visual delegate and a drag handler while
            // leaving the actual ratio commit to the parent DockNode.
            Item {
                id: splitter
                required property int index
                objectName: root.node && root.node.id ? "dockSplitter_" + root.node.id + "_" + index : ""
                x: root.horizontal ? root.childOffset(index) + root.childLength(index) : 0
                y: root.horizontal ? 0 : root.childOffset(index) + root.childLength(index)
                width: root.horizontal ? root.workspace.style.splitter.size : splitContainer.width
                height: root.horizontal ? splitContainer.height : root.workspace.style.splitter.size

                Loader {
                    id: splitterVisual
                    anchors.fill: parent
                    sourceComponent: root.workspace.splitterDelegate
                    property DockStyle style: root.workspace.style
                    property bool hovered: splitterHover.hovered
                    property bool pressed: splitterDrag.active
                    property bool horizontal: root.horizontal
                }

                HoverHandler {
                    id: splitterHover
                    cursorShape: root.horizontal ? Qt.SplitHCursor : Qt.SplitVCursor
                }

                DragHandler {
                    id: splitterDrag
                    target: null
                    acceptedButtons: Qt.LeftButton
                    property bool canceled: false

                    onActiveChanged: {
                        if (active) {
                            canceled = false
                            if (root.beginSplitterDrag(splitter.index)) {
                                splitter.updateDrag()
                            }
                        } else if (canceled) {
                            root.cancelSplitterDrag(splitter.index)
                        } else {
                            root.finishSplitterDrag(splitter.index)
                        }
                    }
                    onTranslationChanged: {
                        if (active)
                            splitter.updateDrag()
                    }
                    onCanceled: {
                        canceled = true
                        root.cancelSplitterDrag(splitter.index)
                    }
                }

                function updateDrag() {
                    const delta = root.horizontal ? splitterDrag.translation.x : splitterDrag.translation.y
                    root.updateSplitterDrag(splitter.index, delta)
                }
            }
        }
    }
}
