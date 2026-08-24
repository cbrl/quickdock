.pragma library
.import "DockTypes.js" as DockTypes

var layoutVersion = 2

function _sameArray(first, second) {
    if (first === second)
        return true
    if (!first || !second || first.length !== second.length)
        return false
    for (let i = 0; i < first.length; ++i) {
        if (first[i] !== second[i])
            return false
    }
    return true
}

function _positive(value) {
    const number = Number(value)
    return isFinite(number) && number > 0 ? number : 1
}

function normalizedWeights(weights, count) {
    const source = Array.isArray(weights) ? weights : []
    const result = []
    let total = 0
    for (let i = 0; i < count; ++i) {
        const value = _positive(source[i])
        result.push(value)
        total += value
    }
    if (total <= 0)
        return result
    for (let i = 0; i < result.length; ++i)
        result[i] /= total
    return result
}

// Collecting into a caller-provided array keeps recursive traversals cheap and
// lets callers choose whether they need a new list or an accumulated result.
function collectDocks(node, result) {
    result = result || []
    if (!node)
        return result
    if (node.kind === "tabs") {
        const docks = Array.isArray(node.docks) ? node.docks : []
        for (let i = 0; i < docks.length; ++i)
            result.push(docks[i])
    } else if (node.kind === "split") {
        const children = Array.isArray(node.children) ? node.children : []
        for (let i = 0; i < children.length; ++i)
            collectDocks(children[i], result)
    }
    return result
}

// Depth-first search for the first node matching predicate. Tab groups are
// leaves. Split nodes are the only ones with children to recurse into.
function find(node, predicate) {
    if (!node)
        return null
    if (predicate(node))
        return node
    if (node.kind !== "split")
        return null
    for (let i = 0; i < node.children.length; ++i) {
        const result = find(node.children[i], predicate)
        if (result)
            return result
    }
    return null
}

function findGroup(node, groupId) {
    return find(node, candidate => candidate.kind === "tabs" && candidate.id === groupId)
}

function findGroupForDock(node, dockId) {
    return find(
        node,
        candidate => candidate.kind === "tabs"
                && candidate.docks.indexOf(dockId) >= 0
    )
}

function findNode(node, nodeId) {
    return find(node, candidate => candidate.id === nodeId)
}

function firstGroup(node) {
    return find(node, candidate => candidate.kind === "tabs")
}

function _normalizedTabs(node) {
    const source = Array.isArray(node.docks) ? node.docks : []
    const docks = []
    for (let i = 0; i < source.length; ++i) {
        const dockId = String(source[i])
        if (dockId && docks.indexOf(dockId) < 0)
            docks.push(dockId)
    }
    if (!docks.length)
        return null
    const active = docks.indexOf(node.active) >= 0 ? node.active : docks[0]
    if (_sameArray(docks, node.docks) && active === node.active)
        return node
    return DockTypes.tabsNode({id: node.id, docks: docks, active: active})
}

function normalize(node) {
    if (!node || typeof node !== "object")
        return null
    if (node.kind === "tabs")
        return _normalizedTabs(node)
    if (node.kind !== "split")
        return null

    const orientation = node.orientation === "vertical" ? "vertical" : "horizontal"
    const sourceChildren = Array.isArray(node.children) ? node.children : []
    const sourceWeights = normalizedWeights(node.weights, sourceChildren.length)
    const children = []
    const weights = []
    let changed = orientation !== node.orientation || !Array.isArray(node.children)

    for (let i = 0; i < sourceChildren.length; ++i) {
        const child = normalize(sourceChildren[i])
        if (!child) {
            changed = true
            continue
        }
        if (child !== sourceChildren[i])
            changed = true
        // Flatten nested splits with the same orientation. This keeps the
        // model shallow and preserves each descendant's relative weight.
        if (child.kind === "split" && child.orientation === orientation) {
            const nestedWeights = normalizedWeights(child.weights, child.children.length)
            for (let j = 0; j < child.children.length; ++j) {
                children.push(child.children[j])
                weights.push(sourceWeights[i] * nestedWeights[j])
            }
            changed = true
        } else {
            children.push(child)
            weights.push(sourceWeights[i])
        }
    }

    if (!children.length)
        return null
    if (children.length === 1)
        return children[0]

    const finalWeights = normalizedWeights(weights, children.length)
    if (!changed && _sameArray(children, node.children)) {
        const currentWeights = normalizedWeights(node.weights, children.length)
        let weightsChanged = !Array.isArray(node.weights)
                || currentWeights.length !== node.weights.length
        for (let i = 0; !weightsChanged && i < currentWeights.length; ++i)
            weightsChanged = Math.abs(currentWeights[i] - Number(node.weights[i])) > 1e-9
        if (!weightsChanged)
            return node
    }
    return DockTypes.splitNode({
        id: node.id,
        orientation: orientation,
        weights: finalWeights,
        children: children
    })
}

