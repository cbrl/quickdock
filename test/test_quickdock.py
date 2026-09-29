from __future__ import annotations

import json
import os
import re
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path
from typing import NamedTuple

import pytest


os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtCore import (  # noqa: E402
    QCoreApplication,
    QEvent,
    QObject,
    QPoint,
    QPointF,
    QSizeF,
    Qt,
    QUrl,
    qInstallMessageHandler,
)
from PySide6.QtGui import QGuiApplication, QWindow  # noqa: E402
from PySide6.QtQml import (  # noqa: E402
    QJSEngine,
    QQmlComponent,
    QQmlEngine,
    QQmlExpression,
)
from PySide6.QtQuick import QQuickItem  # noqa: E402
from PySide6.QtTest import QTest  # noqa: E402
from shiboken6 import getCppPointer  # noqa: E402

from quickdock import install_docking  # noqa: E402
from quickdock.layout import (  # noqa: E402
    LAYOUT_VERSION,
    containers_of,
    decode_layout,
    docks_in,
)


TEST_DATA = Path(__file__).parent / "data"
PACKAGE = Path(__file__).parents[1] / "src" / "quickdock"
LIBRARY = PACKAGE / "qml" / "QuickDock"

DOCK_IDS = ("scene", "outline", "inspector", "console")

# Four declarative docks in a Window, all in one tab group. Tests that need
# splits build them explicitly.
WORKSPACE_QML = b"""
import QtQuick
import QtQuick.Window
import QuickDock 1.0

Window {
    width: 900
    height: 600
    visible: true

    DockWorkspace {
        id: workspace
        objectName: "testWorkspace"
        anchors.fill: parent

        DockItem { dockId: "scene"; title: "Scene"; Rectangle { anchors.fill: parent } }
        DockItem { dockId: "outline"; title: "Outline"; Rectangle { anchors.fill: parent } }
        DockItem { dockId: "inspector"; title: "Inspector"; Rectangle { anchors.fill: parent } }
        DockItem { dockId: "console"; title: "Console"; Rectangle { anchors.fill: parent } }
    }

    Component.onCompleted: workspace.resetLayout()
}
"""

# Six docks, for the saved-layout fixture in test/data.
GOLDEN_QML = b"""
import QtQuick
import QtQuick.Window
import QuickDock 1.0

Window {
    width: 900
    height: 600
    visible: true

    DockWorkspace {
        objectName: "goldenWorkspace"
        anchors.fill: parent

        DockItem { dockId: "scene" }
        DockItem { dockId: "outline" }
        DockItem { dockId: "inspector" }
        DockItem { dockId: "console" }
        DockItem { dockId: "timeline" }
        DockItem { dockId: "log" }
    }
}
"""

CUSTOM_DELEGATES_QML = b"""
import QtQuick
import QuickDock 1.0

DockWorkspace {
    width: 900
    height: 600

    titleBarDelegate: Component {
        Rectangle {
            required property string containerId
            required property DockItem dock
            required property bool maximized
            required property var floatingWindow
            required property DockStyle style
            objectName: "customFloatingTitle_" + containerId
            color: style.colors.accent
            property string receivedDockId: dock ? dock.dockId : ""
            property string receivedTitle: dock ? dock.title : ""
            property bool receivedMaximized: maximized
            property var receivedWindow: floatingWindow
        }
    }

    // Declares only some of the offered values and sizes the tab through
    // its implicit width.
    tabDelegate: Component {
        Rectangle {
            required property string dockId
            required property bool selected
            objectName: "customTab_" + dockId
            implicitWidth: dockId === "scene" ? 190 : 130
            color: selected ? "red" : "gray"
        }
    }

    // A Text root has a `style` property of its own, which must not receive
    // the workspace style it did not ask for.
    placeholderDelegate: Component {
        Text {
            objectName: "customPlaceholder"
            text: "Nothing here"
        }
    }

    DockItem { dockId: "scene"; title: "Scene"; Rectangle { anchors.fill: parent } }
    DockItem { dockId: "inspector"; title: "Inspector"; Rectangle { anchors.fill: parent } }
}
"""

# The delegate examples from the README.
README_DELEGATES_QML = b"""
import QtQuick
import QtQuick.Window
import QuickDock 1.0

Window {
    width: 900
    height: 600
    visible: true

    DockWorkspace {
        objectName: "readmeWorkspace"
        anchors.fill: parent

        tabDelegate: Component {
            DockHeader {
                color: selected ? "#3b3f58" : "transparent"
            }
        }

        headerDelegate: Component {
            Rectangle {
                id: header
                required property DockWorkspace workspace
                required property DockItem dock
                required property string dockId
                objectName: "readmeHeader_" + dockId

                Text { anchors.centerIn: parent; text: header.dock ? header.dock.title : "" }

                DockDragArea {
                    anchors.fill: parent
                    workspace: header.workspace
                    dockId: header.dockId
                }
            }
        }

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

        DockItem { dockId: "scene"; title: "Scene" }
        DockItem { dockId: "outline"; title: "Outline" }
    }
}
"""

DYNAMIC_DOCK_QML = b"""
import QtQuick
import QtQuick.Window
import QuickDock 1.0

Window {
    width: 640
    height: 480
    visible: true

    DockWorkspace {
        id: workspace
        objectName: "dynamicWorkspace"
        anchors.fill: parent
    }

    Component {
        id: panelFactory
        DockItem {
            dockId: "dynamic-panel"
            title: "Dynamic panel"
            Rectangle { anchors.fill: parent }
        }
    }

    Component.onCompleted: workspace.createDock(panelFactory)
}
"""

# A windowIntegrationDelegate standing in for a native helper: it counts the
# maximize requests it gets, and handles them when told to.
WINDOW_INTEGRATION_QML = b"""
import QtQuick
import QtQuick.Window
import QuickDock 1.0

Window {
    width: 900
    height: 600
    visible: true

    DockWorkspace {
        objectName: "integrationWorkspace"
        anchors.fill: parent

        windowIntegrationDelegate: Component {
            Item {
                id: integration
                required property var floatingWindow
                required property string containerId
                property bool handlesMaximize: false
                property int maximizeRequests: 0
                objectName: "windowIntegration_" + containerId

                function toggleMaximized() {
                    ++integration.maximizeRequests
                    return integration.handlesMaximize
                }
            }
        }

        DockItem { dockId: "scene"; title: "Scene"; Rectangle { anchors.fill: parent } }
        DockItem { dockId: "outline"; title: "Outline"; Rectangle { anchors.fill: parent } }
    }
}
"""


# --------------------------------------------------------------------------
# Fixtures and helpers
# --------------------------------------------------------------------------


class Hosted(NamedTuple):
    window: QWindow
    workspace: QObject


@pytest.fixture(scope="session")
def qgui_app():
    app = QGuiApplication.instance() or QGuiApplication([])
    QCoreApplication.setOrganizationName("QuickDock-Test")
    QCoreApplication.setApplicationName("QuickDock-Tests")
    # Tests close host windows on purpose. That must not end the event loop.
    app.setQuitOnLastWindowClosed(False)
    return app


@pytest.fixture()
def pump(qgui_app):
    """Drive the event loop. Queued layout work settles within a few passes."""

    def _pump(times: int = 3):
        for _ in range(times):
            qgui_app.processEvents()

    return _pump


@pytest.fixture()
def load(qgui_app, pump):
    """Instantiate QML source against a private engine, torn down after."""

    created: list[tuple[QQmlEngine, QQmlComponent, QObject]] = []

    def _load(source: bytes, name: str = "Test.qml") -> QObject:
        engine = QQmlEngine()
        install_docking(engine)
        component = QQmlComponent(engine)
        component.setData(source, QUrl.fromLocalFile(str((Path.cwd() / name).resolve())))
        assert component.isReady(), [error.toString() for error in component.errors()]
        root = component.create()
        assert root is not None, [error.toString() for error in component.errors()]
        # create() leaves a parentless root under JavaScript ownership, which
        # the engine is free to collect mid-test.
        QQmlEngine.setObjectOwnership(root, QQmlEngine.ObjectOwnership.CppOwnership)
        created.append((engine, component, root))
        pump(1)
        return root

    yield _load

    for engine, _component, root in reversed(created):
        if isinstance(root, QWindow):
            root.close()
        root.deleteLater()
        engine.deleteLater()
    pump()


@pytest.fixture()
def hosted(load) -> Hosted:
    """A workspace and the window hosting it, for tests that deliver input."""

    window = load(WORKSPACE_QML, "WorkspaceTest.qml")
    return Hosted(window, window.findChild(QObject, "testWorkspace"))


