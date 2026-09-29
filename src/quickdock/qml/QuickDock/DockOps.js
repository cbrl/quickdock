.pragma library
.import "DockLayout.js" as DockLayout
.import "DockTypes.js" as DockTypes

// Every layout mutation as a pure function of a snapshot. An operation returns
// `{snapshot, select}` on success, where `select` names a dock to activate as
// part of the same change (or ""), or `{error, args}` with an error code from
// DockWorkspace's message table. A successful no-op returns the input snapshot.
//
// `ctx` supplies what the operations cannot know themselves:
//   newId(prefix)            fresh node/container id
//   dock(dockId)             the registered DockItem (policy flags), or null
//   centralDockId            the dock that must stay in the main container
//   defaultRatio             share given to a dock inserted by a split
//   fitFloating(geometry, root, screen) -> {geometry, screen}
//
// A move target is `{containerId, groupId, zone, outer, tabIndex}`: `outer`
// drops along the container's edge instead of a group's, and `tabIndex` is the
// final index of the moved tab in the target group (negative appends). The
// payload of a move is `{dockId}` or `{containerId}` (a whole floating
// container, which keeps its subtree).

var zones = ["center", "left", "right", "top", "bottom"]

function _ok(snapshot, select) {
    return {snapshot: snapshot, select: select || ""}
}

function _fail(error, args) {
    return {error: error, args: args || []}
}

function _without(list, value) {
    return list.indexOf(value) < 0 ? list : list.filter(item => item !== value)
}

function _withContainer(snapshot, index, container) {
    const containers = snapshot.containers.slice()
    containers[index] = container
    return DockLayout.snapshotWith(containers, snapshot.hidden)
}

function _group(ctx, docks) {
    return DockTypes.tabs(ctx.newId("tabs"), docks, docks[0])
}

// --- Policy ---------------------------------------------------------------------

function zoneAllowed(item, zone) {
    const allowed = item ? item.allowedZones : null
    return !!allowed && typeof allowed.indexOf === "function" && allowed.indexOf(zone) >= 0
}

// The first edge, in reading order of preference, that every item allows.
function preferredSplitZone(items) {
    const order = ["right", "bottom", "left", "top"]
    for (let i = 0; i < order.length; ++i) {
        if (items.every(item => zoneAllowed(item, order[i])))
            return order[i]
    }
    return ""
}

function _tabbable(ctx, dockId) {
    const item = ctx.dock(dockId)
    return !!item && !!item.tabbable
}

// Whether `docks` may join `group` as tabs: they must be tabbable and allow
// the center zone, and every other member of the group must be tabbable too.
function _canJoin(ctx, docks, group) {
    for (let i = 0; i < docks.length; ++i) {
        if (!_tabbable(ctx, docks[i]) || !zoneAllowed(ctx.dock(docks[i]), "center"))
            return false
    }
    for (let i = 0; i < group.docks.length; ++i) {
        if (docks.indexOf(group.docks[i]) < 0 && !_tabbable(ctx, group.docks[i]))
            return false
    }
    return true
}

function canClose(ctx, dockId) {
    const item = ctx.dock(dockId)
    return !!item && !!item.closable && dockId !== ctx.centralDockId
}

function canFloat(ctx, dockId) {
    const item = ctx.dock(dockId)
    return !!item && !!item.floatable && dockId !== ctx.centralDockId
}

function _payloadDocks(snapshot, payload) {
    if (payload.containerId) {
        const source = DockLayout.containerById(snapshot.containers, payload.containerId)
        return source ? DockLayout.collectDocks(source.root) : []
    }
    return [payload.dockId]
}

