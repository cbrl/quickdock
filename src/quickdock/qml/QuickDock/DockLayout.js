.pragma library
.import "DockTypes.js" as DockTypes

// Pure layout algebra: tree queries and edits with structural sharing, size
// limits, geometry, and drop-zone math. Nothing here touches QML objects.
// Dock size limits come from a `limitsOf(dockId)` callback that returns
// `{minimum: {width, height}, maximum: {width, height}}` or null, and header
// and splitter sizes come from `metrics = {header, splitter}`.

var layoutVersion = 2

// Qt's largest supported item dimension, used as "no maximum".
var unlimited = 16777215

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

function _clamp(value, lower, upper) {
    return Math.max(lower, Math.min(upper, value))
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
    for (let i = 0; i < result.length; ++i)
        result[i] /= total
    return result
}

// --- Queries ----------------------------------------------------------------

function collectDocks(node, result) {
    result = result || []
    if (!node)
        return result
    if (node.kind === "tabs") {
        for (let i = 0; i < node.docks.length; ++i)
            result.push(node.docks[i])
    } else if (node.kind === "split") {
        for (let i = 0; i < node.children.length; ++i)
            collectDocks(node.children[i], result)
    }
    return result
}

// Depth-first search for the first node matching predicate.
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
    return find(node, candidate => candidate.kind === "tabs" && candidate.docks.indexOf(dockId) >= 0)
}

function findNode(node, nodeId) {
    return find(node, candidate => candidate.id === nodeId)
}

function firstGroup(node) {
    return find(node, candidate => candidate.kind === "tabs")
}

function firstActiveDock(node) {
    const group = firstGroup(node)
    return group ? group.active : ""
}

// Docks in the same group and in the adjacent siblings of each ancestor split.
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

// --- Normalization and edits --------------------------------------------------

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
    return DockTypes.tabs(node.id, docks, active)
}

// Drops empty nodes, collapses single-child splits, and flattens nested splits
// that share an orientation while preserving each pane's relative weight.
// Returns the same node when nothing changes.
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
    let changed = orientation !== node.orientation

    for (let i = 0; i < sourceChildren.length; ++i) {
        const child = normalize(sourceChildren[i])
        if (child !== sourceChildren[i])
            changed = true
        if (!child)
            continue
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
    if (!changed && Array.isArray(node.weights) && node.weights.length === children.length) {
        let same = true
        for (let i = 0; same && i < finalWeights.length; ++i)
            same = Math.abs(finalWeights[i] - Number(node.weights[i])) < 1e-9
        if (same)
            return node
    }
    return DockTypes.split(node.id, orientation, finalWeights, children)
}

// Applies transform at every node. transform returns undefined for "keep
// walking"; any other value (including null) replaces the node. Ancestors of
// a change are copied, untouched siblings are shared, and the ancestors are
// renormalized when requested (needed after removals or insertions).
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

    const rebuilt = DockTypes.split(node.id, node.orientation, node.weights, nextChildren)
    return normalizeAncestors ? normalize(rebuilt) : rebuilt
}

function _replaceNode(node, nodeId, replacement) {
    return mapSpine(node, candidate => candidate.id === nodeId ? replacement : undefined, true)
}

function withSplitRatio(node, splitId, splitterIndex, ratio) {
    return mapSpine(node, function(candidate) {
        if (candidate.kind !== "split" || candidate.id !== splitId)
            return undefined
        const index = Math.max(0, Math.floor(Number(splitterIndex)))
        const bounded = _clamp(Number(ratio), 0, 1)
        if (index >= candidate.children.length - 1 || !isFinite(bounded))
            return candidate

        const weights = normalizedWeights(candidate.weights, candidate.children.length)
        const pairWeight = weights[index] + weights[index + 1]
        const firstWeight = pairWeight * bounded
        if (Math.abs(weights[index] - firstWeight) < 1e-9)
            return candidate
        weights[index] = firstWeight
        weights[index + 1] = pairWeight - firstWeight
        return DockTypes.split(candidate.id, candidate.orientation, weights, candidate.children)
    }, false)
}

function withDockRemoved(node, dockId) {
    return mapSpine(node, function(candidate) {
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
        return DockTypes.tabs(candidate.id, docks, active)
    }, true)
}

function withActiveDock(node, dockId) {
    return mapSpine(node, function(candidate) {
        if (candidate.kind !== "tabs")
            return undefined
        if (candidate.docks.indexOf(dockId) < 0 || candidate.active === dockId)
            return candidate
        return DockTypes.tabs(candidate.id, candidate.docks, dockId)
    }, false)
}

