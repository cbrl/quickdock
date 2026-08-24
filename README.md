# QuickDock

QuickDock is a pure Qt Quick docking system for QML applications. A
`DockWorkspace` arranges `DockItem`s as tabs and N-way splits, opens floating
containers as native `Window`s, persists the complete layout, and exposes the
same operations for menus, shortcuts, and application controllers.

## Install and run the demo

QuickDock requires Python 3.10+ and PySide6 6.6+ when hosted from Python.

```bash
python -m pip install -e .
python -m quickdock.demo
```

Drag a title or tab to move a dock. A translucent snapshot follows a docked
panel during the drag. Drop over a panel center to create or reorder tabs, over
an inner edge to split that group, or over the narrow outer edge to split the
whole container.

Dropping away from every target creates a floating window, which can itself
contain tabs and splits, and can be docked back into the main workspace or
another floating container. A floating container with multiple docks has a
separate title bar. Drag it to move the whole window and drop its complete
layout tree onto a docking surface, or drag a tab to move only that dock. Its
title-bar dock button returns the complete container to the main workspace.

## Quick start

For a Python-hosted QML engine, install the module import path before loading
the root QML file:

```python
from PySide6.QtQml import QQmlApplicationEngine
from quickdock import install_docking

engine = QQmlApplicationEngine()
install_docking(engine)
engine.load("Main.qml")
```

QML-only applications can instead add the directory containing `QuickDock` to
their QML import path.

Declare docks directly in a workspace and create the initial arrangement with
the public layout operations:

```qml
import QtQuick
import QuickDock 1.0

DockWorkspace {
    id: workspace
    anchors.fill: parent
    centralDockId: "editor"

    DockItem {
        dockId: "editor"
        title: qsTr("Editor")
        minimumSize: Qt.size(400, 240)
        Rectangle { anchors.fill: parent; color: "#20242d" }
    }

    DockItem {
        dockId: "outline"
        title: qsTr("Outline")
        preferredSize: Qt.size(300, 500)
        closePolicy: DockItem.Hide
        allowedZones: ["left", "right", "center"]
        OutlineView { anchors.fill: parent }
    }

    DockItem {
        dockId: "console"
        title: qsTr("Console")
        ConsoleView { anchors.fill: parent }
    }

    Component.onCompleted: {
        resetLayout()
        splitDock("outline", "editor", "left")
        splitDock("console", "editor", "bottom")
    }
}
```

`centralDockId` identifies a permanent main-region dock. It cannot be closed,
hidden, floated, or dragged, regardless of its `DockItem` policy properties.

## Creating docks dynamically

Use `createDock()` when the workspace should own the object:

```qml
Component {
    id: searchDockFactory

    DockItem {
        dockId: "search"
        title: qsTr("Search")
        closePolicy: DockItem.Destroy
        SearchPanel { anchors.fill: parent }
    }
}

Component.onCompleted: {
    workspace.createDock(
        searchDockFactory,
        { toolTip: qsTr("Search results") },
        "editor",
        "right"
    )
}
```

`createDock(component, initialProperties, targetDockId, zone)` returns the new
`DockItem` or `null`. `registerDock(item, targetDockId, zone, takeOwnership)`
adds an existing item. An externally owned item is never destroyed by a close
operation unless it was registered with `takeOwnership: true`; it is hidden
instead.

The valid zones are `center`, `left`, `right`, `top`, and `bottom`. `center`
means a tab insertion. `allowedZones` controls where a dock can be dropped,
while `tabbable` controls whether it may join a tab group.

## DockItem API

| Property                   | Purpose                                                         |
|----------------------------|-----------------------------------------------------------------|
| `dockId`                   | Required stable identity used by APIs and saved layouts.        |
| `title`, `icon`, `toolTip` | Header and overflow-menu presentation.                          |
| `minimumSize`              | Propagates through split trees and constrains floating windows. |
| `maximumSize`              | Constrains floating windows.                                    |
| `preferredSize`            | Default size when the dock first becomes floating.              |
| `closable`                 | Enables application and header close operations.                |
| `floatable`                | Enables undocking and explicit `floatDock()`.                   |
| `tabbable`                 | Allows the dock to join compatible tab groups.                  |
| `headerButtonsVisible`     | Shows or hides the header/tab action buttons.                   |
| `allowedZones`             | Array of accepted drop zones.                                   |
| `closePolicy`              | `DockItem.Destroy` or `DockItem.Hide`.                          |

