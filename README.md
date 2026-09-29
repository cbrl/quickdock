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
        moveDock("outline", "editor", "left")
        moveDock("console", "editor", "bottom")
        clearLayoutHistory()
    }
}
```

The workspace starts with every declared dock in one tab group of the main
container. `centralDockId` identifies a permanent main-area dock. It cannot be
closed, hidden, floated, or moved, regardless of its `DockItem` policy properties.

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
adds an existing item. When the target is missing or does not accept the dock,
it goes into the main container instead. An externally owned item is never
destroyed by a close operation unless it was registered with `takeOwnership: true`;
it is hidden instead. A registered dock's `dockId` cannot change.

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

Closing a dock with the `Destroy` policy only closes workspace-owned docks.
A dock closed with the `Hide` policy can be restored with `showDock()`.

## Workspace API

Mutation methods return whether they succeeded (or the created item for
`createDock()`) and report failures through `errorOccurred(code, message)`.

| Operation                                | Purpose                                                              |
|------------------------------------------|----------------------------------------------------------------------|
| `resetLayout()`                          | Put every registered dock into the main container.                   |
| `moveDock(dockId, targetDockId, zone)`   | Dock next to another dock: `center` adds a tab, otherwise it splits. |
| `dockToMain(dockId)`                     | Dock into the main container (first group, or its preferred edge).   |
| `dockContainerToMain(containerId)`       | Dock a floating container back, keeping its splits.                  |
| `floatDock(dockId, x, y, width, height)` | Float a dock. Geometry arguments are optional.                       |
| `hideDock(dockId)`, `showDock(dockId)`   | Change visibility without unregistering.                             |
| `closeDock(dockId)`                      | Apply the dock's close policy.                                       |
| `activateDock(dockId)`                   | Select a dock in its tab group and container.                        |
| `focusDock(dockId)`                      | Activate a dock and raise its window if floating.                    |
| `setSplitRatio(splitId, index, ratio)`   | Resize an adjacent child pair programmatically.                      |
| `saveLayout()`, `restoreLayout(state)`   | Persist and restore the complete layout.                             |
| `undoLayout()`, `redoLayout()`           | Step through layout history.                                         |
| `clearLayoutHistory()`                   | Forget history, e.g. after restoring a layout at startup.            |

Undo history only records structural changes. This excludes tab selections,
resizes, or window movements. Undo and redo never bring back a dock that has
been destroyed. A dock created after the restored point comes back hidden. Use
`canUndoLayout` and `canRedoLayout` to enable undo/redo actions.

Queries:

```javascript
workspace.dockIds()
workspace.dockById("outline")
workspace.dockState("outline")      // "docked", "floating", "hidden", or "" if unknown
workspace.containerOf("outline")    // "main" or a floating container id
workspace.neighborsOf("outline")
workspace.selectedDock("main")      // the container's most recently activated dock
workspace.canCloseDock("outline")
workspace.canFloatDock("outline")
workspace.floatingWindowForDock("outline")   // the Window, or null when docked