// Recurses the tree, applying transform at every node. transform returns
// undefined to mean "not a match, keep walking". Any other value (including
// null) replaces the node at that position. Split ancestors above a change
// are rebuilt with structural sharing of untouched siblings, optionally
// renormalized (needed whenever a transform can delete or restructure a
// child, e.g. dock removal. Not needed for pure metadata edits like weights
// or the active tab, which cannot make a split collapsible).
function mapSpine(node, transform, normalizeAncestors) {
    if (!node)
        return node
    const replaced = transform(node)
    if (replaced !== undefined)
        return replaced
    if (node.kind !== "split")
        return node

    let nextChildren = null
    for (let i = 0; i < node.children.length; ++i) {
        const child = mapSpine(node.children[i], transform, normalizeAncestors)
        if (child !== node.children[i]) {
            if (!nextChildren)
                nextChildren = node.children.slice()
            nextChildren[i] = child
        }
    }
    if (!nextChildren)
        return node

    const rebuilt = DockTypes.splitNode({
        id: node.id,
        orientation: node.orientation,
        weights: node.weights,
        children: nextChildren
    })
    return normalizeAncestors ? normalize(rebuilt) : rebuilt
}

function _replaceNode(node, nodeId, replacement) {
    return mapSpine(
        node,
        candidate => candidate.id === nodeId ? replacement : undefined,
        true
    )
}

function withSplitRatio(node, splitId, splitterIndex, ratio) {
    return mapSpine(
        node,
        function(candidate) {
            if (candidate.kind !== "split" || candidate.id !== splitId)
                return undefined
            const index = Math.max(0, Math.floor(Number(splitterIndex)))
            if (index >= candidate.children.length - 1)
                return candidate
            const bounded = Math.max(0, Math.min(1, Number(ratio)))
            if (!isFinite(bounded))
                return candidate

            const weights = normalizedWeights(candidate.weights, candidate.children.length)
            const pairWeight = weights[index] + weights[index + 1]
            const firstWeight = pairWeight * bounded
            const secondWeight = pairWeight - firstWeight
            if (Math.abs(weights[index] - firstWeight) < 1e-9
                    && Math.abs(weights[index + 1] - secondWeight) < 1e-9)
                return candidate
            weights[index] = firstWeight
            weights[index + 1] = secondWeight

            return DockTypes.splitNode({
                id: candidate.id,
                orientation: candidate.orientation,
                weights: weights,
                children: candidate.children
            })
        },
        false
    )
}

function withDockRemoved(node, dockId) {
    return mapSpine(
        node,
        function(candidate) {
            if (candidate.kind !== "tabs")
                return undefined
            const index = candidate.docks.indexOf(dockId)
            if (index < 0)
                return undefined

            const docks = candidate.docks.slice()
            docks.splice(index, 1)
            if (!docks.length)
                return null

            const active = candidate.active === dockId
                    ? docks[Math.min(index, docks.length - 1)] : candidate.active
            return DockTypes.tabsNode({id: candidate.id, docks: docks, active: active})
        },
        true
    )
}

function _splitWeights(ratio, before) {
    const value = Number(ratio)
    const bounded = isFinite(value) ? Math.max(0, Math.min(1, value)) : 0.5
    return before ? [bounded, 1 - bounded] : [1 - bounded, bounded]
}

function _newTabGroup(groupId, dockId) {
    return DockTypes.tabsNode({id: groupId, docks: [dockId], active: dockId})
}

function _splitPlacement(zone) {
    return DockTypes.splitPlacement({
        horizontal: zone === "left" || zone === "right",
        before: zone === "left" || zone === "top"
    })
}