@pytest.fixture()
def workspace(hosted) -> QObject:
    return hosted.workspace


@contextmanager
def qml_messages() -> Iterator[list[str]]:
    """Capture QML engine output so tests can assert it stays clean."""

    captured: list[str] = []
    previous = qInstallMessageHandler(
        lambda _kind, _context, message: captured.append(message)
    )
    try:
        yield captured
    finally:
        qInstallMessageHandler(previous)


def warnings_in(messages: list[str]) -> list[str]:
    return [
        message
        for message in messages
        if "TypeError" in message or "Binding loop" in message or "ReferenceError" in message
    ]


def evaluate(workspace, expression: str):
    """Evaluate a QML expression in the workspace's own context."""

    evaluated = QQmlExpression(QQmlEngine.contextForObject(workspace), workspace, expression)
    value, _undefined = evaluated.evaluate()
    assert not evaluated.hasError(), evaluated.error().toString()
    return value


def token(workspace, path: str):
    """A style token by its path, e.g. ``token(ws, "header.height")``.

    Expected values derive from these rather than being hard-coded, so
    retuning the theme cannot silently invalidate a test.
    """

    return evaluate(workspace, f"style.{path}")


def setting(workspace, name: str):
    return evaluate(workspace, f"behavior.{name}")


def descendants(root):
    """Yield every visual item under an Item or Window, depth first.

    Repeater delegates are not reachable through ``findChild()`` here, so
    objectName lookups must walk ``childItems()``.
    """

    pending = [root.contentItem() if isinstance(root, QWindow) else root]
    while pending:
        item = pending.pop()
        yield item
        pending.extend(item.childItems())


def find_item(root, object_name: str, *, visible: bool | None = None) -> QQuickItem | None:
    matches = [item for item in descendants(root) if item.objectName() == object_name]
    if visible is not None:
        matches = [item for item in matches if item.isVisible() == visible]
    return matches[0] if matches else None


def find_items(root, prefix: str) -> list[QQuickItem]:
    return [item for item in descendants(root) if item.objectName().startswith(prefix)]


def saved(workspace) -> dict:
    return decode_layout(workspace.saveLayout())


def main_container(state: dict) -> dict:
    return next(c for c in state["containers"] if c["kind"] == "main")


def floating_containers(state: dict) -> list[dict]:
    return [c for c in state["containers"] if c["kind"] == "floating"]


def collect_docks(node: dict | None) -> list[str]:
    if node is None:
        return []
    if node["kind"] == "tabs":
        return list(node["docks"])
    return [dock for child in node["children"] for dock in collect_docks(child)]


def without_ids(value):
    """A layout with node and container ids removed, for comparisons."""

    if isinstance(value, dict):
        return {key: without_ids(item) for key, item in value.items() if key != "id"}
    if isinstance(value, list):
        return [without_ids(item) for item in value]
    return value


def qml_value(value):
    return value.toVariant() if hasattr(value, "toVariant") else value


def same_object(first: QObject | None, second: QObject | None) -> bool:
    return first is not None and second is not None and getCppPointer(first) == getCppPointer(second)


def center_of(item: QQuickItem) -> QPoint:
    return item.mapToScene(QPointF(item.width() / 2, item.height() / 2)).toPoint()


def workspace_center(workspace) -> QPointF:
    return workspace.mapToGlobal(QPointF(workspace.width() / 2, workspace.height() / 2))


def tab_drop_point(workspace, index: int) -> QPointF:
    """Global point just inside the left edge of the rendered tab at ``index``."""

    docks = main_container(saved(workspace))["root"]["docks"]
    tab = find_item(workspace, f"dockDragArea_{docks[index]}", visible=True)
    assert tab is not None
    return tab.mapToGlobal(QPointF(1, tab.height() / 2))


def build_split_layout(workspace):
    """`scene` beside a tabbed `inspector`/`outline`, with `console` below.

    Has both a horizontal and a vertical splitter, and an inactive tab.
    """

    assert workspace.moveDock("inspector", "scene", "right")
    assert workspace.moveDock("console", "scene", "bottom")
    assert workspace.moveDock("outline", "inspector", "center")
    assert workspace.activateDock("inspector")


def floating_minimum(workspace, dock_id: str) -> tuple[float, float]:
    """The size a single-dock floating window is clamped up to."""

    floor = setting(workspace, "floatingMinimumSize")
    item = workspace.dockById(dock_id).property("minimumSize")
    return (
        max(floor.width(), item.width()),
        max(floor.height(), item.height() + token(workspace, "header.height")),
    )


def drag(workspace, point, **options):
    """Begin a drag pressed at ``point`` and move it there."""

    assert workspace.beginDrag({"pressPoint": point, **options})
    return qml_value(workspace.moveDrag(point))


# --------------------------------------------------------------------------
# Layout envelope (Python) and packaging
# --------------------------------------------------------------------------


def test_decode_layout_rejects_unreadable_envelopes():
    with pytest.raises(ValueError, match="unsupported docking layout version"):
        decode_layout(json.dumps({"version": LAYOUT_VERSION - 1, "containers": []}))
    with pytest.raises(ValueError, match="containers"):
        decode_layout(json.dumps({"version": LAYOUT_VERSION}))
    with pytest.raises(ValueError, match="JSON"):
        decode_layout("{")


def test_layout_inspection_walks_containers_and_ignores_malformed_nodes():
    tabs = lambda ident, docks: {"kind": "tabs", "id": ident, "docks": docks}  # noqa: E731
    state = decode_layout(
        json.dumps(
            {
                "version": LAYOUT_VERSION,
                "containers": [
                    None,  # dropped
                    {
                        "id": "main",
                        "kind": "main",
                        "root": {
                            "kind": "split",
                            "id": "split-1",
                            "children": [None, tabs("t1", ["scene", None, 42, "outline"])],
                        },
                    },
                    {"id": "float-1", "kind": "floating", "root": tabs("t2", ["console"])},
                ],
                "hidden": ["timeline", None],
            }
        )
    )

    containers = containers_of(state)
    assert [c["id"] for c in containers] == ["main", "float-1"]
    assert docks_in(containers[0]) == ("scene", "outline")
    # Snapshot order is visible docks in tree order, then hidden ones.
    assert docks_in(state) == ("scene", "outline", "console", "timeline")
    assert containers_of(state, "console") == (containers[1],)
    assert containers_of(state, "timeline") == ()


def test_python_layout_version_matches_the_qml_library(layout_js):
    assert layout_js("return DockLayout.layoutVersion") == LAYOUT_VERSION


def test_resources_qrc_lists_every_library_file():
    qrc = (PACKAGE / "resources.qrc").read_text(encoding="utf-8")
    listed = set(re.findall(r"<file>(.+?)</file>", qrc))
    on_disk = {
        path.relative_to(PACKAGE).as_posix()
        for path in (PACKAGE / "qml").rglob("*")
        if path.is_file() and (path.suffix in (".qml", ".js") or path.name == "qmldir")
    }
    assert listed == on_disk


def test_qmldir_lists_every_qml_file():
    qmldir = (LIBRARY / "qmldir").read_text(encoding="utf-8")
    listed = set(re.findall(r"(\S+\.qml)$", qmldir, re.MULTILINE))
    on_disk = {path.relative_to(LIBRARY).as_posix() for path in LIBRARY.rglob("*.qml")}
    assert listed == on_disk


# --------------------------------------------------------------------------
# Pure layout code (DockLayout.js, DockOps.js)
# --------------------------------------------------------------------------


JS_PRELUDE = """
const left = {kind: "tabs", id: "left", docks: ["a", "b"], active: "a"}
const right = {kind: "tabs", id: "right", docks: ["c"], active: "c"}
const original = {
    kind: "split", id: "root", orientation: "horizontal",
    weights: [0.5, 0.5], children: [left, right]
}
const allZones = ["center", "left", "right", "top", "bottom"]
function context(overrides) {
    let next = 0
    const docks = {}
    for (const id of ["a", "b", "c", "d", "e"])
        docks[id] = {tabbable: true, floatable: true, closable: true, allowedZones: allZones}
    return Object.assign({
        newId: prefix => prefix + "_" + (++next),
        dock: id => docks[id] || null,
        centralDockId: "",
        defaultRatio: 0.5,
        fitFloating: (geometry, root, screen) => ({geometry: geometry, screen: screen})
    }, overrides || {})
}
function snapshotOf(mainRoot, floating, hidden) {
    return DockLayout.snapshotWith(
        [DockTypes.mainContainer(mainRoot, "")].concat(floating || []), hidden || [])
}
function mainRoot(snapshot) {
    return DockLayout.mainContainer(snapshot.containers).root
}
"""