workspace.snapshot       // the current layout, as saved
workspace.hiddenDocks
workspace.layoutVersion
workspace.dragging
```

A floating window returned by `floatingWindowForDock()` has `maximized`,
`showMaximized()`, `showNormal()`, and `toggleMaximized()`.

### Workspace signals

| Signal              | Parameters                 | Purpose                                                              |
|---------------------|----------------------------|----------------------------------------------------------------------|
| `initialized`       | --                         | The declared `DockItem`s are registered and the first layout exists. |
| `layoutChanged`     | --                         | A structural change, including undo, redo, and restore.              |
| `splitRatioChanged` | `splitId`, `splitterIndex` | A split ratio changed.                                               |
| `dockActivated`     | `dockId`                   | A dock became the selected dock of its container.                    |
| `dockAdded`         | `dockId`, `dockItem`       | A dock was registered with the workspace.                            |
| `dockShown`         | `dockId`                   | A hidden dock became visible.                                        |
| `dockHidden`        | `dockId`                   | A dock was hidden.                                                   |
| `dockAboutToClose`  | `dockId`, `dockItem`       | A close was accepted and is about to be applied.                     |
| `dockClosed`        | `dockId`                   | A close completed.                                                   |
| `errorOccurred`     | `code`, `message`          | An operation failed.                                                 |

`dockActivated`, `dockShown`, and `dockHidden` come from comparing layouts, so
undo, redo, and restore emit them too. Activating the dock that is already
selected emits nothing.

### Error codes

`errorOccurred(code, message)` carries a stable `code` identifier. Message text
may be translated.

| Code                         | Raised when                                                                  |
|------------------------------|------------------------------------------------------------------------------|
| `dock-not-found`             | No dock is registered under the given ID.                                    |
| `target-not-found`           | The target dock of a docking operation is unknown.                           |
| `target-not-visible`         | The target dock exists but is hidden.                                        |
| `dock-not-visible`           | The dock is hidden, so it cannot be activated.                               |
| `invalid-dock`               | A registered item has no `dockId`.                                           |
| `duplicate-dock-id`          | A registration reuses an ID that is already taken.                           |
| `dock-id-changed`            | A registered dock's `dockId` was changed (the change is reverted).           |
| `invalid-component`          | `createDock()` received something that is not a `Component`.                 |
| `dock-creation-failed`       | The component failed to instantiate a `DockItem`.                            |
| `dock-operation-failed`      | A layout change could not be applied to the tree.                            |
| `dock-policy-denied`         | `tabbable`, `allowedZones`, or a similar `DockItem` policy refused the drop. |
| `no-placement`               | The dock allows no zone it could be placed in.                               |
| `close-not-allowed`          | The dock is not `closable`.                                                  |
| `float-not-allowed`          | The dock is not `floatable`.                                                 |
| `central-dock-policy`        | The operation would close, hide, float, or move `centralDockId`.             |
| `central-dock-not-found`     | `centralDockId` names a dock that is not registered.                         |
| `invalid-zone`               | The zone is not `center`, `left`, `right`, `top`, or `bottom`.               |
| `split-not-found`            | `setSplitRatio()` was given an unknown split ID.                             |
| `group-not-found`            | The target tab group no longer exists.                                       |
| `container-not-found`        | The container ID does not name a live container.                             |
| `invalid-layout`             | `restoreLayout()` could not parse the layout.                                |
| `unsupported-layout-version` | The layout's `version` is not `layoutVersion`.                               |

## Saving layouts

Use `saveLayout()` for a JSON representation of the current layout.
`restoreLayout(stringOrObject)` loads the serialized layout and returns whether
it was accepted. When restoring a layout, unknown docks are dropped and existing
docks the layout does not specify are added to the main container. Floating
windows will go on their saved screen if it still exists, or the host's screen
otherwise. A restore counts as an undo step.

The layout has one main container and zero or more floating containers. Each
container's `selected` is its most recently activated dock:

```json
{
  "version": 2,
  "containers": [
    {
      "id": "main",
      "kind": "main",
      "root": {
        "kind": "split",
        "id": "split_1",
        "orientation": "horizontal",
        "weights": [0.3, 0.7],
        "children": [
          {"kind": "tabs", "id": "tabs_1", "docks": ["outline"], "active": "outline"},
          {"kind": "tabs", "id": "tabs_2", "docks": ["editor"], "active": "editor"}
        ]
      },
      "selected": "editor"
    },
    {
      "id": "float_3",
      "kind": "floating",
      "geometry": {"x": 120, "y": 80, "width": 480, "height": 320},
      "screen": "DP-1",
      "root": {"kind": "tabs", "id": "tabs_4", "docks": ["search"], "active": "search"},
      "selected": "search"
    }
  ],
  "hidden": ["console"]
}
```

Python can validate and inspect saved state without constructing a QML engine:

```python
from quickdock import containers_of, decode_layout, docks_in

layout = decode_layout(saved_json)

for container in containers_of(layout):
    print(container["id"], docks_in(container))