function withDockInserted(node, targetGroupId, dockId, zone, groupId, splitId, tabIndex, splitRatio) {
    const placement = zone || "center"
    const newGroup = _newTabGroup(groupId, dockId)
    if (!node)
        return newGroup

    const target = findGroup(node, targetGroupId)
    if (!target)
        return node

    if (placement === "center") {
        let index = Math.floor(Number(tabIndex))
        if (!isFinite(index) || index < 0 || index > target.docks.length)
            index = target.docks.length

        const docks = target.docks.slice()
        const existing = docks.indexOf(dockId)
        if (existing >= 0)
            docks.splice(existing, 1)

        docks.splice(Math.min(index, docks.length), 0, dockId)

        return _replaceNode(
            node,
            targetGroupId,
            DockTypes.tabsNode({id: target.id, docks: docks, active: dockId})
        )
    }

    const placementInfo = _splitPlacement(placement)
    const replacement = DockTypes.splitNode({
        id: splitId,
        orientation: placementInfo.horizontal ? "horizontal" : "vertical",
        weights: _splitWeights(splitRatio, placementInfo.before),
        children: placementInfo.before ? [newGroup, target] : [target, newGroup]
    })
    return _replaceNode(node, targetGroupId, replacement)
}

function withDockInsertedAtRoot(node, dockId, zone, groupId, splitId, splitRatio) {
    const newGroup = _newTabGroup(groupId, dockId)
    if (!node)
        return newGroup

    const placementInfo = _splitPlacement(zone)
    return normalize(DockTypes.splitNode({
        id: splitId,
        orientation: placementInfo.horizontal ? "horizontal" : "vertical",
        weights: _splitWeights(splitRatio, placementInfo.before),
        children: placementInfo.before ? [newGroup, node] : [node, newGroup]
    }))
}

// Container-title drags move a complete layout subtree. Directional drops
// preserve that subtree, while center drops merge a tabs root into the target
// group without changing the order of either tab list.
function withNodeInserted(node, targetGroupId, insertedNode, zone, splitId, tabIndex, splitRatio) {
    if (!node)
        return insertedNode

    const target = findGroup(node, targetGroupId)
    if (!target || !insertedNode)
        return node

    const placement = zone || "center"
    if (placement === "center") {
        if (insertedNode.kind !== "tabs")
            return node

        let index = Math.floor(Number(tabIndex))
        if (!isFinite(index) || index < 0 || index > target.docks.length)
            index = target.docks.length

        const docks = target.docks.slice()
        docks.splice.apply(docks, [index, 0].concat(insertedNode.docks))
        return _replaceNode(
            node,
            targetGroupId,
            DockTypes.tabsNode({id: target.id, docks: docks, active: insertedNode.active})
        )
    }

    const placementInfo = _splitPlacement(placement)
    const replacement = DockTypes.splitNode({
        id: splitId,
        orientation: placementInfo.horizontal ? "horizontal" : "vertical",
        weights: _splitWeights(splitRatio, placementInfo.before),
        children: placementInfo.before ? [insertedNode, target] : [target, insertedNode]
    })
    return _replaceNode(node, targetGroupId, replacement)
}

function withNodeInsertedAtRoot(node, insertedNode, zone, splitId, splitRatio) {
    if (!node)
        return insertedNode
    if (!insertedNode)
        return node

    const placementInfo = _splitPlacement(zone)
    return normalize(DockTypes.splitNode({
        id: splitId,
        orientation: placementInfo.horizontal ? "horizontal" : "vertical",
        weights: _splitWeights(splitRatio, placementInfo.before),
        children: placementInfo.before ? [insertedNode, node] : [node, insertedNode]
    }))
}

function withActiveDock(node, dockId) {
    return mapSpine(
        node,
        function(candidate) {
            if (candidate.kind !== "tabs")
                return undefined
            if (candidate.docks.indexOf(dockId) < 0 || candidate.active === dockId)
                return candidate
            return DockTypes.tabsNode({
                id: candidate.id,
                docks: candidate.docks,
                active: dockId
            })
        },
        false
    )
}

function withTabMoved(node, groupId, fromIndex, toIndex) {
    const group = findGroup(node, groupId)
    if (!group)
        return node
    const from = Math.floor(Number(fromIndex))
    let to = Math.floor(Number(toIndex))
    if (from < 0 || from >= group.docks.length || !isFinite(to))
        return node
    to = Math.max(0, Math.min(group.docks.length - 1, to))
    if (from === to)
        return node
    const docks = group.docks.slice()
    const dockId = docks.splice(from, 1)[0]
    docks.splice(to, 0, dockId)
    return _replaceNode(
        node,
        groupId,
        DockTypes.tabsNode({id: group.id, docks: docks, active: group.active})
    )
}