def _js_module(engine: QJSEngine, name: str, path: Path):
    source = path.read_text(encoding="utf-8")
    source = re.sub(r"^\.(pragma|import) .*$", "", source, flags=re.MULTILINE)
    exports = re.findall(r"^(?:function|var) (\w+)", source, flags=re.MULTILINE)
    result = engine.evaluate(
        f"var {name} = (function() {{\n{source}\nreturn {{{', '.join(exports)}}}\n}})()"
    )
    assert not result.isError(), result.toString()


@pytest.fixture(scope="module")
def layout_js(qgui_app):
    """Evaluate the library's JavaScript in a bare engine; return an eval helper."""

    engine = QJSEngine()
    _js_module(engine, "DockTypes", LIBRARY / "DockTypes.js")
    _js_module(engine, "DockLayout", LIBRARY / "DockLayout.js")
    _js_module(engine, "DockOps", LIBRARY / "DockOps.js")

    def evaluate_js(body: str):
        result = engine.evaluate(f"JSON.stringify((function() {{ {JS_PRELUDE}\n{body} }})())")
        assert not result.isError(), result.toString()
        return json.loads(result.toString())

    return evaluate_js


def test_layout_edits_copy_the_spine_and_share_untouched_subtrees(layout_js):
    assert layout_js(
        """
        const resized = DockLayout.withSplitRatio(original, "root", 0, 0.7)
        const removed = DockLayout.withDockRemoved(original, "b")
        return {
            copiedRoot: resized !== original,
            sharedChildren: resized.children === original.children,
            sharedLeft: resized.children[0] === left,
            sharedRightAfterRemoval: removed.children[1] === right,
            originalWeight: original.weights[0],
            originalLeftDockCount: left.docks.length
        }
        """
    ) == {
        "copiedRoot": True,
        "sharedChildren": True,
        "sharedLeft": True,
        "sharedRightAfterRemoval": True,
        "originalWeight": 0.5,
        "originalLeftDockCount": 2,
    }


def test_layout_insertion_normalizes_and_places_nodes(layout_js):
    values = layout_js(
        """
        const nested = DockLayout.normalize({
            kind: "split", id: "outer", orientation: "horizontal",
            weights: [1, 1], children: [original, right]
        })
        const single = {kind: "tabs", id: "new", docks: ["d"], active: "d"}
        const inserted = {kind: "tabs", id: "inserted", docks: ["d", "e"], active: "e"}
        const atRoot = DockLayout.withNodeAtRoot(original, single, "left", "new-root", 0.3)
        const merged = DockLayout.withNodeInserted(original, "left", inserted, "center", "unused", 1, 0.3)
        return {
            // A same-orientation child split is flattened into its parent.
            flattenedChildren: nested.children.length,
            // A node inserted along the root's edge takes the given share.
            rootWeight: atRoot.weights[0],
            rootFirst: atRoot.children[0].docks[0],
            // A center drop merges the incoming tabs at the given index and
            // adopts the incoming active dock.
            mergedDocks: merged.children[0].docks,
            mergedActive: merged.children[0].active,
            // A top drop at the root produces a vertical split.
            topOrientation: DockLayout.withNodeAtRoot(original, inserted, "top", "top-root", 0.3).orientation
        }
        """
    )
    assert values.pop("rootWeight") == pytest.approx(0.3)
    assert values == {
        "flattenedChildren": 3,
        "rootFirst": "d",
        "mergedDocks": ["a", "d", "e", "b"],
        "mergedActive": "e",
        "topOrientation": "vertical",
    }


def test_size_limits_account_for_headers_and_splitters(layout_js):
    header, splitter, available = 30, 5, 300
    minimums = {"a": (100, 50), "b": (120, 40), "c": (80, 70)}
    values = layout_js(
        f"""
        const minimums = {json.dumps({k: {"width": w, "height": h} for k, (w, h) in minimums.items()})}
        const limitsOf = id => ({{minimum: minimums[id], maximum: {{width: 500, height: 400}}}})
        const metrics = {{header: {header}, splitter: {splitter}}}
        return {{
            limits: DockLayout.sizeLimitsOf(original, limitsOf, metrics),
            constrained: DockLayout.constrainedLengths(original, {available}, limitsOf, metrics)
        }}
        """
    )

    # `original` is a horizontal split of tabs(a, b) and tabs(c): tabbed docks
    # overlap, split siblings add up, and every group pays for one header.
    def tabbed(*docks):
        return (
            max(minimums[d][0] for d in docks),
            max(minimums[d][1] for d in docks) + header,
        )

    left, right = tabbed("a", "b"), tabbed("c")
    assert values["limits"] == {
        "minimum": {"width": left[0] + right[0] + splitter, "height": max(left[1], right[1])},
        "maximum": {"width": 500 + 500 + splitter, "height": 400 + header},
    }
    # Equal weights, and the available width clears both minimums.
    assert values["constrained"] == [available / 2, available / 2]


def test_geometry_places_groups_and_splitters_and_follows_a_live_drag(layout_js):
    values = layout_js(
        """
        const metrics = {header: 30, splitter: 5}
        const layout = DockLayout.computeGeometry(original, 405, 200, () => null, metrics, null)
        const dragged = DockLayout.computeGeometry(original, 405, 200, () => null, metrics,
                                                   {splitId: "root", lengths: [100, 300]})
        const strip = entry => ({x: entry.x, y: entry.y, width: entry.width, height: entry.height})
        return {
            left: strip(layout.groups.left),
            right: strip(layout.groups.right),
            splitter: strip(layout.splitters["root:0"]),
            draggedRight: strip(dragged.groups.right),
            // A drag keeps each pane above its minimum.
            clamped: DockLayout.draggedLengths([200, 200], [150, 120], 0, -100)
        }
        """
    )
    assert values == {
        "left": {"x": 0, "y": 0, "width": 200, "height": 200},
        "right": {"x": 205, "y": 0, "width": 200, "height": 200},
        "splitter": {"x": 200, "y": 0, "width": 5, "height": 200},
        "draggedRight": {"x": 105, "y": 0, "width": 300, "height": 200},
        "clamped": [150, 250],
    }


def test_drop_zones_and_floating_geometry_are_pure_math(layout_js):
    assert layout_js(
        """
        const limits = {minimum: {width: 200, height: 100}, maximum: {width: 400, height: 300}}
        return {
            // Group bands are a fraction of the side, capped in pixels.
            capped: DockLayout.edgeZone(170, 300, 1000, 600, 0.26, 160),
            inBand: DockLayout.edgeZone(150, 300, 1000, 600, 0.26, 160),
            outer: DockLayout.outerEdgeZone(995, 300, 1000, 600, 12),
            preview: DockLayout.previewRect({x: 0, y: 0, width: 100, height: 50}, "right", 0.3),
            // Size limits always apply; a screen area also pulls the window on screen.
            free: DockLayout.fitGeometry({x: 5000, y: 10, width: 900, height: 50}, limits, null),
            onScreen: DockLayout.fitGeometry({x: 5000, y: 10, width: 900, height: 50}, limits,
                                             {x: 0, y: 0, width: 800, height: 600})
        }
        """
    ) == {
        "capped": "center",
        "inBand": "left",
        "outer": "right",
        "preview": {"x": 70, "y": 0, "width": 30, "height": 50},
        "free": {"x": 5000, "y": 10, "width": 400, "height": 100},
        "onScreen": {"x": 400, "y": 10, "width": 400, "height": 100},
    }


def test_tab_moves_use_the_final_index_in_both_directions(layout_js):
    values = layout_js(
        """
        const group = {kind: "tabs", id: "g", docks: ["a", "b", "c", "d"], active: "a"}
        const snapshot = snapshotOf(group)
        const target = index => ({containerId: "main", groupId: "g", zone: "center", outer: false, tabIndex: index})
        const moved = (dockId, index) => {
            const result = DockOps.move(snapshot, {dockId: dockId}, target(index), context())
            return mainRoot(result.snapshot).docks
        }
        return {
            right: moved("a", 2),
            left: moved("d", 0),
            end: moved("b", 3),
            same: moved("c", 2)
        }
        """
    )
    assert values == {
        "right": ["b", "c", "a", "d"],
        "left": ["d", "a", "b", "c"],
        "end": ["a", "c", "d", "b"],
        "same": ["a", "b", "c", "d"],
    }


