pragma ComponentBehavior: Bound

import QtQuick

// The registered DockItems by id, in registration order, and which of them the
// workspace owns (and so destroys on close). Items that are not on screen wait
// in a hidden parking lot.
QtObject {
    id: root

    required property Item parkingParent
    readonly property var ids: _ids
    readonly property Item parkingLot: _parkingLot

    // An item's dockId changed after registration. The change was reverted.
    signal dockIdChangeRejected(string dockId)

    property var _ids: []
    property var _items: ({})
    property var _owned: ({})
    property var _watchers: ({})

    property Item _parkingLot: Item {
        parent: root.parkingParent
        visible: false
    }

    function _has(dockId) {
        return Object.prototype.hasOwnProperty.call(_items, dockId)
    }

    function item(dockId) {
        return _has(dockId) ? _items[dockId] : null
    }

    function isOwned(dockId) {
        return !!_owned[dockId]
    }

    // Returns "" on success or an error code.
    function add(item, owned) {
        if (!item || typeof item.dockId !== "string" || !item.dockId.trim())
            return "invalid-dock"
        const dockId = item.dockId
        if (_has(dockId))
            return _items[dockId] === item ? "" : "duplicate-dock-id"

        // A dock id is the item's identity in saved layouts and history.
        const watcher = () => {
            if (item.dockId !== dockId) {
                item.dockId = dockId
                root.dockIdChangeRejected(dockId)
            }
        }
        item.dockIdChanged.connect(watcher)
        _watchers[dockId] = watcher
        _items = Object.assign({}, _items, {[dockId]: item})
        _owned[dockId] = !!owned
        _ids = _ids.concat([dockId])
        park(item)
        return ""
    }

    function remove(dockId) {
        const item = root.item(dockId)
        if (!item)
            return
        item.dockIdChanged.disconnect(_watchers[dockId])
        delete _watchers[dockId]
        const items = Object.assign({}, _items)
        delete items[dockId]
        _items = items
        delete _owned[dockId]
        _ids = _ids.filter(id => id !== dockId)
    }

    function park(item) {
        if (!item)
            return
        item.visible = false
        item.parent = _parkingLot
        item.x = 0
        item.y = 0
    }
}