function _dockMinimum(dockId, resolver) {
    let value = null
    if (typeof resolver === "function")
        value = resolver(dockId)
    else if (resolver && typeof resolver === "object")
        value = resolver[dockId]
    return DockTypes.size({
        width: Math.max(0, Number(value && value.width) || 0),
        height: Math.max(0, Number(value && value.height) || 0)
    })
}

function minimumSizeOf(node, resolver, headerHeight, splitterSize) {
    if (!node)
        return DockTypes.size({width: 0, height: 0})
    if (node.kind === "tabs") {
        let width = 0
        let height = 0
        for (let i = 0; i < node.docks.length; ++i) {
            const size = _dockMinimum(node.docks[i], resolver)
            width = Math.max(width, size.width)
            height = Math.max(height, size.height)
        }
        return DockTypes.size({
            width: width,
            height: height + Math.max(0, Number(headerHeight) || 0)
        })
    }
    if (node.kind !== "split")
        return DockTypes.size({width: 0, height: 0})
    const horizontal = node.orientation === "horizontal"
    let width = 0
    let height = 0
    for (let i = 0; i < node.children.length; ++i) {
        const size = minimumSizeOf(
            node.children[i],
            resolver,
            headerHeight,
            splitterSize
        )
        if (horizontal) {
            width += size.width
            height = Math.max(height, size.height)
        } else {
            width = Math.max(width, size.width)
            height += size.height
        }
    }
    const splitters = Math.max(0, node.children.length - 1)
            * Math.max(0, Number(splitterSize) || 0)
    if (horizontal)
        width += splitters
    else
        height += splitters
    return DockTypes.size({width: width, height: height})
}

function maximumSizeOf(node, resolver, headerHeight, splitterSize) {
    const unlimited = 16777215
    if (!node)
        return DockTypes.size({width: unlimited, height: unlimited})
    if (node.kind === "tabs") {
        let width = unlimited
        let height = unlimited
        for (let i = 0; i < node.docks.length; ++i) {
            const size = resolver(node.docks[i])
            if (!size)
                continue
            const itemWidth = Number(size.width)
            const itemHeight = Number(size.height)
            width = Math.min(
                width,
                isFinite(itemWidth) && itemWidth > 0 ? itemWidth : unlimited
            )
            height = Math.min(
                height,
                isFinite(itemHeight) && itemHeight > 0 ? itemHeight : unlimited
            )
        }
        return DockTypes.size({
            width: width,
            height: Math.min(unlimited, height + Math.max(0, Number(headerHeight) || 0))
        })
    }
    if (node.kind !== "split")
        return DockTypes.size({width: unlimited, height: unlimited})
    const horizontal = node.orientation === "horizontal"
    let width = horizontal ? 0 : unlimited
    let height = horizontal ? unlimited : 0
    for (let i = 0; i < node.children.length; ++i) {
        const size = maximumSizeOf(
            node.children[i],
            resolver,
            headerHeight,
            splitterSize
        )
        if (horizontal) {
            width = Math.min(unlimited, width + size.width)
            height = Math.min(height, size.height)
        } else {
            width = Math.min(width, size.width)
            height = Math.min(unlimited, height + size.height)
        }
    }
    const splitters = Math.max(0, node.children.length - 1)
            * Math.max(0, Number(splitterSize) || 0)
    if (horizontal)
        width = Math.min(unlimited, width + splitters)
    else
        height = Math.min(unlimited, height + splitters)
    return DockTypes.size({width: width, height: height})
}

