.pragma library

// Named data classes for records shared by the layout engine and QML components.
// Properties are assigned directly so instances remain JSON-serializable and work
// like ordinary JavaScript objects when they cross the QML/Python boundary.

// Geometry records are shared by layout sizing, floating-window state, and drag previews.
class Size {
    constructor({width, height}) {
        this.width = width
        this.height = height
    }
}

class Rect {
    constructor({x, y, width, height}) {
        this.x = x
        this.y = y
        this.width = width
        this.height = height
    }
}

// Layout nodes form the recursive tree stored in each container.
class TabsNode {
    constructor({id, docks, active}) {
        this.kind = "tabs"
        this.id = id
        this.docks = docks
        this.active = active
    }
}

class SplitNode {
    constructor({id, orientation, weights, children}) {
        this.kind = "split"
        this.id = id
        this.orientation = orientation
        this.weights = weights
        this.children = children
    }
}

// Containers and snapshots make up the persisted versioned layout document.
class MainContainer {
    constructor({id, root, selected}) {
        this.id = id
        this.kind = "main"
        this.root = root
        this.selected = selected || ""
    }
}

class FloatingContainer {
    constructor({id, geometry, screen, root, selected}) {
        this.id = id
        this.kind = "floating"
        this.geometry = geometry
        this.screen = screen
        this.root = root
        this.selected = selected || ""
    }
}

class LayoutSnapshot {
    constructor({version, containers, hidden}) {
        this.version = version
        this.containers = containers
        this.hidden = hidden
    }
}

// Interaction records carry calculated placement and hit-test results between controllers.
class SplitPlacement {
    constructor({horizontal, before}) {
        this.horizontal = horizontal
        this.before = before
    }
}

class NodeHit {
    constructor({groupId, node, rect}) {
        this.groupId = groupId
        this.node = node
        this.rect = rect
    }
}

class DropTarget {
    constructor({containerId, groupId, zone, outer, tabIndex}) {
        this.containerId = containerId
        this.groupId = groupId
        this.zone = zone
        this.outer = outer
        this.tabIndex = tabIndex
    }
}

class DropSurface {
    constructor({state, item}) {
        this.state = state
        this.item = item
    }
}

// Factory functions are the public API because QML JavaScript imports expose functions
// consistently across all supported Qt versions.
function size(options) {
    return new Size(options)
}

function rect(options) {
    return new Rect(options)
}

function tabsNode(options) {
    return new TabsNode(options)
}

function splitNode(options) {
    return new SplitNode(options)
}

function mainContainer(options) {
    return new MainContainer(options)
}

function floatingContainer(options) {
    return new FloatingContainer(options)
}

function layoutSnapshot(options) {
    return new LayoutSnapshot(options)
}

function splitPlacement(options) {
    return new SplitPlacement(options)
}

function nodeHit(options) {
    return new NodeHit(options)
}

function dropTarget(options) {
    return new DropTarget(options)
}

function dropSurface(options) {
    return new DropSurface(options)
}