// "left"/"top" put the new node first; "left"/"right" split horizontally.
function splitPlacement(zone) {
    return {
        horizontal: zone === "left" || zone === "right",
        before: zone === "left" || zone === "top"
    }
}

function _splitAround(existing, inserted, zone, splitId, ratio) {
    const placement = splitPlacement(zone)
    const value = Number(ratio)
    const share = isFinite(value) ? _clamp(value, 0, 1) : 0.5
    return DockTypes.split(
        splitId,
        placement.horizontal ? "horizontal" : "vertical",
        placement.before ? [share, 1 - share] : [1 - share, share],
        placement.before ? [inserted, existing] : [existing, inserted]
    )
}

// Inserts a subtree relative to a tab group. A "center" drop merges a tabs
// node into the group at `tabIndex` (the final index of the first inserted
// tab; negative appends). Any other zone splits the group, giving the new
// node `ratio` of the space. Returns the root unchanged when the group is
// missing or a non-tabs node is dropped in the center.
function withNodeInserted(root, groupId, node, zone, splitId, tabIndex, ratio) {
    if (!root)
        return node
    const target = findGroup(root, groupId)
    if (!target || !node)
        return root

    if (!zone || zone === "center") {
        if (node.kind !== "tabs")
            return root
        let index = Math.floor(Number(tabIndex))
        if (!isFinite(index) || index < 0 || index > target.docks.length)
            index = target.docks.length
        const docks = target.docks.slice()
        docks.splice.apply(docks, [index, 0].concat(node.docks))
        return _replaceNode(root, groupId, DockTypes.tabs(target.id, docks, node.active))
    }
    return normalize(_replaceNode(root, groupId, _splitAround(target, node, zone, splitId, ratio)))
}

// Inserts a subtree along one outer edge of a container's root.
function withNodeAtRoot(root, node, zone, splitId, ratio) {
    if (!root)
        return node
    if (!node)
        return root
    return normalize(_splitAround(root, node, zone, splitId, ratio))
}

// --- Size limits and geometry ---------------------------------------------------

function _size(width, height) {
    return {width: width, height: height}
}

function _metric(metrics, key) {
    return Math.max(0, Number(metrics && metrics[key]) || 0)
}

function _dockLimits(dockId, limitsOf) {
    const limits = typeof limitsOf === "function" ? limitsOf(dockId) : null
    const minimum = limits && limits.minimum
    const maximum = limits && limits.maximum
    const bound = value => {
        const number = Number(value)
        return isFinite(number) && number > 0 ? Math.min(unlimited, number) : unlimited
    }
    return {
        minimum: _size(Math.max(0, Number(minimum && minimum.width) || 0),
                       Math.max(0, Number(minimum && minimum.height) || 0)),
        maximum: _size(bound(maximum && maximum.width), bound(maximum && maximum.height))
    }
}

// The smallest and largest size a subtree can be rendered at. Tabbed docks
// overlap and pay for one header; split children add up along the split axis
// and pay for the splitters between them.
function sizeLimitsOf(node, limitsOf, metrics) {
    if (!node || (node.kind !== "tabs" && node.kind !== "split"))
        return {minimum: _size(0, 0), maximum: _size(unlimited, unlimited)}

    if (node.kind === "tabs") {
        const header = _metric(metrics, "header")
        const minimum = _size(0, 0)
        const maximum = _size(unlimited, unlimited)
        for (let i = 0; i < node.docks.length; ++i) {
            const limits = _dockLimits(node.docks[i], limitsOf)
            minimum.width = Math.max(minimum.width, limits.minimum.width)
            minimum.height = Math.max(minimum.height, limits.minimum.height)
            maximum.width = Math.min(maximum.width, limits.maximum.width)
            maximum.height = Math.min(maximum.height, limits.maximum.height)
        }
        minimum.height += header
        maximum.height = Math.min(unlimited, maximum.height + header)
        return {minimum: minimum, maximum: maximum}
    }

    const horizontal = node.orientation === "horizontal"
    const splitters = (node.children.length - 1) * _metric(metrics, "splitter")
    const minimum = _size(0, 0)
    const maximum = horizontal ? _size(splitters, unlimited) : _size(unlimited, splitters)
    if (horizontal)
        minimum.width = splitters
    else
        minimum.height = splitters
    for (let i = 0; i < node.children.length; ++i) {
        const limits = sizeLimitsOf(node.children[i], limitsOf, metrics)
        if (horizontal) {
            minimum.width += limits.minimum.width
            minimum.height = Math.max(minimum.height, limits.minimum.height)
            maximum.width = Math.min(unlimited, maximum.width + limits.maximum.width)
            maximum.height = Math.min(maximum.height, limits.maximum.height)
        } else {
            minimum.width = Math.max(minimum.width, limits.minimum.width)
            minimum.height += limits.minimum.height
            maximum.width = Math.min(maximum.width, limits.maximum.width)
            maximum.height = Math.min(unlimited, maximum.height + limits.maximum.height)
        }
    }
    return {minimum: minimum, maximum: maximum}
}