Closing and ownership are independent. `Destroy` destroys only a
workspace-owned dock. `Hide` keeps the item registered and allows it to be
restored with `showDock()`.

## Workspace API

Most mutation methods return success values (or a created item for
`createDock()`) and report failures through `errorOccurred(code, message)`.

| Operation                                  | Purpose                                                       |
|--------------------------------------------|---------------------------------------------------------------|
| `resetLayout()`                            | Put every registered dock into the main container.            |
| `dockAsTab(dockId, targetDockId)`          | Add a dock to the target tab group.                           |
| `splitDock(dockId, targetDockId, side)`    | Place a dock on `left`, `right`, `top`, or `bottom`.          |
| `dockRelative(dockId, targetDockId, zone)` | General tab/split operation.                                  |
| `floatDock(dockId, x, y, width, height)`   | Create a floating container. Geometry arguments are optional. |
| `dockToFirstGroup(dockId)`                 | Return a dock to the first compatible main group.             |
| `activateDock(dockId)`                     | Select a dock in its tab group.                               |
| `focusDock(dockId)`                        | Activate a dock and raise its window if floating.             |
| `selectedDock(containerId)`                | Returns the ID of the dock selected in the container.         |
| `hideDock(dockId)`, `showDock(dockId)`     | Change persistent visibility without unregistering.           |
| `closeDock(dockId)`                        | Apply the dock's close policy.                                |
| `setSplitRatio(splitId, index, ratio)`     | Resize an adjacent child pair programmatically.               |
| `undoLayout()`, `redoLayout()`             | Traverse structural layout history.                           |
| `maximizeFloatingDock(dockId)`             | Maximize the containing floating window.                      |
| `restoreFloatingDock(dockId)`              | Restore that window to its saved normal geometry.             |
| `toggleFloatingDockMaximized(dockId)`      | Toggle the floating window state.                             |

Use `canUndoLayout` and `canRedoLayout` to enable undo/redo actions.

Read-only state and inspection are available without parsing the visual tree:

```javascript
workspace.dockIds()
workspace.dockById("outline")
workspace.isDocked("outline")
workspace.isFloating("outline")
workspace.isHidden("outline")
workspace.isVisible("outline")
workspace.containerOf("outline")
workspace.neighborsOf("outline")

workspace.snapshot       // Current value. Treat as read-only.
workspace.layoutTree     // Main container root
workspace.hiddenDocks
workspace.layoutVersion
```

PySide exposes `QQuickItem.isVisible()` as an inherited method, so Python code
that invokes the dock query through a wrapped workspace can use
`isDockVisible(dockId)`. QML code uses `isVisible(dockId)` directly.

Workspace signals are:

| Signal                 | Parameters                 | Purpose                                                                                    |
|------------------------|----------------------------|--------------------------------------------------------------------------------------------|
| `layoutChanged`        | --                         | A structural layout change occurred.                                                       |
| `splitRatioChanged`    | `splitId`, `splitterIndex` | A split ratio changed.                                                                     |
| `dockActivated`        | `dockId`                   | A dock became active.                                                                      |
| `errorOccurred`        | `code`, `message`          | An operation failed.                                                                       |
| `dockItemsInitialized` | --                         | Fires once after declarative `DockItem`s are registered and the initial layout exists.     |
| `hostClosingRequested` | --                         | The host is closing, after `hostClosing` is set and before floating windows are torn down. |
| `dockAdded`            | `dockId`, `dockItem`       | A dock was registered with the workspace.                                                  |
| `dockAboutToClose`     | `dockId`, `dockItem`       | A dock close was accepted and is about to be applied.                                      |
| `dockClosed`           | `dockId`                   | A dock close completed.                                                                    |
| `dockHidden`           | `dockId`                   | A dock was hidden.                                                                         |
| `dockShown`            | `dockId`                   | A dock was shown.                                                                          |

`dockItemsInitialized()` is the earliest safe point for `restoreLayout()`.

### Error codes

`errorOccurred(code, message)` carries a stable `code` identifier. Message text
may be translated.