def test_moves_that_change_nothing_only_select(layout_js):
    assert layout_js(
        """
        const snapshot = snapshotOf(original)
        const onOwnEdge = DockOps.move(snapshot, {dockId: "c"},
            {containerId: "main", groupId: "right", zone: "left", outer: false, tabIndex: -1}, context())
        const onOwnCenter = DockOps.move(snapshot, {dockId: "a"},
            {containerId: "main", groupId: "left", zone: "center", outer: false, tabIndex: -1}, context())
        return {
            edgeUnchanged: onOwnEdge.snapshot === snapshot,
            edgeSelects: onOwnEdge.select,
            centerUnchanged: onOwnCenter.snapshot === snapshot,
            centerSelects: onOwnCenter.select
        }
        """
    ) == {"edgeUnchanged": True, "edgeSelects": "c", "centerUnchanged": True, "centerSelects": "a"}


def test_floating_containers_move_and_dock_back_as_a_whole(layout_js):
    values = layout_js(
        """
        const column = {kind: "split", id: "column", orientation: "vertical", weights: [0.5, 0.5],
                        children: [{kind: "tabs", id: "top", docks: ["d"], active: "d"},
                                   {kind: "tabs", id: "bottom", docks: ["e"], active: "e"}]}
        const tabbed = {kind: "tabs", id: "tabbed", docks: ["d", "e"], active: "e"}
        const floating = root => DockTypes.floatingContainer("f", {x: 0, y: 0, width: 300, height: 300}, "", root, "e")
        const docked = DockOps.dockContainerToMain(snapshotOf(original, [floating(column)]), "f", context())
        const merged = DockOps.move(snapshotOf(original, [floating(tabbed)]), {containerId: "f"},
            {containerId: "main", groupId: "right", zone: "center", outer: false, tabIndex: 0}, context())
        const splitCenter = DockOps.move(snapshotOf(original, [floating(column)]), {containerId: "f"},
            {containerId: "main", groupId: "right", zone: "center", outer: false, tabIndex: 0}, context())
        return {
            // A split container docks back as the same split, not as tabs.
            dockedColumn: mainRoot(docked.snapshot).children[2],
            dockedContainers: docked.snapshot.containers.length,
            dockedSelects: docked.select,
            mergedDocks: DockLayout.findGroup(mainRoot(merged.snapshot), "right").docks,
            splitCenterError: splitCenter.error
        }
        """
    )
    assert values["dockedColumn"]["orientation"] == "vertical"
    assert [child["docks"] for child in values["dockedColumn"]["children"]] == [["d"], ["e"]]
    assert values["dockedContainers"] == 1
    assert values["dockedSelects"] == "e"
    assert values["mergedDocks"] == ["d", "e", "c"]
    assert values["splitCenterError"] == "dock-policy-denied"


def test_reconcile_enforces_the_snapshot_invariant(layout_js):
    values = layout_js(
        """
        const valid = snapshotOf(original, [], ["d"])
        valid.containers[0].selected = "a"
        const broken = snapshotOf(
            {kind: "split", id: "root", orientation: "horizontal", weights: [0.5, 0.5],
             children: [{kind: "tabs", id: "x", docks: ["a", "ghost", "a"], active: "ghost"},
                        {kind: "tabs", id: "y", docks: ["ghost"], active: "ghost"}]},
            [DockTypes.floatingContainer("f", {}, "", {kind: "tabs", id: "z", docks: ["ghost"], active: "ghost"}, "ghost")],
            ["a", "b"])
        broken.containers[0].selected = "ghost"
        const fixed = DockOps.reconcile(broken, ["a", "b", "c"])
        return {
            unchanged: DockOps.reconcile(valid, ["a", "b", "c", "d"]) === valid,
            root: mainRoot(fixed),
            selected: fixed.containers[0].selected,
            containers: fixed.containers.length,
            hidden: fixed.hidden
        }
        """
    )
    assert values["unchanged"]
    # Unknown docks and duplicates are dropped, empty groups and floating
    # containers disappear, and registered docks the layout lost are hidden.
    assert values["root"] == {"kind": "tabs", "id": "x", "docks": ["a"], "active": "a"}
    assert values["selected"] == "a"
    assert values["containers"] == 1
    assert values["hidden"] == ["b", "c"]


def test_history_steps_keep_live_geometry_and_weights(layout_js):
    values = layout_js(
        """
        const floating = (geometry, root) => DockTypes.floatingContainer("f", geometry, "", root, "")
        const d = {kind: "tabs", id: "d", docks: ["d"], active: "d"}
        const saved = snapshotOf(original, [floating({x: 0, y: 0, width: 300, height: 300}, d)])
        const resized = DockLayout.withSplitRatio(original, "root", 0, 0.8)
        const live = snapshotOf(resized, [floating({x: 500, y: 60, width: 320, height: 300}, d)])
        const restored = DockOps.withLiveState(saved, live)
        return {
            weights: mainRoot(restored).weights,
            geometry: restored.containers[1].geometry,
            untouched: DockOps.withLiveState(saved, saved) === saved
        }
        """
    )
    assert values["weights"] == pytest.approx([0.8, 0.2])
    assert values["geometry"] == {"x": 500, "y": 60, "width": 320, "height": 300}
    assert values["untouched"]


# --------------------------------------------------------------------------
# Layout operations through the workspace
# --------------------------------------------------------------------------


def test_splits_are_nary_and_ratio_changes_are_not_structural(workspace, pump):
    structural: list[bool] = []
    ratios: list[tuple[str, int]] = []
    workspace.layoutChanged.connect(lambda: structural.append(True))
    workspace.splitRatioChanged.connect(lambda split_id, index: ratios.append((split_id, index)))

    assert workspace.moveDock("inspector", "scene", "right")
    assert workspace.moveDock("outline", "scene", "left")
    assert workspace.moveDock("console", "inspector", "center")
    assert workspace.activateDock("console")
    pump()

    root = main_container(saved(workspace))["root"]
    assert root["kind"] == "split"
    assert root["orientation"] == "horizontal"
    assert len(root["children"]) == 3  # not a nest of binary splits
    assert root["children"][2]["docks"] == ["inspector", "console"]
    assert root["children"][2]["active"] == "console"

    outline = workspace.dockById("outline")
    initial_width = outline.property("width")
    structural_count = len(structural)
    undo_depth = workspace.property("canUndoLayout")

    assert workspace.setSplitRatio(root["id"], 0, 0.7)
    pump()

    resized = main_container(saved(workspace))["root"]
    pair = resized["weights"][0] + resized["weights"][1]
    assert resized["weights"][0] / pair == pytest.approx(0.7)
    assert outline.property("width") > initial_width
    assert len(structural) == structural_count
    assert ratios == [(root["id"], 0)]
    assert workspace.property("canUndoLayout") == undo_depth


def test_hidden_docks_keep_their_items_and_can_be_shown(workspace):
    assert sorted(qml_value(workspace.dockIds())) == sorted(DOCK_IDS)

    assert workspace.closeDock("outline")
    assert workspace.dockState("outline") == "hidden"
    assert "outline" in qml_value(workspace.property("hiddenDocks"))
    assert workspace.dockById("outline") is not None  # item survives hiding

    assert workspace.showDock("outline")
    assert workspace.dockState("outline") == "docked"
    assert "scene" in qml_value(workspace.neighborsOf("outline"))
    assert workspace.containerOf("outline") == "main"
    assert workspace.dockState("no-such-dock") == ""


def test_dropping_a_sole_group_on_its_own_edge_is_a_successful_no_op(workspace):
    for dock_id in ("outline", "inspector", "console"):
        assert workspace.hideDock(dock_id)

    before = workspace.saveLayout()
    assert workspace.moveDock("scene", "scene", "left")
    assert workspace.saveLayout() == before


def test_undo_and_redo_round_trip_the_layout(workspace):
    original = workspace.saveLayout()
    assert workspace.moveDock("inspector", "scene", "right")
    changed = workspace.saveLayout()
    assert changed != original

    assert workspace.undoLayout()
    assert workspace.saveLayout() == original
    assert workspace.redoLayout()
    assert workspace.saveLayout() == changed

    workspace.clearLayoutHistory()
    assert not workspace.property("canUndoLayout")
    assert not workspace.undoLayout()


def test_undo_leaves_floating_windows_where_they_are(workspace, pump):
    assert workspace.floatDock("inspector", 120, 140, 510, 330)
    assert workspace.moveDock("outline", "scene", "right")
    pump()
    window = workspace.floatingWindowForDock("inspector")
    floating_id = floating_containers(saved(workspace))[0]["id"]
    assert workspace.beginDrag({"containerId": floating_id, "pressPoint": QPointF(0, 0)})
    workspace.moveDrag(QPointF(1500, 20))
    assert workspace.endDrag(QPointF(1500, 20))
    pump()
    moved = floating_containers(saved(workspace))[0]["geometry"]

    assert workspace.undoLayout()
    pump()
    assert floating_containers(saved(workspace))[0]["geometry"] == moved
    assert window.property("x") == moved["x"]