function _moveError(snapshot, payload, target, ctx) {
    if (!target || zones.indexOf(target.zone) < 0 || (target.outer && target.zone === "center"))
        return _fail("invalid-zone", [target ? target.zone : ""])
    const container = DockLayout.containerById(snapshot.containers, target.containerId)
    if (!container)
        return _fail("container-not-found", [target.containerId])
    const group = !target.outer && container.root
        ? DockLayout.findGroup(container.root, target.groupId) : null
    if (!target.outer && container.root && !group)
        return _fail("group-not-found", [target.groupId])

    if (payload.containerId) {
        const source = DockLayout.containerById(snapshot.containers, payload.containerId)
        if (!source || source.kind !== "floating")
            return _fail("container-not-found", [payload.containerId])
        if (source.id === container.id || (group && target.zone === "center" && source.root.kind !== "tabs"))
            return _fail("dock-policy-denied", [payload.containerId, target.zone])
    } else {
        if (!ctx.dock(payload.dockId))
            return _fail("dock-not-found", [payload.dockId])
        if (payload.dockId === ctx.centralDockId)
            return _fail("central-dock-policy")
    }

    const docks = _payloadDocks(snapshot, payload)
    for (let i = 0; i < docks.length; ++i) {
        if (!zoneAllowed(ctx.dock(docks[i]), target.zone))
            return _fail("dock-policy-denied", [docks[i], target.zone])
    }
    if (group && target.zone === "center" && !_canJoin(ctx, docks, group))
        return _fail("dock-policy-denied", [docks[0], target.zone])
    return null
}

function canMove(snapshot, payload, target, ctx) {
    return !_moveError(snapshot, payload, target, ctx)
}

// --- Placement --------------------------------------------------------------------

// Adds a subtree to a container root: into the first group as tabs when every
// dock may join it, otherwise along the root edge all of its docks allow.
// Returns null when no placement is allowed.
function _rootWith(root, node, ctx, edgeOnly) {
    if (!root)
        return node
    const docks = DockLayout.collectDocks(node)
    const group = DockLayout.firstGroup(root)
    if (!edgeOnly && node.kind === "tabs" && _canJoin(ctx, docks, group))
        return DockLayout.withNodeInserted(root, group.id, node, "center", "", -1, ctx.defaultRatio)
    const zone = edgeOnly ? "right" : preferredSplitZone(docks.map(dockId => ctx.dock(dockId)))
    if (!zone)
        return null
    return DockLayout.withNodeAtRoot(root, node, zone, ctx.newId("split"), ctx.defaultRatio)
}

function _intoMain(containers, hidden, node, ctx, select) {
    const index = containers.findIndex(container => container.kind === "main")
    const main = containers[index]
    // The central dock is the anchor of the main area, so it is never tabbed
    // into another group.
    const central = DockLayout.collectDocks(node).indexOf(ctx.centralDockId) >= 0
    const root = _rootWith(main.root, node, ctx, central && !!main.root)
    if (!root)
        return _fail("no-placement", [DockLayout.collectDocks(node)[0]])
    containers = containers.slice()
    containers[index] = DockLayout.containerWithRoot(main, root)
    return _ok(DockLayout.snapshotWith(containers, hidden), select)
}

function _insertAt(container, target, node, ctx) {
    let root = null
    if (!container.root)
        root = node
    else if (target.outer)
        root = DockLayout.withNodeAtRoot(container.root, node, target.zone, ctx.newId("split"), ctx.defaultRatio)
    else
        root = DockLayout.withNodeInserted(container.root, target.groupId, node, target.zone,
                                           ctx.newId("split"), target.tabIndex, ctx.defaultRatio)
    return root === container.root ? null : DockLayout.containerWithRoot(container, root)
}

// --- Operations -------------------------------------------------------------------

// Every dock in the main container, the central dock first.
function reset(snapshot, dockIds, ctx) {
    const central = ctx.centralDockId
    const ids = dockIds.indexOf(central) >= 0
        ? [central].concat(dockIds.filter(id => id !== central)) : dockIds.slice()
    let root = null
    const hidden = []
    for (let i = 0; i < ids.length; ++i) {
        const next = _rootWith(root, _group(ctx, [ids[i]]), ctx, false)
        if (next)
            root = next
        else
            hidden.push(ids[i])
    }
    return _ok(DockLayout.snapshotWith([DockTypes.mainContainer(root, "")], hidden),
               ids.find(dockId => hidden.indexOf(dockId) < 0))
}

