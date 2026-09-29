pragma ComponentBehavior: Bound

import QtQuick
import "DockLayout.js" as DockLayout
import "DockOps.js" as DockOps
import "DockTypes.js" as DockTypes

// Holds the current layout snapshot and its undo history. Every snapshot that
// enters the model, including undo, redo, and restore, is reconciled against
// the registered dock ids first, so the model can never show a dock twice,
// lose one, or keep one that no longer exists. Undo and redo change structure
// only: window geometry and split weights stay as they are now.
QtObject {
    id: root

    property var dockIds: []
    property bool debugLayout: false
    property int undoLimit: 50

    readonly property var snapshot: _snapshot
    readonly property bool canUndo: _undoStack.length > 0
    readonly property bool canRedo: _redoStack.length > 0

    // `structural` is true for changes recorded in history and for undo/redo.
    signal changed(var previous, var current, bool structural)

    property var _snapshot: DockLayout.snapshotWith([DockTypes.mainContainer(null, "")], [])
    property var _undoStack: []
    property var _redoStack: []

    onDebugLayoutChanged: {
        if (debugLayout)
            DockLayout.deepFreeze(_snapshot)
    }

    function _replace(next, structural) {
        next = DockOps.reconcile(next, dockIds)
        if (next === _snapshot)
            return false
        if (debugLayout)
            DockLayout.deepFreeze(next)
        const previous = _snapshot
        _snapshot = next
        changed(previous, next, structural)
        return true
    }

    // Replaces the snapshot. With `history`, the previous snapshot becomes an
    // undo step. Otherwise (selection, split ratios, window geometry) the
    // change is not undoable and leaves the redo stack alone.
    function set(next, history) {
        const previous = _snapshot
        if (!_replace(next, !!history))
            return false
        if (history) {
            _undoStack = _undoStack.concat([previous]).slice(-Math.max(1, undoLimit))
            _redoStack = []
        }
        return true
    }

    function undo() {
        if (!_undoStack.length)
            return false
        const current = _snapshot
        const previous = _undoStack[_undoStack.length - 1]
        _undoStack = _undoStack.slice(0, -1)
        _redoStack = _redoStack.concat([current])
        _replace(DockOps.withLiveState(previous, current), true)
        return true
    }

    function redo() {
        if (!_redoStack.length)
            return false
        const current = _snapshot
        const next = _redoStack[_redoStack.length - 1]
        _redoStack = _redoStack.slice(0, -1)
        _undoStack = _undoStack.concat([current])
        _replace(DockOps.withLiveState(next, current), true)
        return true
    }

    function clearHistory() {
        _undoStack = []
        _redoStack = []
    }
}