def test_restore_sanitizes_untrusted_layout(workspace):
    activated: list[str] = []
    workspace.dockActivated.connect(activated.append)

    assert workspace.restoreLayout(
        {
            "version": LAYOUT_VERSION,
            "containers": [
                {
                    "id": "untrusted-main",
                    "kind": "main",
                    "root": {
                        "kind": "tabs",
                        "id": "untrusted-tabs",
                        "docks": ["scene", "removed", "scene"],
                        "active": "removed",
                    },
                },
                {
                    "id": "untrusted-float",
                    "kind": "floating",
                    "geometry": {"x": 99999, "y": 99999, "width": 1, "height": 1},
                    "screen": "disconnected",
                    "root": {
                        "kind": "tabs",
                        "id": "also-untrusted",
                        "docks": ["inspector"],
                        "active": "inspector",
                    },
                },
            ],
            "hidden": ["console"],
        }
    )

    restored = saved(workspace)
    main = main_container(restored)
    floating = floating_containers(restored)[0]

    # Unknown docks are dropped, duplicates collapsed, and docks that the
    # layout never mentions stay in the layout rather than vanishing.
    assert sorted(collect_docks(main["root"])) == ["outline", "scene"]
    assert restored["hidden"] == ["console"]
    assert collect_docks(floating["root"]) == ["inspector"]
    # Untrusted ids are reissued so they cannot collide with live ones.
    assert main["id"] == "main"
    assert main["root"]["id"] != "untrusted-tabs"
    assert floating["id"] != "untrusted-float"
    # An undersized, off-screen floating rect is sized up to the dock's own
    # minimum and pulled back onto a screen.
    width, height = floating_minimum(workspace, "inspector")
    assert (floating["geometry"]["width"], floating["geometry"]["height"]) == (width, height)
    assert floating["geometry"]["x"] < 99999
    assert "inspector" in activated


def test_the_saved_v2_format_round_trips(load, pump):
    window = load(GOLDEN_QML, "GoldenTest.qml")
    workspace = window.findChild(QObject, "goldenWorkspace")
    golden = json.loads((TEST_DATA / "layout_v2.json").read_text(encoding="utf-8"))

    assert workspace.restoreLayout(json.dumps(golden))
    pump()
    assert without_ids(saved(workspace)) == without_ids(golden)


def test_restore_keeps_each_containers_selection(load, pump):
    window = load(GOLDEN_QML, "GoldenTest.qml")
    workspace = window.findChild(QObject, "goldenWorkspace")
    golden = json.loads((TEST_DATA / "layout_v2.json").read_text(encoding="utf-8"))

    assert workspace.restoreLayout(json.dumps(golden))
    pump()
    assert workspace.selectedDock("main") == "inspector"
    floating = floating_containers(saved(workspace))[0]
    assert workspace.selectedDock(floating["id"]) == "timeline"
    assert workspace.floatingWindowForDock("timeline").property("title") == "timeline"


def test_selection_is_not_an_undo_step(workspace):
    workspace.clearLayoutHistory()
    assert workspace.moveDock("inspector", "scene", "right")
    assert workspace.undoLayout()
    assert not workspace.property("canUndoLayout")

    for dock_id in ("outline", "console", "scene"):
        assert workspace.activateDock(dock_id)
    assert not workspace.property("canUndoLayout")
    # Selecting also leaves the redo step in place.
    assert workspace.property("canRedoLayout")


def test_undo_never_brings_back_a_dock_that_is_gone(load, pump):
    window = load(DYNAMIC_DOCK_QML, "DynamicDockTest.qml")
    workspace = window.findChild(QObject, "dynamicWorkspace")
    pump()

    # Undoing past a destroying close leaves the destroyed dock out.
    assert workspace.closeDock("dynamic-panel")
    pump()
    assert workspace.undoLayout()
    assert "dynamic-panel" not in workspace.saveLayout()
    assert workspace.dockState("dynamic-panel") == ""


def test_undo_past_a_created_dock_hides_it(load, pump):
    window = load(DYNAMIC_DOCK_QML, "DynamicDockTest.qml")
    workspace = window.findChild(QObject, "dynamicWorkspace")
    hidden: list[str] = []
    workspace.dockHidden.connect(hidden.append)

    assert workspace.undoLayout()
    assert workspace.dockState("dynamic-panel") == "hidden"
    assert hidden == ["dynamic-panel"]
    assert workspace.showDock("dynamic-panel")
    assert workspace.dockState("dynamic-panel") == "docked"


def test_moving_a_hidden_dock_shows_it(workspace):
    shown: list[str] = []
    workspace.dockShown.connect(shown.append)

    assert workspace.hideDock("console")
    assert workspace.moveDock("console", "scene", "bottom")
    assert workspace.dockState("console") == "docked"
    assert "console" not in qml_value(workspace.property("hiddenDocks"))
    assert shown == ["console"]


def test_lifecycle_signals_follow_undo_and_redo(workspace):
    events: list[str] = []
    workspace.dockHidden.connect(lambda dock_id: events.append(f"hidden:{dock_id}"))
    workspace.dockShown.connect(lambda dock_id: events.append(f"shown:{dock_id}"))

    assert workspace.hideDock("outline")
    assert workspace.undoLayout()
    assert workspace.redoLayout()
    assert events == ["hidden:outline", "shown:outline", "hidden:outline"]


def test_docking_a_floating_container_back_keeps_its_split(workspace, pump):
    assert workspace.moveDock("inspector", "scene", "right")
    assert workspace.floatDock("console", 100, 100, 400, 500)
    assert workspace.moveDock("outline", "console", "bottom")
    pump()
    floating = floating_containers(saved(workspace))[0]
    assert floating["root"]["kind"] == "split"

    assert workspace.dockContainerToMain(floating["id"])
    pump()
    state = saved(workspace)
    assert not floating_containers(state)
    column = next(
        child
        for child in main_container(state)["root"]["children"]
        if child["kind"] == "split"
    )
    assert column["orientation"] == "vertical"
    assert collect_docks(column) == ["console", "outline"]


def test_register_dock_falls_back_to_the_main_area_quietly(load, pump):
    window = load(DYNAMIC_DOCK_QML, "DynamicDockTest.qml")
    workspace = window.findChild(QObject, "dynamicWorkspace")
    errors: list[str] = []
    workspace.errorOccurred.connect(lambda code, _message: errors.append(code))

    component = QQmlComponent(QQmlEngine.contextForObject(workspace).engine())
    component.setData(
        b'import QuickDock 1.0\nDockItem { dockId: "extra"; allowedZones: ["center"] }',
        QUrl.fromLocalFile(str(Path.cwd() / "Extra.qml")),
    )
    assert workspace.createDock(component, {}, "dynamic-panel", "left") is not None
    assert workspace.dockState("extra") == "docked"
    assert errors == []


def test_docks_keep_their_parent_when_the_tree_changes_elsewhere(workspace, pump):
    build_split_layout(workspace)
    pump()
    scene = workspace.dockById("scene")
    host = scene.parentItem()

    # Splitting another group, and dropping a dock into another column,
    # re-lays out the tree around `scene` without re-creating its group.
    assert workspace.moveDock("outline", "inspector", "bottom")
    assert workspace.moveDock("outline", "console", "right")
    pump()
    assert scene.parentItem() is not None
    assert getCppPointer(scene.parentItem())[0] == getCppPointer(host)[0]


# --------------------------------------------------------------------------
# Policies and size constraints
# --------------------------------------------------------------------------


def test_central_dock_cannot_be_closed_hidden_floated_or_moved(workspace, pump):
    errors: list[str] = []
    workspace.errorOccurred.connect(lambda code, _message: errors.append(code))

    assert workspace.setProperty("centralDockId", "scene")
    pump()

    assert not workspace.canCloseDock("scene")
    assert not workspace.canFloatDock("scene")
    assert not workspace.closeDock("scene")
    assert not workspace.hideDock("scene")
    assert not workspace.floatDock("scene", None, None, None, None)
    assert not workspace.moveDock("scene", "outline", "left")
    assert errors == ["central-dock-policy"] * 4