function move(snapshot, payload, target, ctx) {
    const error = _moveError(snapshot, payload, target, ctx)
    if (error)
        return error

    if (payload.containerId) {
        const source = DockLayout.containerById(snapshot.containers, payload.containerId)
        const containers = snapshot.containers.filter(container => container !== source)
        const index = containers.findIndex(container => container.id === target.containerId)
        const next = _insertAt(containers[index], target, source.root, ctx)
        if (!next)
            return _fail("dock-operation-failed")
        containers[index] = next
        return _ok(DockLayout.snapshotWith(containers, snapshot.hidden),
                   source.selected || DockLayout.firstActiveDock(source.root))
    }

    const dockId = payload.dockId
    const source = DockLayout.containerForDock(snapshot.containers, dockId)
    if (source && source.id === target.containerId) {
        const group = DockLayout.findGroupForDock(source.root, dockId)
        const sameGroup = group.id === target.groupId && !target.outer
        // Moving a container's only dock anywhere inside it, splitting a
        // group by itself, and a center drop without an index all leave the
        // layout as it is and just activate the dock.
        if (DockLayout.collectDocks(source.root).length === 1
                || (sameGroup && group.docks.length === 1)
                || (sameGroup && target.zone === "center" && !(target.tabIndex >= 0)))
            return _ok(snapshot, dockId)
    }

    const containers = DockLayout.withoutDock(snapshot.containers, dockId)
    const index = containers.findIndex(container => container.id === target.containerId)
    const next = _insertAt(containers[index], target, _group(ctx, [dockId]), ctx)
    if (!next)
        return _fail("dock-operation-failed")
    containers[index] = next
    return _ok(DockLayout.snapshotWith(containers, _without(snapshot.hidden, dockId)), dockId)
}

// Moves a dock to `target` given as another dock and a zone.
function moveNextTo(snapshot, dockId, targetDockId, zone, ctx) {
    if (!ctx.dock(targetDockId))
        return _fail("target-not-found", [targetDockId])
    const container = DockLayout.containerForDock(snapshot.containers, targetDockId)
    if (!container)
        return _fail("target-not-visible", [targetDockId])
    const group = DockLayout.findGroupForDock(container.root, targetDockId)
    return move(snapshot, {dockId: dockId}, {
        containerId: container.id,
        groupId: group.id,
        zone: zone || "center",
        outer: false,
        tabIndex: -1
    }, ctx)
}

// Floats a dock in a new window. A dock that is already alone in a floating
// window keeps that window and only moves it.
function float(snapshot, dockId, geometry, screen, ctx) {
    if (!ctx.dock(dockId))
        return _fail("dock-not-found", [dockId])
    if (dockId === ctx.centralDockId)
        return _fail("central-dock-policy")
    if (!canFloat(ctx, dockId))
        return _fail("float-not-allowed", [dockId])
    const source = DockLayout.containerForDock(snapshot.containers, dockId)
    if (source && source.kind === "floating" && DockLayout.collectDocks(source.root).length === 1)
        return setGeometry(snapshot, source.id, geometry, screen)

    const root = _group(ctx, [dockId])
    const containers = DockLayout.withoutDock(snapshot.containers, dockId)
    containers.push(DockTypes.floatingContainer(ctx.newId("float"), geometry, screen, root, dockId))
    return _ok(DockLayout.snapshotWith(containers, _without(snapshot.hidden, dockId)), dockId)
}

function dockToMain(snapshot, dockId, ctx) {
    if (!ctx.dock(dockId))
        return _fail("dock-not-found", [dockId])
    const source = DockLayout.containerForDock(snapshot.containers, dockId)
    if (source && source.kind === "main")
        return _ok(snapshot, dockId)
    return _intoMain(DockLayout.withoutDock(snapshot.containers, dockId),
                     _without(snapshot.hidden, dockId), _group(ctx, [dockId]), ctx, dockId)
}