outline_container = containers_of(layout, "outline")
all_docks = docks_in(layout)  # visible tree order, then hidden docks
```

`decode_layout()` validates the layout version and top-level format. The rest
of the sanitization is performed in QML's `restoreLayout()`. `docks_in()`
accepts a node, container, or complete snapshot and safely skips malformed
entries. `containers_of()` preserves saved container order, skips non-object
entries, and can optionally filter by dock ID.

## Styling

Every workspace owns a `DockStyle` with visual tokens in one level of groups.
Start with a preset and override only what your application needs:

```qml
DockWorkspace {
    style: DockStyle {
        preset: DockStyle.Dark
        colors.accent: "#8b7cff"
        header.height: 36
        frame.splitterSize: 6
        tab.minimumWidth: 96
        dragPreview.opacity: 0.68
        fonts.title: Qt.font({ family: "Inter", pixelSize: 13, weight: Font.Medium })
        fonts.glyph: Qt.font({ family: "Material Symbols Outlined", pixelSize: 18 })
    }
}
```

`DockStyle.Dark`, `DockStyle.Light`, and `DockStyle.System` provide complete
palettes, and the preset can be switched at runtime.

| Group         | Tokens                                                                                                                                             |
|---------------|----------------------------------------------------------------------------------------------------------------------------------------------------|
| `colors`      | `panel`, `header`, `activeHeader`, `text`, `activeText`, `border`, `splitter`, `accent`, `hover`, `preview`, `dragPreviewFallback`, `placeholder` |
| `header`      | `height`, `horizontalPadding`, `outerMargin`, `titleSpacing`, `buttonSize`, `buttonSpacing`, `buttonRadius`                                        |
| `tab`         | `minimumWidth`, `maximumWidth`, `borderWidth`, `borderColor`, `activeBorderColor`, `underlineHeight`, `activeUnderlineHeight`                      |
| `frame`       | `borderWidth`, `radius` (rounds the main container), `splitterSize`                                                                                |
| `drop`        | `indicatorBorderWidth`, `indicatorRadius`, `tabMarkerWidth`, `tabMarkerMargin`, `compassSize`, `compassCellSize`                                   |
| `dragPreview` | `opacity`, `borderWidth`, `radius`                                                                                                                 |
| `fonts`       | `title`, `glyph`, `button`, `closeButton`, `placeholder`                                                                                           |
| `glyphs`      | `close`, `float`, `dock`, `maximize`, `restore`, `overflow`                                                                                        |
| `floating`    | `gripSize` (the invisible resize border of floating windows)                                                                                       |

Font tokens use QML's `font` value type and are assigned as complete font
specifications.

## Behavior

Interaction settings are on `DockWorkspace.behavior`:

```qml
DockWorkspace {
    behavior.dragThreshold: 12
    behavior.defaultSplitRatio: 0.35
    behavior.dropCompassEnabled: false
}
```

| Setting                                   | Purpose                                                                   |
|-------------------------------------------|---------------------------------------------------------------------------|
| `dragThreshold`                           | Pointer travel before a press on a header becomes a drag.                 |
| `edgeFraction`, `edgeMaxBand`             | A group's edge drop bands: a fraction of each side, capped in pixels.     |
| `outerEdgeBand`                           | Width in pixels of a container's outer edge band.                         |
| `defaultSplitRatio`                       | Share of the space a dock gets when docked by splitting.                  |
| `dropCompassEnabled`                      | Whether the drop compass is shown over a target.                          |
| `floatingMinimumSize`                     | Smallest floating window.                                                 |
| `floatingDefaultSize`                     | Floating size when neither the caller nor the layout gives one.           |
| `floatingOrigin`, `floatingCascadeOffset` | Where new floating windows appear: a fraction of the workspace, cascaded. |

## Delegates

Every visual part can be replaced through a `xyzDelegate` property on
`DockWorkspace`. A delegate declares the values it uses as `required property`,
the same way a `ListView` delegate declares model roles. They are set when the
delegate is created and kept up to date. Values a delegate does not declare are
not passed to it, so it declares only what it uses. `workspace` and `style` are
offered to every delegate.

| Delegate                      | Default             | Values                                                                                       |
|-------------------------------|---------------------|----------------------------------------------------------------------------------------------|
| `headerDelegate`              | `DockHeader`        | `dock`, `dockId`, `selected`, `compact`, `floatingWindow`, `moveWindow`                      |
| `tabDelegate`                 | `DockHeader`        | Same as `headerDelegate`, with `compact` set. A tab's width comes from its `implicitWidth`.  |
| `titleBarDelegate`            | `DockTitleBar`      | `floatingWindow`, `containerId`, `dock` (the selected dock), `maximized`                     |
| `containerDelegate`           | `DockContainerView` | `containerId`, `container`, `floatingWindow`, `renderReady`                                  |
| `containerBackgroundDelegate` | none                | `containerId`                                                                                |
| `containerDecorationDelegate` | frame border        | `containerId`                                                                                |
| `placeholderDelegate`         | "Drag a dock here"  | `containerId`                                                                                |
| `splitterDelegate`            | bar                 | `hovered`, `pressed`, `horizontal`                                                           |
| `dropIndicatorDelegate`       | rectangle           | `zone` (`tab` for the marker between tabs)                                                   |
| `dropCompassDelegate`         | `DockDropCompass`   | `zone`                                                                                       |
| `dragPreviewDelegate`         | captured image      | `dock`, `dockId`, `snapshotSource`                                                           |
| `overflowMenuDelegate`        | menu button         | `docks`, `activeDock`                                                                        |

`DockHeader`, `DockTitleBar`, `DockDropCompass`, and `DockContainerView` are
public, so a delegate can extend a built-in instead of starting over:

```qml
DockWorkspace {
    tabDelegate: Component {
        DockHeader {
            color: selected ? "#3b3f58" : "transparent"
        }
    }

    dragPreviewDelegate: Component {
        Rectangle {
            id: preview
            required property DockStyle style
            required property url snapshotSource
            radius: 8
            color: style.colors.panel
            border.color: style.colors.accent
            border.width: 3
            clip: true

            Image { anchors.fill: parent; source: preview.snapshotSource }
        }
    }
}
```

A delegate whose root is a `Text` cannot declare `style`, which `Text` already
has. Put the `Text` inside an `Item`.

A custom `containerDelegate` places a `DockContainerView` next to its own
content and passes its values through. The window around a floating container
uses the delegate's `minimumSize` and `maximumSize` when it declares them:

```qml
containerDelegate: Component {
    Item {
        id: frame
        required property DockWorkspace workspace
        required property string containerId
        required property var container
        required property var floatingWindow
        required property bool renderReady

        DockContainerView {
            anchors { fill: parent; leftMargin: 40 }
            workspace: frame.workspace
            containerId: frame.containerId
            container: frame.container
            floatingWindow: frame.floatingWindow
            renderReady: frame.renderReady
        }
    }
}
```

### Dragging from a custom header, tab, or title bar

Put a `DockDragArea` over the part that should drag. It handles the gesture,
the preview, drop targeting, activation on tap, and floating on release:

```qml
headerDelegate: Component {
    Rectangle {
        id: header
        required property DockWorkspace workspace
        required property DockItem dock
        required property string dockId

        Text { anchors.centerIn: parent; text: header.dock ? header.dock.title : "" }

        DockDragArea {
            anchors.fill: parent
            workspace: header.workspace
            dockId: header.dockId
        }
    }
}
```

With `containerId` set as well, a drag moves that floating container's window
instead, docking the whole container when released over a target, and a
double tap maximizes the window. The built-in header does this when
`moveWindow` is true, which is when it is the only chrome of a floating
window:

```qml
DockDragArea {
    workspace: header.workspace
    dockId: header.dockId
    containerId: header.moveWindow ? header.floatingWindow.containerId : ""
}
```

Code that drives its own gestures can use the same session directly:
`beginDrag({dockId, containerId, pressPoint, source})`, then
`moveDrag(globalPoint)` for every movement (it returns the drop target or
`null`), then `endDrag(globalPoint)` or `cancelDrag()`. Points are global.

## Embedded resources

QML and JavaScript files are loaded directly from the package by default.
Executable builds can compile any of the `resources.qrc` manifests to a sibling
`resources_rc.py` module with `pyside6-rcc`. The owning application imports that
module when it is present and switches to `qrc:/` URLs automatically. Otherwise
it retains the package-file fallback. Generated `resources_rc.py` modules are
ignored by Git and are not required when installing or running the Python package.
A stale `resources_rc.py` shadows the package files, so regenerate it after
changing the QML:

```bash
pyside6-rcc src/quickdock/resources.qrc -o src/quickdock/resources_rc.py
```