def test_dock_item_policies_restrict_zones_and_tabbing(workspace):
    inspector = workspace.dockById("inspector")

    assert inspector.setProperty("allowedZones", ["left"])
    assert not workspace.moveDock("inspector", "scene", "right")
    assert workspace.moveDock("inspector", "scene", "left")

    assert inspector.setProperty("tabbable", False)
    assert not workspace.moveDock("inspector", "scene", "center")


def test_size_constraints_bound_docked_and_floating_geometry(workspace, pump):
    inspector = workspace.dockById("inspector")
    minimum, maximum = QSizeF(360, 180), QSizeF(420, 260)
    assert inspector.setProperty("minimumSize", minimum)
    assert inspector.setProperty("maximumSize", maximum)

    assert workspace.moveDock("inspector", "scene", "left")
    root = main_container(saved(workspace))["root"]
    assert workspace.setSplitRatio(root["id"], 0, 0.0)
    pump()
    assert inspector.property("width") >= minimum.width()

    # Floating geometry is clamped to the dock's maximum plus its header.
    assert workspace.floatDock("inspector", 100, 100, 4000, 4000)
    pump()
    geometry = floating_containers(saved(workspace))[0]["geometry"]
    assert geometry["width"] == maximum.width()
    assert geometry["height"] == maximum.height() + token(workspace, "header.height")
    assert workspace.dockState("inspector") == "floating"


# --------------------------------------------------------------------------
# Drag targeting
# --------------------------------------------------------------------------


def test_edge_bands_are_capped_in_pixels_and_outer_bands_are_narrow(workspace):
    fraction = setting(workspace, "edgeFraction")
    max_band = setting(workspace, "edgeMaxBand")
    outer_band = setting(workspace, "outerEdgeBand")
    # The pixel cap only means something while it is the binding constraint.
    assert workspace.width() * fraction > max_band

    just_outside = workspace.mapToGlobal(QPointF(max_band + 1, workspace.height() / 2))
    target = drag(workspace, just_outside, dockId="outline")
    assert (target["zone"], target["outer"]) == ("center", False)
    workspace.cancelDrag()

    inside_outer = workspace.mapToGlobal(QPointF(outer_band / 2, workspace.height() / 2))
    target = drag(workspace, inside_outer, dockId="outline")
    assert (target["zone"], target["outer"]) == ("left", True)
    workspace.cancelDrag()
    assert not workspace.property("dragging")


def test_a_splitter_is_not_a_drop_target(workspace, pump):
    assert workspace.moveDock("inspector", "scene", "right")
    pump()
    splitter = find_items(workspace, "dockSplitter_")[0]
    point = splitter.mapToGlobal(QPointF(splitter.width() / 2, splitter.height() / 2))

    assert drag(workspace, point, dockId="outline") is None
    workspace.cancelDrag()


def test_outer_edge_drop_splits_the_root_at_the_behavior_ratio(workspace, pump):
    ratio = 0.3
    evaluate(workspace, f"behavior.defaultSplitRatio = {ratio}")
    outer_band = setting(workspace, "outerEdgeBand")

    assert workspace.floatDock("inspector", 1200, 140, 510, 330)
    pump()
    floating_id = floating_containers(saved(workspace))[0]["id"]

    # Dragging a single-dock window's header moves the window itself.
    point = workspace.mapToGlobal(QPointF(outer_band / 2, workspace.height() / 2))
    target = drag(workspace, point, containerId=floating_id)
    assert (target["zone"], target["outer"]) == ("left", True)
    assert workspace.endDrag(point)
    pump()

    root = main_container(saved(workspace))["root"]
    assert root["kind"] == "split"
    assert root["orientation"] == "horizontal"
    assert root["weights"][0] == pytest.approx(ratio)
    assert collect_docks(root["children"][0]) == ["inspector"]


def test_tab_drag_reorders_within_the_group(workspace, pump):
    root = main_container(saved(workspace))["root"]
    assert root["docks"] == list(DOCK_IDS)

    point = tab_drop_point(workspace, 1)
    target = drag(workspace, point, dockId="console")
    assert target["zone"] == "center"
    assert target["tabIndex"] == 1

    indicator = find_item(workspace, "dockDropPreview_main")
    assert indicator is not None
    assert indicator.isVisible()
    assert indicator.property("zone") == "tab"
    assert indicator.width() == token(workspace, "drop.tabMarkerWidth")
    assert indicator.height() < token(workspace, "header.height")
    assert workspace.endDrag(point)
    assert not indicator.isVisible()

    assert main_container(saved(workspace))["root"]["docks"] == [
        "scene",
        "console",
        "outline",
        "inspector",
    ]

    # Moving right: the index is the final position of the dragged tab.
    pump()
    last_tab = find_item(workspace, "dockDragArea_inspector", visible=True)
    point = last_tab.mapToGlobal(QPointF(last_tab.width() - 1, last_tab.height() / 2))
    target = drag(workspace, point, dockId="scene")
    assert target["tabIndex"] == 3
    assert workspace.endDrag(point)
    assert main_container(saved(workspace))["root"]["docks"] == [
        "console",
        "outline",
        "inspector",
        "scene",
    ]


def test_drag_released_outside_any_surface_floats_where_the_preview_was(workspace, pump):
    press = workspace.mapToGlobal(QPointF(40, 60))
    release = QPointF(2400, 900)
    assert drag(workspace, press, dockId="scene") is not None
    assert workspace.endDrag(release)
    pump()

    floating = floating_containers(saved(workspace))
    assert len(floating) == 1
    # The window takes the dragged group's size and keeps the press offset.
    assert floating[0]["geometry"] == {
        "x": 2400 - 40,
        "y": 900 - 60,
        "width": workspace.width(),
        "height": workspace.height(),
    }


def test_a_floating_container_is_a_drop_target_with_its_own_overlay(workspace, pump):
    assert workspace.floatDock("inspector", 1200, 140, 510, 330)
    pump()
    window = workspace.floatingWindowForDock("inspector")
    floating_id = floating_containers(saved(workspace))[0]["id"]
    center = QPointF(
        window.property("x") + window.property("width") / 2,
        window.property("y") + window.property("height") / 2,
    )

    target = drag(workspace, workspace_center(workspace), dockId="scene")
    target = qml_value(workspace.moveDrag(center))
    assert target["containerId"] == floating_id
    # The preview is drawn by the floating window, not through the host.
    preview = find_item(window, f"dockDropPreview_{floating_id}")
    assert preview is not None and preview.isVisible()
    assert not find_item(workspace, "dockDropPreview_main").isVisible()

    assert workspace.endDrag(center)
    pump()
    assert collect_docks(floating_containers(saved(workspace))[0]["root"]) == [
        "inspector",
        "scene",
    ]


def test_tab_and_title_bar_drags_move_different_scopes(workspace, pump):
    assert workspace.floatDock("inspector", 1200, 140, 510, 330)
    assert workspace.moveDock("scene", "inspector", "center")
    pump()
    floating_id = floating_containers(saved(workspace))[0]["id"]
    drop_point = workspace_center(workspace)

    # Dragging one tab extracts only that dock.
    window = workspace.floatingWindowForDock("scene")
    tab = find_item(window, "dockDragArea_scene", visible=True)
    drag(workspace, tab.mapToGlobal(QPointF(2, 2)), dockId="scene")
    assert workspace.endDrag(drop_point)
    pump()
    state = saved(workspace)
    assert collect_docks(floating_containers(state)[0]["root"]) == ["inspector"]
    assert "scene" in collect_docks(main_container(state)["root"])

    # Dragging the title bar moves the whole container, which then disappears.
    assert workspace.moveDock("scene", "inspector", "center")
    pump()
    target = drag(workspace, drop_point, containerId=floating_id)
    assert target["containerId"] == "main"
    assert workspace.endDrag(drop_point)
    pump()

    state = saved(workspace)
    assert not floating_containers(state)
    assert set(collect_docks(main_container(state)["root"])) >= {"inspector", "scene"}


# --------------------------------------------------------------------------
# Floating windows
# --------------------------------------------------------------------------