// Docks a whole floating container back into the main area, keeping its
// subtree. A single tab group merges into the first main group when allowed.
function dockContainerToMain(snapshot, containerId, ctx) {
    const source = DockLayout.containerById(snapshot.containers, containerId)
    if (!source || source.kind !== "floating")
        return _fail("container-not-found", [containerId])
    return _intoMain(snapshot.containers.filter(container => container !== source),
                     snapshot.hidden, source.root, ctx, source.selected)
}

function hide(snapshot, dockId, ctx) {
    if (!ctx.dock(dockId))
        return _fail("dock-not-found", [dockId])
    if (dockId === ctx.centralDockId)
        return _fail("central-dock-policy")
    if (snapshot.hidden.indexOf(dockId) >= 0)
        return _ok(snapshot)
    return _ok(DockLayout.snapshotWith(DockLayout.withoutDock(snapshot.containers, dockId),
                                       snapshot.hidden.concat([dockId])))
}

function show(snapshot, dockId, ctx) {
    if (!ctx.dock(dockId))
        return _fail("dock-not-found", [dockId])
    if (snapshot.hidden.indexOf(dockId) < 0)
        return _ok(snapshot, dockId)
    return _intoMain(snapshot.containers, _without(snapshot.hidden, dockId), _group(ctx, [dockId]), ctx, dockId)
}

// Forgets a dock entirely, for docks that are being destroyed.
function remove(snapshot, dockId) {
    return _ok(DockLayout.snapshotWith(DockLayout.withoutDock(snapshot.containers, dockId),
                                       _without(snapshot.hidden, dockId)))
}

// Shows a dock in its group and makes it its container's selected dock.
function activate(snapshot, dockId) {
    const index = snapshot.containers.findIndex(container => !!DockLayout.findGroupForDock(container.root, dockId))
    if (index < 0)
        return _fail("dock-not-visible", [dockId])
    const container = snapshot.containers[index]
    const root = DockLayout.withActiveDock(container.root, dockId)
    if (root === container.root && container.selected === dockId)
        return _ok(snapshot)
    const next = DockLayout.containerWithRoot(container, root)
    next.selected = dockId
    return _ok(_withContainer(snapshot, index, next))
}

function setSplitRatio(snapshot, splitId, splitterIndex, ratio) {
    const index = snapshot.containers.findIndex(container => {
        const node = DockLayout.findNode(container.root, splitId)
        return !!node && node.kind === "split"
    })
    if (index < 0)
        return _fail("split-not-found", [splitId])
    const container = snapshot.containers[index]
    const root = DockLayout.withSplitRatio(container.root, splitId, splitterIndex, ratio)
    return _ok(root === container.root
               ? snapshot : _withContainer(snapshot, index, DockLayout.containerWithRoot(container, root)))
}

function setGeometry(snapshot, containerId, geometry, screen) {
    const index = snapshot.containers.findIndex(container => container.id === containerId)
    const container = snapshot.containers[index]
    if (!container || container.kind !== "floating")
        return _fail("container-not-found", [containerId])
    const current = container.geometry
    if (current && current.x === geometry.x && current.y === geometry.y
            && current.width === geometry.width && current.height === geometry.height
            && container.screen === (screen || ""))
        return _ok(snapshot)
    return _ok(_withContainer(snapshot, index, DockTypes.floatingContainer(
        container.id, geometry, screen, container.root, container.selected)))
}

