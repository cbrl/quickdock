.pragma library

// Pure placement/close/float/drop policy. Every function here takes the
// DockItem(s) it needs to inspect as plain values/callbacks so it stays
// testable outside of any QML context.

function zoneAllowed(item, zone) {
    const zones = item ? item.allowedZones : null
    if (!zones || typeof zones.indexOf !== "function")
        return false
    return zones.indexOf(zone) >= 0
}

function preferredSplitZone(item) {
    const order = ["right", "bottom", "left", "top"]
    for (let i = 0; i < order.length; ++i) {
        if (zoneAllowed(item, order[i]))
            return order[i]
    }
    return ""
}

// True when every dock already in the group (other than excludedDockId, if
// it happens to already be a member) is tabbable, i.e. it tolerates
// non-tabbable neighbors leaving/joining around it.
function groupAcceptsTabbable(group, excludedDockId, resolveDock) {
    for (let i = 0; i < group.docks.length; ++i) {
        const existing = resolveDock(group.docks[i])
        if (existing && !existing.tabbable && group.docks[i] !== excludedDockId)
            return false
    }
    return true
}

function canJoinGroup(item, group, resolveDock) {
    if (!item || !group || !item.tabbable || !zoneAllowed(item, "center"))
        return false
    return groupAcceptsTabbable(group, null, resolveDock)
}

function canClose(item, dockId, centralDockId) {
    return !!item && !!item.closable && dockId !== centralDockId
}

function canFloat(item, dockId, centralDockId) {
    return !!item && !!item.floatable && dockId !== centralDockId
}