function _axisMinimums(node, limitsOf, metrics) {
    const horizontal = node.orientation === "horizontal"
    return node.children.map(child => {
        const minimum = sizeLimitsOf(child, limitsOf, metrics).minimum
        return Math.max(0, horizontal ? minimum.width : minimum.height)
    })
}

// Pixel lengths of a split's children along its axis, excluding splitters.
// Panes that would fall below their minimum are pinned to it and the rest
// share the remaining space by weight. When even the minimums do not fit,
// they are scaled down proportionally so the split still fills its space.
function constrainedLengths(node, availableLength, limitsOf, metrics, minimums) {
    if (!node || node.kind !== "split")
        return []
    const count = node.children.length
    const available = Math.max(0, Number(availableLength) || 0)
    const weights = normalizedWeights(node.weights, count)
    minimums = minimums || _axisMinimums(node, limitsOf, metrics)
    const minimumTotal = minimums.reduce((total, value) => total + value, 0)

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
    let remainingWeight = 1
    const free = []
    for (let i = 0; i < count; ++i)
        free.push(i)
    let changed = true
    while (changed && free.length) {
        changed = false
        for (let i = free.length - 1; i >= 0; --i) {
            const index = free[i]
            const proposed = remainingWeight > 0 ? remaining * weights[index] / remainingWeight : 0
            if (proposed + 0.01 < minimums[index]) {
                result[index] = minimums[index]
                remaining -= minimums[index]
                remainingWeight -= weights[index]
                free.splice(i, 1)
                changed = true
            }
        }
    }
    let used = 0
    for (let i = 0; i < free.length; ++i) {
        const index = free[i]
        result[index] = i === free.length - 1
            ? Math.max(0, remaining - used)
            : Math.max(0, Math.round(remaining * weights[index] / remainingWeight))
        used += result[index]
    }
    return result
}

// Lays out a container's tree inside a width x height box. Returns tab group
// rects keyed by group id, and splitter rects keyed by "splitId:index" with
// what a splitter drag needs (the split's current lengths and minimums).
// `override = {splitId, lengths}` substitutes live lengths during a drag.
function computeGeometry(root, width, height, limitsOf, metrics, override) {
    const result = {groups: {}, splitters: {}}
    const splitterSize = _metric(metrics, "splitter")

    function visit(node, x, y, w, h) {
        if (!node)
            return
        if (node.kind === "tabs") {
            result.groups[node.id] = {x: x, y: y, width: w, height: h, node: node}
            return
        }
        const horizontal = node.orientation === "horizontal"
        const count = node.children.length
        const available = Math.max(0, (horizontal ? w : h) - splitterSize * (count - 1))
        const minimums = _axisMinimums(node, limitsOf, metrics)
        const lengths = override && override.splitId === node.id && override.lengths.length === count
            ? override.lengths
            : constrainedLengths(node, available, limitsOf, metrics, minimums)

        let offset = 0
        for (let i = 0; i < count; ++i) {
            if (horizontal)
                visit(node.children[i], x + offset, y, lengths[i], h)
            else
                visit(node.children[i], x, y + offset, w, lengths[i])
            offset += lengths[i]
            if (i + 1 < count) {
                result.splitters[node.id + ":" + i] = {
                    x: horizontal ? x + offset : x,
                    y: horizontal ? y : y + offset,
                    width: horizontal ? splitterSize : w,
                    height: horizontal ? h : splitterSize,
                    splitId: node.id,
                    index: i,
                    horizontal: horizontal,
                    lengths: lengths,
                    minimums: minimums
                }
            }
            offset += splitterSize
        }
    }

    visit(root, 0, 0, Math.max(0, width), Math.max(0, height))
    return result
}

// Lengths for a live splitter drag: the pair around `index` keeps its total,
// the splitter moves by `delta`, and neither pane goes below its minimum.
function draggedLengths(lengths, minimums, index, delta) {
    const pair = lengths[index] + lengths[index + 1]
    const lower = Math.min(pair, minimums[index])
    const upper = Math.max(lower, pair - minimums[index + 1])
    const first = _clamp(lengths[index] + delta, lower, upper)
    const result = lengths.slice()
    result[index] = first
    result[index + 1] = pair - first
    return result
}