// Puts the central dock back in the main container if it is anywhere else.
function ensureCentral(snapshot, ctx) {
    const central = ctx.centralDockId
    if (!central)
        return _ok(snapshot)
    if (!ctx.dock(central))
        return _fail("central-dock-not-found", [central])
    const source = DockLayout.containerForDock(snapshot.containers, central)
    if (source && source.kind === "main")
        return _ok(snapshot)
    return _intoMain(DockLayout.withoutDock(snapshot.containers, central),
                     _without(snapshot.hidden, central), _group(ctx, [central]), ctx, "")
}

// A history snapshot with the current window geometry and split weights, for
// undo and redo: history steps are structural, so they leave where windows
// are and how splits are sized alone. A container or split that no longer
// matches (a different child count) keeps its saved values.
function withLiveState(target, current) {
    const liveSplits = {}
    for (let i = 0; i < current.containers.length; ++i) {
        DockLayout.find(current.containers[i].root, node => {
            if (node.kind === "split")
                liveSplits[node.id] = node
            return false
        })
    }
    const withLiveWeights = node => {
        if (!node || node.kind !== "split")
            return node
        const children = node.children.map(withLiveWeights)
        const live = liveSplits[node.id]
        const weights = live && live.children.length === node.children.length ? live.weights : node.weights
        if (weights === node.weights && children.every((child, i) => child === node.children[i]))
            return node
        return DockTypes.split(node.id, node.orientation, weights, children)
    }

    let changed = false
    const containers = target.containers.map(container => {
        const root = withLiveWeights(container.root)
        const live = container.kind === "floating"
            ? DockLayout.containerById(current.containers, container.id) : null
        let next = root === container.root ? container : DockLayout.containerWithRoot(container, root)
        if (live && live.kind === "floating" && live.geometry !== container.geometry)
            next = DockTypes.floatingContainer(container.id, live.geometry, live.screen, next.root, next.selected)
        changed = changed || next !== container
        return next
    })
    return changed ? DockLayout.snapshotWith(containers, target.hidden) : target
}

// --- Persistence and invariants -----------------------------------------------------

function _sanitizeNode(raw, valid, used, ctx) {
    if (!raw || typeof raw !== "object")
        return null
    if (raw.kind === "tabs") {
        const docks = []
        const source = Array.isArray(raw.docks) ? raw.docks : []
        for (let i = 0; i < source.length; ++i) {
            const dockId = String(source[i])
            if (valid[dockId] && !used[dockId]) {
                docks.push(dockId)
                used[dockId] = true
            }
        }
        if (!docks.length)
            return null
        const active = docks.indexOf(String(raw.active)) >= 0 ? String(raw.active) : docks[0]
        return DockTypes.tabs(ctx.newId("tabs"), docks, active)
    }
    if (raw.kind !== "split")
        return null
    const children = []
    const sourceChildren = Array.isArray(raw.children) ? raw.children : []
    const sourceWeights = Array.isArray(raw.weights) ? raw.weights : []
    const weights = []
    for (let i = 0; i < sourceChildren.length; ++i) {
        const child = _sanitizeNode(sourceChildren[i], valid, used, ctx)
        if (child) {
            children.push(child)
            weights.push(sourceWeights[i])
        }
    }
    return DockLayout.normalize(DockTypes.split(
        ctx.newId("split"),
        raw.orientation === "vertical" ? "vertical" : "horizontal",
        DockLayout.normalizedWeights(weights, children.length),
        children
    ))
}

function _selection(root, saved) {
    return DockLayout.collectDocks(root).indexOf(String(saved)) >= 0
        ? String(saved) : DockLayout.firstActiveDock(root)
}