function constrainedLengths(node, availableLength, resolver, headerHeight, splitterSize) {
    if (!node || node.kind !== "split")
        return []
    const count = node.children.length
    const available = Math.max(0, Number(availableLength) || 0)
    const horizontal = node.orientation === "horizontal"
    const weights = normalizedWeights(node.weights, count)
    const minimums = []
    let minimumTotal = 0
    for (let i = 0; i < count; ++i) {
        const size = minimumSizeOf(
            node.children[i],
            resolver,
            headerHeight,
            splitterSize
        )
        const minimum = Math.max(0, horizontal ? size.width : size.height)
        minimums.push(minimum)
        minimumTotal += minimum
    }

    // If minimums cannot fit, scale them proportionally so the layout still
    // fills its viewport. Otherwise, pin panes that would fall below their
    // minimum and distribute the remaining space by the saved weights.
    const result = new Array(count).fill(0)
    if (minimumTotal >= available && minimumTotal > 0) {
        const scale = available / minimumTotal
        let used = 0
        for (let i = 0; i < count; ++i) {
            result[i] = i === count - 1
                    ? Math.max(0, available - used)
                    : Math.max(0, Math.round(minimums[i] * scale))
            used += result[i]
        }
        return result
    }

    let remaining = available
    let remainingWeight = 0
    const active = []
    for (let i = 0; i < count; ++i) {
        active.push(i)
        remainingWeight += weights[i]
    }
    let changed = true
    while (changed && active.length) {
        changed = false
        for (let i = active.length - 1; i >= 0; --i) {
            const index = active[i]
            const proposed = remainingWeight > 0
                    ? remaining * weights[index] / remainingWeight : 0
            if (proposed + 0.01 < minimums[index]) {
                result[index] = minimums[index]
                remaining -= minimums[index]
                remainingWeight -= weights[index]
                active.splice(i, 1)
                changed = true
            }
        }
    }
    let used = 0
    for (let i = 0; i < active.length; ++i) {
        const index = active[i]
        const last = i === active.length - 1
        result[index] = last
                ? Math.max(0, remaining - used)
                : Math.max(
                      0,
                      Math.round(remaining * weights[index] / remainingWeight)
                  )
        used += result[index]
    }
    return result
}

function neighborsOf(node, dockId) {
    const result = []
    function appendDocks(value) {
        const docks = collectDocks(value)
        for (let i = 0; i < docks.length; ++i) {
            if (docks[i] !== dockId && result.indexOf(docks[i]) < 0)
                result.push(docks[i])
        }
    }
    function visit(value) {
        if (!value)
            return false
        if (value.kind === "tabs") {
            if (value.docks.indexOf(dockId) < 0)
                return false
            appendDocks(value)
            return true
        }
        if (value.kind !== "split")
            return false
        for (let i = 0; i < value.children.length; ++i) {
            if (!visit(value.children[i]))
                continue
            if (i > 0)
                appendDocks(value.children[i - 1])
            if (i + 1 < value.children.length)
                appendDocks(value.children[i + 1])
            return true
        }
        return false
    }
    visit(node)
    return result
}

// --- Snapshot / container algebra -----------------------------------------
// State construction is centralized in DockTypes so every returned record has
// an explicit class while preserving the immutable, JSON-compatible API.

function snapshotWith(containers, hidden) {
    return DockTypes.layoutSnapshot({
        version: layoutVersion,
        containers: containers,
        hidden: hidden || []
    })
}

function containerWithRoot(container, nextRoot) {
    if (container.kind === "main")
        return DockTypes.mainContainer({id: container.id, root: nextRoot, selected: container.selected})
    return DockTypes.floatingContainer({
        id: container.id,
        geometry: container.geometry,
        screen: container.screen || "",
        root: nextRoot,
        selected: container.selected
    })
}

function containerById(containers, id) {
    for (let i = 0; i < containers.length; ++i) {
        if (containers[i].id === id)
            return containers[i]
    }
    return null
}

function containerForDock(containers, dockId) {
    for (let i = 0; i < containers.length; ++i) {
        if (findGroupForDock(containers[i].root, dockId))
            return containers[i]
    }
    return null
}

function mainContainer(containers) {
    for (let i = 0; i < containers.length; ++i) {
        if (containers[i].kind === "main")
            return containers[i]
    }
    return DockTypes.mainContainer({id: "main", root: null, selected: ""})
}

function firstActiveDock(node) {
    if (!node)
        return ""
    if (node.kind === "tabs")
        return node.active || (node.docks.length ? node.docks[0] : "")
    for (let i = 0; i < node.children.length; ++i) {
        const dockId = firstActiveDock(node.children[i])
        if (dockId)
            return dockId
    }
    return ""
}

function withoutDock(containers, dockId) {
    const next = []
    for (let i = 0; i < containers.length; ++i) {
        const container = containers[i]
        const rootAfter = withDockRemoved(container.root, dockId)
        if (container.kind === "floating" && !rootAfter)
            continue
        next.push(containerWithRoot(container, rootAfter))
    }
    return next
}

function deepFreeze(value) {
    if (!value || typeof value !== "object" || Object.isFrozen(value))
        return value

    Object.freeze(value)

    const keys = Object.keys(value)
    for (let i = 0; i < keys.length; ++i)
        deepFreeze(value[keys[i]])

    return value
}
