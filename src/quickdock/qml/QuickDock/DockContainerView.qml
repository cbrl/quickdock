pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import "DockLayout.js" as DockLayout

// Renders one top-level container: the main area or a floating window's
// content. It is the default containerDelegate, and a custom container
// delegate can place one next to its own content by passing its required
// properties through.
//
// The tree is laid out once by DockLayout.computeGeometry, and groups and
// splitters are rendered as flat collections keyed by id. A group therefore
// keeps its instance, and its DockItem keeps its parent, however the tree
// around it changes. Drag hit-testing reads the same `geometry`.
Rectangle {
    id: root

    required property DockWorkspace workspace
    required property string containerId
    required property var container
    required property var floatingWindow
    required property bool renderReady

    // Size limits of the dock tree, for the window around a floating view.
    readonly property var limits: workspace._sizeLimits(container ? container.root : null)
    readonly property size minimumSize: Qt.size(limits.minimum.width, limits.minimum.height)
    readonly property size maximumSize: Qt.size(limits.maximum.width, limits.maximum.height)

    // Group rects by group id and splitter rects by "splitId:index".
    readonly property var geometry: DockLayout.computeGeometry(
        renderReady && container ? container.root : null,
        width, height, workspace._dockLimits, workspace._metrics, _splitterOverride)

    // Live lengths of the split whose splitter is being dragged.
    property var _splitterOverride: null
    property var _splitterDrag: null

    readonly property real _frameRadius: containerId === "main" ? workspace.style.frame.radius : 0
    readonly property bool _roundedMaskAvailable: GraphicsInfo.api !== GraphicsInfo.Software

    objectName: "dockContainerView_" + containerId
    color: workspace.style.colors.panel
    radius: _frameRadius
    clip: true

    onGeometryChanged: {
        _syncKeys(groupKeys, geometry.groups)
        _syncKeys(splitterKeys, geometry.splitters)
    }
    onContainerIdChanged: workspace._registerView(root)
    Component.onCompleted: {
        _syncKeys(groupKeys, geometry.groups)
        _syncKeys(splitterKeys, geometry.splitters)
        workspace._registerView(root)
    }
    Component.onDestruction: workspace._unregisterView(root)

    // The rendered DockGroup of a tab group, for tab-level drop targeting.
    function groupItem(groupId) {
        for (let i = 0; i < groups.count; ++i) {
            const group = groups.itemAt(i) as DockGroup
            if (group && group.groupId === groupId)
                return group
        }
        return null
    }

    function showDropPreview(previewRect, targetRect, zone) {
        dropOverlay.show(previewRect, targetRect, zone)
    }

    function hideDropPreview() {
        dropOverlay.hide()
    }

    // Removes keys that are gone and appends new ones. Rows are positioned
    // absolutely, so their order does not matter and survivors are untouched.
    function _syncKeys(model, entries) {
        const present = {}
        for (let i = model.count - 1; i >= 0; --i) {
            const key = model.get(i).key
            if (entries[key])
                present[key] = true
            else
                model.remove(i)
        }
        for (const key in entries) {
            if (!present[key])
                model.append({key: key})
        }
    }

    function _beginSplitterDrag(entry) {
        _splitterDrag = entry
        _splitterOverride = {splitId: entry.splitId, lengths: entry.lengths.slice()}
    }

    function _updateSplitterDrag(delta) {
        if (!_splitterDrag)
            return
        _splitterOverride = {
            splitId: _splitterDrag.splitId,
            lengths: DockLayout.draggedLengths(_splitterDrag.lengths, _splitterDrag.minimums,
                                               _splitterDrag.index, delta)
        }
    }

    function _endSplitterDrag(commit) {
        const drag = _splitterDrag
        const override = _splitterOverride
        _splitterDrag = null
        _splitterOverride = null
        if (!commit || !drag)
            return
        const first = override.lengths[drag.index]
        const pair = first + override.lengths[drag.index + 1]
        workspace.setSplitRatio(drag.splitId, drag.index, pair > 0 ? first / pair : 0.5)
    }

    ListModel { id: groupKeys }
    ListModel { id: splitterKeys }

    Item {
        id: clippedContent
        anchors.fill: parent
        layer.enabled: root._roundedMaskAvailable && root._frameRadius > 0 && width > 0 && height > 0
        layer.smooth: true
        layer.effect: MultiEffect {
            autoPaddingEnabled: false
            maskEnabled: true
            maskSource: roundedMask
        }

        DockDelegateHost {
            anchors.fill: parent
            delegate: root.workspace.containerBackgroundDelegate
            context: decorationContext
        }

        Repeater {
            id: groups
            model: groupKeys

            DockGroup {
                id: group
                required property string key
                readonly property var entry: root.geometry.groups[key] || null

                workspace: root.workspace
                floatingWindow: root.floatingWindow
                groupId: key
                node: entry ? entry.node : null
                visible: !!entry
                x: entry ? entry.x : 0
                y: entry ? entry.y : 0
                width: entry ? entry.width : 0
                height: entry ? entry.height : 0
            }
        }

        Repeater {
            model: splitterKeys

            Item {
                id: splitter
                required property string key
                readonly property var entry: root.geometry.splitters[key] || null
                readonly property bool horizontal: !!entry && entry.horizontal

                objectName: "dockSplitter_" + key
                visible: !!entry
                x: entry ? entry.x : 0
                y: entry ? entry.y : 0
                width: entry ? entry.width : 0
                height: entry ? entry.height : 0

                DockDelegateHost {
                    anchors.fill: parent
                    delegate: root.workspace.splitterDelegate
                    context: QtObject {
                        readonly property DockWorkspace workspace: root.workspace
                        readonly property DockStyle style: root.workspace.style
                        readonly property bool hovered: splitterHover.hovered
                        readonly property bool pressed: splitterDrag.active
                        readonly property bool horizontal: splitter.horizontal
                    }
                }

                HoverHandler {
                    id: splitterHover
                    cursorShape: splitter.horizontal ? Qt.SplitHCursor : Qt.SplitVCursor
                }

                DragHandler {
                    id: splitterDrag
                    target: null
                    acceptedButtons: Qt.LeftButton
                    property bool canceled: false

                    onActiveChanged: {
                        if (active) {
                            canceled = false
                            root._beginSplitterDrag(splitter.entry)
                        } else {
                            root._endSplitterDrag(!canceled)
                        }
                    }
                    onTranslationChanged: {
                        if (active)
                            root._updateSplitterDrag(splitter.horizontal ? translation.x : translation.y)
                    }
                    onCanceled: {
                        canceled = true
                        root._endSplitterDrag(false)
                    }
                }
            }
        }

        DockDelegateHost {
            anchors.fill: parent
            delegate: root.workspace.containerDecorationDelegate
            context: decorationContext
        }

        DockDelegateHost {
            anchors.centerIn: parent
            width: implicitWidth
            height: implicitHeight
            visible: !root.container || !root.container.root
            delegate: root.workspace.placeholderDelegate
            context: decorationContext
        }
    }

    QtObject {
        id: decorationContext
        readonly property DockWorkspace workspace: root.workspace
        readonly property DockStyle style: root.workspace.style
        readonly property string containerId: root.containerId
    }

    // Rectangle.clip ignores the radius, so the rounded main container masks
    // its whole tree, custom backgrounds included.
    Item {
        id: roundedMask
        anchors.fill: clippedContent
        visible: false
        layer.enabled: true
        layer.smooth: true
        layer.samples: 4

        Rectangle {
            anchors.fill: parent
            radius: root._frameRadius
            color: "white"
            antialiasing: true
        }
    }

    DockDropOverlay {
        id: dropOverlay
        anchors.fill: parent
        workspace: root.workspace
        containerId: root.containerId
    }
}