// Rebuilds an untrusted saved layout from known dock ids and fresh node ids,
// so it can never reference a dock twice or reuse a live id. Registered docks
// the layout does not mention are added to the first main group. Returns null
// when the layout cannot be read.
function sanitize(raw, dockIds, ctx) {
    if (!raw || typeof raw !== "object" || Number(raw.version) !== DockLayout.layoutVersion)
        return null

    const valid = {}
    const used = {}
    for (let i = 0; i < dockIds.length; ++i)
        valid[dockIds[i]] = true

    let main = null
    const floating = []
    const source = Array.isArray(raw.containers) ? raw.containers : []
    for (let i = 0; i < source.length; ++i) {
        const saved = source[i]
        if (!saved || typeof saved !== "object" || (saved.kind === "main" && main))
            continue
        if (saved.kind === "main") {
            const root = _sanitizeNode(saved.root, valid, used, ctx)
            main = DockTypes.mainContainer(root, _selection(root, saved.selected))
        } else if (saved.kind === "floating") {
            const root = _sanitizeNode(saved.root, valid, used, ctx)
            if (!root)
                continue
            const placed = ctx.fitFloating(saved.geometry, root, saved.screen ? String(saved.screen) : "")
            floating.push(DockTypes.floatingContainer(
                ctx.newId("float"), placed.geometry, placed.screen, root, _selection(root, saved.selected)))
        }
    }
    main = main || DockTypes.mainContainer(null, "")

    const hidden = []
    const savedHidden = Array.isArray(raw.hidden) ? raw.hidden : []
    for (let i = 0; i < savedHidden.length; ++i) {
        const dockId = String(savedHidden[i])
        if (valid[dockId] && !used[dockId]) {
            hidden.push(dockId)
            used[dockId] = true
        }
    }

    const missing = dockIds.filter(dockId => !used[dockId])
    if (missing.length) {
        const first = DockLayout.firstGroup(main.root)
        const root = first
            ? DockLayout.mapSpine(main.root, node => node === first
                ? DockTypes.tabs(first.id, first.docks.concat(missing), first.active) : undefined, false)
            : _group(ctx, missing)
        main = DockTypes.mainContainer(root, main.selected || DockLayout.firstActiveDock(root))
    }
    return DockLayout.snapshotWith([main].concat(floating), hidden)
}

// Enforces the snapshot invariant against the registered docks: each one
// appears exactly once across the containers and `hidden`, nothing else
// appears, empty floating containers are dropped, and every container's
// `selected` names one of its own docks. Registered docks the snapshot does
// not mention become hidden. Returns the input when it already holds.
function reconcile(snapshot, dockIds) {
    const known = {}
    for (let i = 0; i < dockIds.length; ++i)
        known[dockIds[i]] = true
    const seen = {}
    const claim = dockId => {
        if (!known[dockId] || seen[dockId])
            return false
        seen[dockId] = true
        return true
    }

    let changed = snapshot.version !== DockLayout.layoutVersion
    let hasMain = false
    const containers = []
    for (let i = 0; i < snapshot.containers.length; ++i) {
        const container = snapshot.containers[i]
        if (container.kind === "main" && hasMain) {
            changed = true
            continue
        }
        hasMain = hasMain || container.kind === "main"

        const root = DockLayout.mapSpine(container.root, node => {
            if (node.kind !== "tabs")
                return undefined
            const docks = node.docks.filter(claim)
            if (docks.length === node.docks.length)
                return node
            return docks.length ? DockTypes.tabs(node.id, docks, docks.indexOf(node.active) >= 0 ? node.active : docks[0]) : null
        }, true)
        if (!root && container.kind === "floating") {
            changed = true
            continue
        }
        let next = root === container.root ? container : DockLayout.containerWithRoot(container, root)
        const selected = _selection(root, next.selected)
        if (selected !== next.selected)
            next = DockLayout.containerWithSelection(next, selected)
        changed = changed || next !== container
        containers.push(next)
    }
    if (!hasMain) {
        containers.unshift(DockTypes.mainContainer(null, ""))
        changed = true
    }

    const hidden = snapshot.hidden.filter(claim)
    changed = changed || hidden.length !== snapshot.hidden.length
    for (let i = 0; i < dockIds.length; ++i) {
        if (!seen[dockIds[i]]) {
            hidden.push(dockIds[i])
            changed = true
        }
    }
    return changed ? DockLayout.snapshotWith(containers, hidden) : snapshot
}
