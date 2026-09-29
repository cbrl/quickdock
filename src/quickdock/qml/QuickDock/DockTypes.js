.pragma library

// Factories for the records persisted in a layout snapshot. They are plain
// objects so a snapshot is directly convertible to JSON.

function tabs(id, docks, active) {
    return {kind: "tabs", id: id, docks: docks, active: active || docks[0] || ""}
}

function split(id, orientation, weights, children) {
    return {kind: "split", id: id, orientation: orientation, weights: weights, children: children}
}

function mainContainer(root, selected) {
    return {id: "main", kind: "main", root: root, selected: selected || ""}
}

function floatingContainer(id, geometry, screen, root, selected) {
    return {
        id: id,
        kind: "floating",
        geometry: geometry,
        screen: screen || "",
        root: root,
        selected: selected || ""
    }
}

function snapshot(version, containers, hidden) {
    return {version: version, containers: containers, hidden: hidden || []}
}

function rect(x, y, width, height) {
    return {x: x, y: y, width: width, height: height}
}