// Size limits of a floating window around a container: the content limits,
// the window floor, and the title bar a multi-dock container gets.
function floatingLimits(content, titleBarHeight, floor) {
    content = content || sizeLimitsOf(null)
    const titleBar = Math.max(0, Number(titleBarHeight) || 0)
    const minimum = _size(
        Math.max(Number(floor && floor.width) || 0, content.minimum.width),
        Math.max(Number(floor && floor.height) || 0, content.minimum.height + titleBar)
    )
    return {
        minimum: minimum,
        maximum: _size(
            Math.max(minimum.width, content.maximum.width),
            Math.max(minimum.height, Math.min(unlimited, content.maximum.height + titleBar))
        )
    }
}

// Rounds a rect and fits it to size limits and, when given, a screen area so
// the window stays reachable.
function fitGeometry(rect, limits, area) {
    let width = _clamp(Math.round(Number(rect.width)), limits.minimum.width, limits.maximum.width)
    let height = _clamp(Math.round(Number(rect.height)), limits.minimum.height, limits.maximum.height)
    let x = Math.round(Number(rect.x))
    let y = Math.round(Number(rect.y))
    if (area && area.width > 0 && area.height > 0) {
        width = Math.min(width, area.width)
        height = Math.min(height, area.height)
        x = _clamp(x, area.x, area.x + area.width - width)
        y = _clamp(y, area.y, area.y + area.height - height)
    }
    return DockTypes.rect(x, y, width, height)
}

// --- Drop zones -----------------------------------------------------------------

// The edge whose band contains the point, nearest first; "center" otherwise.
// Distances are normalized by each axis's band.
function nearestEdgeZone(x, y, width, height, bandX, bandY) {
    const candidates = []
    if (x < bandX)
        candidates.push({zone: "left", distance: bandX > 0 ? x / bandX : 1})
    if (x > width - bandX)
        candidates.push({zone: "right", distance: bandX > 0 ? (width - x) / bandX : 1})
    if (y < bandY)
        candidates.push({zone: "top", distance: bandY > 0 ? y / bandY : 1})
    if (y > height - bandY)
        candidates.push({zone: "bottom", distance: bandY > 0 ? (height - y) / bandY : 1})
    if (!candidates.length)
        return "center"
    candidates.sort((first, second) => first.distance - second.distance)
    return candidates[0].zone
}

// Zone within a tab group: bands are a fraction of each side, capped in pixels.
function edgeZone(x, y, width, height, fraction, maxBand) {
    return nearestEdgeZone(x, y, width, height,
                           Math.min(width * fraction, maxBand),
                           Math.min(height * fraction, maxBand))
}

// Zone along a container's outer edge: a fixed, narrow pixel band.
function outerEdgeZone(x, y, width, height, band) {
    const size = Math.max(1, band)
    return nearestEdgeZone(x, y, width, height, size, size)
}

// The part of `rect` a drop in `zone` would occupy.
function previewRect(rect, zone, ratio) {
    const result = DockTypes.rect(rect.x, rect.y, rect.width, rect.height)
    if (zone === "left") {
        result.width *= ratio
    } else if (zone === "right") {
        result.x += result.width * (1 - ratio)
        result.width *= ratio
    } else if (zone === "top") {
        result.height *= ratio
    } else if (zone === "bottom") {
        result.y += result.height * (1 - ratio)
        result.height *= ratio
    }
    return result
}

// --- Snapshots and containers -----------------------------------------------------

function snapshotWith(containers, hidden) {
    return DockTypes.snapshot(layoutVersion, containers, hidden)
}

function containerWithRoot(container, root) {
    if (container.kind === "main")
        return DockTypes.mainContainer(root, container.selected)
    return DockTypes.floatingContainer(container.id, container.geometry, container.screen, root, container.selected)
}

function containerWithSelection(container, selected) {
    const copy = containerWithRoot(container, container.root)
    copy.selected = selected
    return copy
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
    return DockTypes.mainContainer(null, "")
}

// Removes a dock from every container. Floating containers left empty go away.
function withoutDock(containers, dockId) {
    const next = []
    for (let i = 0; i < containers.length; ++i) {
        const container = containers[i]
        const root = withDockRemoved(container.root, dockId)
        if (root === container.root)
            next.push(container)
        else if (root || container.kind === "main")
            next.push(containerWithRoot(container, root))
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