def test_tabbing_into_a_float_reuses_its_window_and_adds_a_title_bar(workspace, pump):
    assert workspace.floatDock("inspector", 120, 140, 510, 330)
    assert workspace.floatDock("scene", 180, 190, 420, 260)
    pump()
    window = workspace.floatingWindowForDock("inspector")
    window_pointer = getCppPointer(window)[0]
    assert len(floating_containers(saved(workspace))) == 2
    # A single-dock float has no separate title bar. Its header moves the window.
    assert not window.property("hasTitleBar")
    assert find_item(window, "dockHeader_inspector", visible=True).property("moveWindow")

    assert workspace.moveDock("scene", "inspector", "center")
    pump()
    floating = floating_containers(saved(workspace))
    assert len(floating) == 1
    assert collect_docks(floating[0]["root"]) == ["inspector", "scene"]
    # The surviving window is the original one, not a replacement.
    assert getCppPointer(workspace.floatingWindowForDock("inspector"))[0] == window_pointer

    # With tabs, a title bar owns moving and maximizing.
    floating_id = floating[0]["id"]
    assert window.property("hasTitleBar")
    assert find_item(window, f"floatingTitleBar_{floating_id}").isVisible()
    assert find_item(window, f"floatingMaximizeButton_{floating_id}").isVisible()
    for dock_id in ("inspector", "scene"):
        header = find_item(window, f"dockHeader_{dock_id}", visible=True)
        assert header is not None and not header.property("moveWindow")
        assert find_item(window, f"dockMaximizeButton_{dock_id}", visible=True) is None


@pytest.mark.parametrize(
    "edges, delta, expected",
    [
        # Dragging a corner grows the window away from its origin ...
        (Qt.Edge.BottomEdge | Qt.Edge.RightEdge, QPointF(80, 40), {"width": 80, "height": 40}),
        # ... while dragging the top edge moves the origin and keeps the
        # opposite edge fixed.
        (Qt.Edge.TopEdge, QPointF(0, 45), {"y": 45, "height": -45}),
    ],
)
def test_floating_resize_is_live_but_committed_once(workspace, pump, edges, delta, expected):
    assert workspace.floatDock("inspector", 120, 140, 510, 330)
    pump()
    window = workspace.floatingWindowForDock("inspector")
    before = floating_containers(saved(workspace))[0]["geometry"]
    after = {**before, **{key: before[key] + d for key, d in expected.items()}}

    window.beginResize(int(edges.value), QPointF(0, 0))
    window.continueResize(delta)
    # The window follows the pointer immediately ...
    assert {key: window.property(key) for key in after} == after
    # ... but the model is not rewritten on every step of the drag.
    assert floating_containers(saved(workspace))[0]["geometry"] == before

    window.endResize()
    pump()
    assert floating_containers(saved(workspace))[0]["geometry"] == after


def test_floating_move_is_committed_once_and_can_dock_back(workspace, pump):
    assert workspace.floatDock("inspector", 120, 140, 510, 330)
    pump()
    window = workspace.floatingWindowForDock("inspector")
    before = floating_containers(saved(workspace))[0]

    start = QPointF(400, 300)
    assert workspace.beginDrag({"containerId": before["id"], "pressPoint": start})
    workspace.moveDrag(QPointF(1445, 335))
    pump()
    assert window.property("x") == before["geometry"]["x"] + 1045
    assert floating_containers(saved(workspace))[0]["geometry"] == before["geometry"]

    # Released away from any target: the window stays where it was moved to.
    assert workspace.endDrag(QPointF(1445, 335))
    pump()
    moved = floating_containers(saved(workspace))[0]["geometry"]
    assert moved["x"] == before["geometry"]["x"] + 1045
    assert moved["y"] == before["geometry"]["y"] + 35

    drop_point = workspace_center(workspace)
    drag(workspace, drop_point, containerId=before["id"])
    assert workspace.endDrag(drop_point)
    pump()
    state = saved(workspace)
    assert not floating_containers(state)
    assert "inspector" in collect_docks(main_container(state)["root"])


def test_each_floating_window_gets_a_window_integration_that_can_take_over_maximizing(load, pump):
    with qml_messages() as messages:
        host = load(WINDOW_INTEGRATION_QML, "WindowIntegrationTest.qml")
        workspace = host.findChild(QObject, "integrationWorkspace")
        assert workspace.floatDock("scene", 120, 140, 510, 330)
        assert workspace.floatDock("outline", 180, 190, 420, 260)
        pump()
    assert not warnings_in(messages)

    # Only floating windows get one: one each, filling the window.
    assert not find_items(host, "windowIntegration_")
    integrations = {}
    for dock_id in ("scene", "outline"):
        window = workspace.floatingWindowForDock(dock_id)
        found = find_items(window, "windowIntegration_")
        assert [item.objectName() for item in found] == [f"windowIntegration_{window.property('containerId')}"]
        assert same_object(found[0].property("floatingWindow"), window)
        assert (found[0].width(), found[0].height()) == (window.width(), window.height())
        integrations[dock_id] = found[0]

    window = workspace.floatingWindowForDock("scene")
    integration = integrations["scene"]
    integration.setProperty("handlesMaximize", True)
    window.toggleMaximized()
    pump()
    # The integration maximized the window (here, it did nothing) ...
    assert integration.property("maximizeRequests") == 1
    assert not window.property("maximized")

    # ... until it declines, and the window does it itself.
    integration.setProperty("handlesMaximize", False)
    window.toggleMaximized()
    pump()
    assert integration.property("maximizeRequests") == 2
    assert window.property("maximized")

    # Dragging a maximized window restores it the same way.
    assert workspace.beginDrag({"containerId": window.property("containerId"), "pressPoint": QPointF(200, 150)})
    workspace.cancelDrag()
    pump()
    assert integration.property("maximizeRequests") == 3
    assert not window.property("maximized")
    assert integrations["outline"].property("maximizeRequests") == 0

    # An integration goes with its window. processEvents() alone does not
    # run deferred deletes at this level.
    destroyed: list[bool] = []
    integration.destroyed.connect(lambda: destroyed.append(True))
    assert workspace.dockToMain("scene")
    pump()
    QCoreApplication.sendPostedEvents(None, QEvent.Type.DeferredDelete)
    assert destroyed == [True]


def test_a_floating_windows_maximize_button_follows_its_chrome_and_shows_platform_state(workspace, pump):
    assert workspace.floatDock("inspector", 120, 140, 510, 330)
    pump()
    window = workspace.floatingWindowForDock("inspector")
    floating_id = window.property("containerId")

    # A lone dock's header moves its window, so it has the window's button.
    header_button = find_item(window, "dockMaximizeButton_inspector", visible=True)
    assert same_object(window.property("maximizeButton"), header_button)

    # A platform that hit-tests the button reports its state to the window,
    # and the button shows it as it shows its own.
    hover = token(workspace, "colors.hover")
    pressed = evaluate(workspace, "Qt.darker(style.colors.hover, 1.15)")
    window.setProperty("maximizeButtonHovered", True)
    assert header_button.property("color") == hover
    window.setProperty("maximizeButtonPressed", True)
    assert header_button.property("color") == pressed
    window.setProperty("maximizeButtonHovered", False)
    window.setProperty("maximizeButtonPressed", False)
    assert header_button.property("color") != hover

    QTest.mousePress(window, Qt.MouseButton.LeftButton, Qt.KeyboardModifier.NoModifier, center_of(header_button))
    assert header_button.property("color") == pressed
    QTest.mouseRelease(window, Qt.MouseButton.LeftButton, Qt.KeyboardModifier.NoModifier, center_of(header_button))
    pump()
    assert window.property("maximized")
    window.showNormal()
    pump()

    # A title bar takes over for a second dock, or when asked to ...
    assert workspace.moveDock("scene", "inspector", "center")
    pump()
    title_button = find_item(window, f"floatingMaximizeButton_{floating_id}", visible=True)
    assert same_object(window.property("maximizeButton"), title_button)
    window.setProperty("maximizeButtonHovered", True)
    assert title_button.property("color") == hover
    window.setProperty("maximizeButtonHovered", False)

    assert workspace.dockToMain("scene")
    pump()
    assert same_object(
        window.property("maximizeButton"), find_item(window, "dockMaximizeButton_inspector", visible=True)
    )

    evaluate(workspace, "behavior.singleDockTitleBar = true")
    pump()
    assert same_object(
        window.property("maximizeButton"), find_item(window, f"floatingMaximizeButton_{floating_id}", visible=True)
    )

    # ... and hands the button back to the header when it goes.
    evaluate(workspace, "behavior.singleDockTitleBar = false")
    pump()
    assert same_object(
        window.property("maximizeButton"), find_item(window, "dockMaximizeButton_inspector", visible=True)
    )

    # A hidden button is not offered.
    workspace.dockById("inspector").setProperty("headerButtonsVisible", False)
    pump()
    assert window.property("maximizeButton") is None