| Code                         | Raised when                                                                  |
|------------------------------|------------------------------------------------------------------------------|
| `dock-not-found`             | No dock is registered under the given ID.                                    |
| `target-not-found`           | The target dock of a docking operation is unknown.                           |
| `target-not-visible`         | The target dock exists but is hidden.                                        |
| `dock-not-visible`           | The moved dock is hidden and has no place in the tree.                       |
| `invalid-dock`               | The dock argument is empty or not a string.                                  |
| `duplicate-dock-id`          | A registration reuses an ID that is already taken.                           |
| `invalid-component`          | `createDock()` received something that is not a `Component`.                 |
| `dock-creation-failed`       | The component failed to instantiate a `DockItem`.                            |
| `dock-operation-failed`      | A layout mutation could not be applied to the tree.                          |
| `dock-policy-denied`         | `tabbable`, `allowedZones`, or a similar `DockItem` policy refused the drop. |
| `close-not-allowed`          | The dock is not `closable`.                                                  |
| `float-not-allowed`          | The dock is not `floatable`.                                                 |
| `central-dock-policy`        | The operation would move or remove `centralDockId`.                          |
| `central-dock-not-found`     | `centralDockId` names a dock that is not registered.                         |
| `invalid-zone`               | The zone is not `center`, `left`, `right`, `top`, or `bottom`.               |
| `split-not-found`            | `setSplitRatio()` was given an unknown split ID or index.                    |
| `group-not-found`            | The target tab group no longer exists.                                       |
| `container-not-found`        | The container ID does not name a live container.                             |
| `dock-not-floating`          | A floating-window operation targeted a docked dock.                          |
| `invalid-geometry`           | Floating geometry arguments are not finite numbers.                          |
| `invalid-layout`             | `restoreLayout()` could not parse or sanitize the snapshot.                  |
| `unsupported-layout-version` | The snapshot's `version` is not `layoutVersion`.                             |

## Saving layouts

`saveLayout()` returns JSON. `restoreLayout(stringOrObject)` validates the
version, sanitizes it against currently registered dock IDs, clamps floating
geometry, and returns whether the state was accepted. Unknown saved docks are
discarded. Newly registered docks absent from the snapshot are appended to the
main layout.

The layout has one main container and zero or more floating containers:

```json
{
  "version": 1,
  "containers": [
    {
      "id": "main",
      "kind": "main",
      "root": {
        "kind": "split",
        "id": "split-1",
        "orientation": "horizontal",
        "weights": [0.3, 0.7],
        "children": [
          {"kind": "tabs", "id": "tabs-1", "docks": ["outline"], "active": "outline"},
          {"kind": "tabs", "id": "tabs-2", "docks": ["editor"], "active": "editor"}
        ]
      }
    }
  ],
  "hidden": ["console"]
}
```

Python can validate and inspect saved state without constructing a QML engine:

```python
from quickdock import LAYOUT_VERSION, containers_of, decode_layout, docks_in

layout = decode_layout(saved_json)
assert layout["version"] == LAYOUT_VERSION

for container in containers_of(layout):
    print(container["id"], docks_in(container))

outline_container = containers_of(layout, "outline")
all_docks = docks_in(layout)  # visible tree order, then hidden docks
```

`LAYOUT_VERSION` is read from the same `DockLayout.js` declaration used by QML.
`decode_layout()` checks the JSON, version, and top-level envelope. QML's
`restoreLayout()` remains the authoritative sanitizer. `docks_in()` accepts a
node, container, or complete snapshot and safely skips malformed entries.
`containers_of()` preserves saved container order, skips non-object entries,
and can optionally filter by dock ID.

## Styling

Every workspace owns a `DockStyle`. Start with a preset and override only the
tokens your application needs:

```qml
DockWorkspace {
    style: DockStyle {
        preset: DockStyle.Dark
        colors.accent: "#8b7cff"
        header.height: 36
        splitter.size: 6
        tab.minimumWidth: 96
        tab.maximumWidth: 240
        drag.preview.opacity: 0.68
        split.defaultRatio: 0.35
        fonts.title: Qt.font({ family: "Inter", pixelSize: 13, weight: Font.Medium })
        fonts.glyph: Qt.font({ family: "Material Symbols Outlined", pixelSize: 18 })
    }
}
```

`DockStyle.Dark`, `DockStyle.Light`, and `DockStyle.System` provide complete
palette defaults. A preset can be switched at runtime. The main color tokens
are:

| Token                        | Role                                          |
|------------------------------|-----------------------------------------------|
| `colors.background`          | Workspace background.                         |
| `colors.panel`               | Dock group and floating-window surface.       |
| `colors.header`              | Inactive tab/header background.               |
| `colors.activeHeader`        | Active tab and floating-title-bar background. |
| `colors.text`                | Inactive tab and label text.                  |
| `colors.activeText`          | Active tab and title-bar text.                |
| `colors.border`              | Dock group, tab, and delegate borders.        |
| `colors.splitter`            | Splitter and inactive drop-compass color.     |
| `colors.accent`              | Active indicators and drop-preview borders.   |
| `colors.hover`               | Hovered tab and control background.           |
| `colors.preview`             | Translucent drag/drop preview surface.        |
| `colors.dragPreviewFallback` | Opaque fallback drag-preview surface.         |

Metrics are grouped by purpose:

| Area              | Properties                                                                                                                              |
|-------------------|-----------------------------------------------------------------------------------------------------------------------------------------|
| Headers           | `header.height`, `header.horizontalPadding`, `header.outerMargin`, `header.titleSpacing`, `header.button.spacing`, `header.button.size` |
| Tabs              | `tab.minimumWidth`, `tab.maximumWidth`, `tab.border.width`, `tab.underline.activeHeight`                                                |
| Splits and frames | `splitter.size`, `frame.border.width`, `frame.canvasMargin`, `split.defaultRatio`.                                                      |
| Drag and drop     | `drag.threshold`, `drag.edge.fraction`, `drag.edge.maxBandPixels`, `drag.edge.outerBandPixels`, `drop.indicator.*`, `drop.compass.*`    |
| Floating windows  | `floating.minimumSize`, `floating.defaultGeometry`, `floating.origin.*`, `floating.cascade.offset`, `floating.resizeGrip.*`             |
| Drag preview      | `drag.preview.opacity`, `drag.preview.border.width`, `drag.preview.radius`                                                              |
| Fonts and buttons | `fonts.title`, `fonts.glyph`, `fonts.button`, `fonts.closeButton`, `fonts.placeholder`, `button.radius`                                 |

Glyph tokens (`glyphs.close`, `glyphs.float`, `glyphs.dock`, `glyphs.maximize`,
`glyphs.restore`, and `glyphs.overflow`) can be replaced without replacing a
delegate.

Font tokens use QML's built-in `font` value type and are assigned as complete
font specifications. This exposes every standard font field, including family,
point or pixel size, weight, style, capitalization, and letter spacing.

## Delegates

For structural visual changes, set the `xyzDelegate` properties on
`DockWorkspace`. A delegate instance is loaded under a `Loader`, and its
contract is exposed as properties on `parent`:

| Delegate                     | Loader properties                                                                                   |
|------------------------------|-----------------------------------------------------------------------------------------------------|
| `tabDelegate`                | `workspace`, `dockId`, `dragFrame`, `floatingWindow`, `windowDragEnabled`, `selected`, `compact`    |
| `headerDelegate`             | `workspace`, `dockId`, `dragFrame`, `floatingWindow`, `windowDragEnabled`, `selected`, `compact`    |
| `floatingTitleBarDelegate`   | `workspace`, `style`, `floatingWindow`, `containerId`, `dockId`, `title`, `iconSource`, `maximized` |
| `splitterDelegate`           | `style`, `hovered`, `pressed`, `horizontal`                                                         |
| `dropIndicatorDelegate`      | `workspace`, `style`, `zone`                                                                        |
| `dragPreviewDelegate`        | `workspace`, `style`, `dockId`, `title`, `iconSource`, `snapshotSource`                             |
| `dropCompassDelegate`        | `style`, `zone`                                                                                     |
| `placeholderDelegate`        | `workspace`, `style`                                                                                |
| `floatingDecorationDelegate` | `workspace`, `style`, `containerId`                                                                 |
| `overflowMenuDelegate`       | `workspace`, `style`, `docks`, `activeDock`                                                         |

For example, a custom drag preview can render the captured panel image and add
application-specific decoration:

```qml
DockWorkspace {
    dragPreviewDelegate: Component {
        Rectangle {
            radius: 8
            color: parent.style.colors.panel
            border.color: parent.style.colors.accent
            border.width: 3
            clip: true

            Image {
                anchors.fill: parent
                source: parent.parent.snapshotSource
                fillMode: Image.Stretch
            }
        }
    }
}
```

`headerDelegate`, `tabDelegate`, and `floatingTitleBarDelegate` are complete
replacements, not visual background layers. A custom implementation is
responsible for the activation, drag, close, dock, float, and maximize controls
it wants to expose. Prefer `TapHandler`, `DragHandler`, and `HoverHandler` there
as well so it preserves the built-in mouse, touch, stylus, and
gesture-composition behavior.

### Implementing drag in a custom header or tab

A replacement header drives the workspace through the drag API. Points are
passed in global coordinates. The sequence is `beginDockDrag()`, then
`updateDockDrag()` for every movement, then exactly one of
`finishDockedDrag()` or `cancelDockDrag()`.

```qml
DockWorkspace {
    headerDelegate: Component {
        Rectangle {
            id: header

            // Supplied by the host Loader.
            readonly property var workspace: parent.workspace
            readonly property string dockId: parent.dockId
            readonly property Item dragFrame: parent.dragFrame

            property point frameOffset: Qt.point(0, 0)
            property bool dragging: false

            Text { anchors.centerIn: parent; text: header.workspace.dockById(header.dockId).title }

            TapHandler {
                onTapped: header.workspace.activateDock(header.dockId)
            }

            DragHandler {
                id: drag
                target: null
                dragThreshold: header.workspace.style.drag.threshold

                onActiveChanged: active ? header.begin() : header.finish()
                onCentroidChanged: if (active) header.move()
                onCanceled: {
                    if (header.dragging)
                        header.workspace.cancelDockDrag()
                    header.dragging = false
                }
            }

            function begin() {
                const press = mapToGlobal(drag.centroid.pressPosition)
                frameOffset = dragFrame.mapFromGlobal(press)
                if (!workspace.beginDockDrag(dockId, false))
                    return
                dragging = true
                // Translucent snapshot of the panel that follows the cursor.
                workspace.showDragPreview(
                    dockId, dragFrame,
                    press.x - frameOffset.x, press.y - frameOffset.y,
                    dragFrame.width, dragFrame.height)
                move()
            }

            function move() {
                if (!dragging)
                    return
                const point = mapToGlobal(drag.centroid.position)
                workspace.moveDragPreview(point.x - frameOffset.x, point.y - frameOffset.y)
                // Drives drop-zone hit-testing and the drop indicator.
                workspace.updateDockDrag(dockId, point)
            }

            function finish() {
                if (!dragging)
                    return
                const point = mapToGlobal(drag.centroid.position)
                // Releasing away from every target floats the dock at this rect.
                workspace.finishDockedDrag(
                    dockId, point,
                    point.x - frameOffset.x, point.y - frameOffset.y,
                    dragFrame.width, dragFrame.height)
                dragging = false
            }
        }
    }
}
```

`showDragPreview()` / `moveDragPreview()` / `hideDragPreview()` are optional.
The drop indicator alone gives feedback if they are skipped. `finishDockedDrag()`
and `cancelDockDrag()` both hide the preview.

When the header sits in a floating window, the host Loader also supplies
`floatingWindow` and sets `windowDragEnabled` to `true`. In that case drag the
native window instead of a preview: call `floatingWindow.beginMove(pressPoint)`,
`floatingWindow.continueMove(point)`, and `floatingWindow.endMove()`, still
calling `updateDockDrag()` on each move, and complete with
`finishFloatingDrag(dockId, floatingWindow.containerId, point, x, y, width, height)`.
`floatingWindow.cancelMove()` reverts an aborted move; `floatingWindow.maximized`
and `floatingWindow.toggleMaximized()` back a maximize control. See `DockHeader.qml`
for a reference implementation of both paths.

The container-scoped equivalents used by a floating window's own title bar are
`beginFloatingContainerDrag()`, `updateFloatingContainerDrag()`, and
`finishFloatingContainerDrag()`. They move the whole container rather than one
dock. `canCloseDock()` and `canFloatDock()` let a delegate enable or hide its
close and float buttons, and `floatingWindowForDock()` returns the window
hosting a dock, or `null` when it is docked.