def test_custom_delegates_receive_the_values_they_declare(load, pump):
    with qml_messages() as messages:
        workspace = load(CUSTOM_DELEGATES_QML, "CustomDelegatesTest.qml")
    assert not warnings_in(messages)
    assert not [message for message in messages if "Unable to assign" in message]
    assert workspace.floatDock("inspector", 120, 140, 510, 330)
    assert workspace.moveDock("scene", "inspector", "center")
    pump()

    floating_id = floating_containers(saved(workspace))[0]["id"]
    window = workspace.floatingWindowForDock("inspector")
    title = find_item(window, f"customFloatingTitle_{floating_id}")

    # The title bar follows the container's selected dock.
    assert title is not None and title.isVisible()
    assert title.property("receivedDockId") == "scene"
    assert title.property("receivedTitle") == "Scene"
    assert title.property("receivedWindow") is not None
    assert not title.property("receivedMaximized")
    assert window.property("title") == "Scene"

    # Tabs get the values they declare, kept up to date, and take their
    # width from the delegate.
    scene_tab = find_item(window, "customTab_scene")
    inspector_tab = find_item(window, "customTab_inspector")
    assert scene_tab.property("selected") and not inspector_tab.property("selected")
    assert scene_tab.width() > inspector_tab.width()

    assert workspace.activateDock("inspector")
    pump()
    assert title.property("receivedDockId") == "inspector"
    assert window.property("title") == "Inspector"
    assert inspector_tab.property("selected") and not scene_tab.property("selected")

    # The main area is empty now, so it shows the placeholder.
    placeholder = find_item(workspace, "customPlaceholder", visible=True)
    assert placeholder is not None
    assert evaluate(workspace, "Text.Normal") == evaluate(placeholder, "style")

    window.showFullScreen()
    pump()
    assert title.property("receivedMaximized")
    window.showNormal()


def test_the_readme_delegate_examples_work(load, pump):
    with qml_messages() as messages:
        window = load(README_DELEGATES_QML, "ReadmeDelegatesTest.qml")
        workspace = window.findChild(QObject, "readmeWorkspace")
        assert workspace.moveDock("outline", "scene", "right")
        pump()
    assert not warnings_in(messages)

    # The custom header drags through DockDragArea; releasing it over the
    # left edge of the scene group splits it there.
    header = find_item(window, "readmeHeader_outline", visible=True)
    start = center_of(header)
    scene = workspace.dockById("scene")
    target = scene.mapToScene(QPointF(8, scene.height() / 2)).toPoint()
    QTest.mousePress(window, Qt.MouseButton.LeftButton, Qt.KeyboardModifier.NoModifier, start)
    for step in (0.3, 0.6, 1.0):
        QTest.mouseMove(window, start + (target - start) * step, 10)
        pump(1)
    assert workspace.property("dragging")
    QTest.mouseRelease(window, Qt.MouseButton.LeftButton, Qt.KeyboardModifier.NoModifier, target)
    pump()

    root = main_container(saved(workspace))["root"]
    assert collect_docks(root) == ["outline", "scene"]


def test_closing_the_host_window_hides_its_floating_windows(hosted, pump):
    assert hosted.workspace.floatDock("scene", 100, 100, 360, 240)
    pump()
    floating_window = hosted.workspace.floatingWindowForDock("scene")
    assert floating_window.property("visible")
    assert floating_window.property("transientParent") is not None

    hosted.window.close()
    pump()

    assert not hosted.window.property("visible")
    assert not floating_window.property("visible")
    assert hosted.workspace.property("hostClosing")
    # Closing for the host leaves the layout as it was.
    assert floating_containers(saved(hosted.workspace))


# --------------------------------------------------------------------------
# Pointer interaction
# --------------------------------------------------------------------------


def test_visible_docks_get_geometry_and_inactive_tabs_do_not(workspace, pump):
    build_split_layout(workspace)
    pump()

    for dock_id in ("scene", "inspector", "console"):
        content = workspace.dockById(dock_id)
        assert content.property("visible")
        assert content.property("width") > 0 and content.property("height") > 0
    # An inactive tab is kept alive but not shown.
    assert not workspace.dockById("outline").property("visible")


@pytest.mark.parametrize("horizontal", [True, False])
def test_dragging_a_splitter_resizes_live_and_commits_once(hosted, pump, horizontal):
    window, workspace = hosted
    build_split_layout(workspace)
    pump()

    splitter = next(
        item
        for item in find_items(workspace, "dockSplitter_")
        if (item.width() > item.height()) == horizontal
    )
    scene = workspace.dockById("scene")
    axis = "height" if horizontal else "width"
    initial = scene.property(axis)

    commits: list[tuple[str, int]] = []
    workspace.splitRatioChanged.connect(lambda split_id, index: commits.append((split_id, index)))

    start = center_of(splitter)
    offsets = [QPoint(0, d) if horizontal else QPoint(d, 0) for d in (15, 45, 75)]
    QTest.mousePress(window, Qt.MouseButton.LeftButton, Qt.KeyboardModifier.NoModifier, start)
    sizes = []
    for offset in offsets:
        QTest.mouseMove(window, start + offset, 10)
        pump(1)
        sizes.append(scene.property(axis))
    QTest.mouseRelease(
        window, Qt.MouseButton.LeftButton, Qt.KeyboardModifier.NoModifier, start + offsets[-1]
    )
    pump()

    # The dock tracks the pointer during the drag ...
    assert sizes == sorted(sizes)
    assert scene.property(axis) > initial
    # ... and the ratio is written to the model exactly once, on release.
    assert len(commits) == 1


def test_dragging_a_header_shows_a_preview_for_that_dock(hosted, pump):
    window, workspace = hosted
    drag_area = find_item(window, "dockDragArea_scene", visible=True)
    start = center_of(drag_area)

    with qml_messages() as messages:
        QTest.mousePress(window, Qt.MouseButton.LeftButton, Qt.KeyboardModifier.NoModifier, start)
        QTest.mouseMove(window, start + QPoint(30, 0), 10)
        pump(1)
        preview = workspace.findChild(QObject, "dockDragPreview")
        assert preview is not None and preview.property("visible")
        assert preview.property("dockId") == "scene"
        assert workspace.property("dragging")

        QTest.mouseRelease(
            window, Qt.MouseButton.LeftButton, Qt.KeyboardModifier.NoModifier, start + QPoint(30, 0)
        )
        pump(1)
        assert not preview.property("visible")
        assert not workspace.property("dragging")

    assert not warnings_in(messages)


def test_close_button_removes_and_destroys_a_dynamically_created_dock(load, pump):
    window = load(DYNAMIC_DOCK_QML, "DynamicDockTest.qml")
    workspace = window.findChild(QObject, "dynamicWorkspace")
    panel = workspace.dockById("dynamic-panel")
    close_button = find_item(window, "dockCloseButton_dynamic-panel", visible=True)
    assert panel is not None and close_button is not None

    events: list[str] = []
    workspace.dockAboutToClose.connect(lambda dock_id, _item: events.append(f"about:{dock_id}"))
    panel.destroyed.connect(lambda: events.append("destroyed"))
    workspace.dockClosed.connect(lambda dock_id: events.append(f"closed:{dock_id}"))

    QTest.mouseClick(
        window, Qt.MouseButton.LeftButton, Qt.KeyboardModifier.NoModifier, center_of(close_button)
    )
    pump()

    assert workspace.dockById("dynamic-panel") is None
    assert main_container(saved(workspace))["root"] is None
    # An owned dock is destroyed between the two signals, never after them.
    assert events == ["about:dynamic-panel", "destroyed", "closed:dynamic-panel"]


def test_tabs_overflow_into_a_menu_listing_every_dock(hosted, pump):
    window, workspace = hosted
    window.setWidth(300)
    pump()

    overflow = find_item(workspace, "dockOverflowButton", visible=True)
    assert overflow is not None
    menu = overflow.findChild(QObject, "dockOverflowMenu")
    assert menu.property("count") == len(DOCK_IDS)


# --------------------------------------------------------------------------
# Engine hygiene
# --------------------------------------------------------------------------


def test_reset_after_float_leaves_no_type_or_binding_loop_warnings(workspace, pump):
    with qml_messages() as messages:
        assert workspace.moveDock("inspector", "scene", "right")
        assert workspace.moveDock("console", "scene", "bottom")
        assert workspace.floatDock("inspector", 100, 100, 360, 240)
        pump()
        assert workspace.resetLayout()
        assert workspace.moveDock("outline", "scene", "left")
        pump()

    assert not warnings_in(messages)
    assert floating_containers(saved(workspace)) == []


def test_a_registered_dock_keeps_its_id(workspace):
    errors: list[str] = []
    workspace.errorOccurred.connect(lambda code, _message: errors.append(code))

    scene = workspace.dockById("scene")
    scene.setProperty("dockId", "renamed")
    assert scene.property("dockId") == "scene"
    assert errors == ["dock-id-changed"]
