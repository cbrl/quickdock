from __future__ import annotations

import json
import os
from collections.abc import Iterator
from contextlib import contextmanager
from pathlib import Path
from typing import NamedTuple

import pytest


os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtCore import (  # noqa: E402
    QCoreApplication,
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


PACKAGE = Path(__file__).parents[1] / "src" / "quickdock"
LIBRARY = PACKAGE / "qml" / "QuickDock"

DOCK_IDS = ("scene", "outline", "inspector", "console")

# Four declarative docks in a Window. Everything starts as one tab group. Tests
# that need splits must explicitly build them.
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

CUSTOM_FLOATING_TITLE_QML = b"""
import QtQuick
import QuickDock 1.0

DockWorkspace {
    width: 900
    height: 600
    floatingTitleBarDelegate: Component {
        Rectangle {
            objectName: "customFloatingTitle_" + parent.containerId
            color: parent.style.colors.accent
            property string receivedDockId: parent.dockId
            property string receivedTitle: parent.title
            property bool receivedMaximized: parent.maximized
            property var receivedWindow: parent.floatingWindow
        }
    }

    DockItem { dockId: "scene"; title: "Scene"; Rectangle { anchors.fill: parent } }
    DockItem { dockId: "inspector"; title: "Inspector"; Rectangle { anchors.fill: parent } }
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


def token(workspace, path: str):
    """Read a style token by its QML path, e.g. ``token(ws, "header.height")``.

    Grouped tokens are QML-declared types with no Python converter, so they
    are evaluated in the workspace's own context rather than walked from
    Python. Expected values are derived from these rather than hard-coded, so
    retuning the theme cannot silently invalidate a test.
    """

    expression = QQmlExpression(
        QQmlEngine.contextForObject(workspace), workspace, f"style.{path}"
    )
    value, _undefined = expression.evaluate()
    assert not expression.hasError(), expression.error().toString()
    return value


def descendants(root):
    """Yield every visual item under an Item or Window, depth first.

    Repeater delegates are not reachable through ``findChild()`` here, so
    objectName lookups inside tab rows must walk ``childItems()``.
    """

    pending = [root.contentItem() if isinstance(root, QWindow) else root]
    while pending:
        item = pending.pop()
        yield item
        pending.extend(item.childItems())


def find_item(root, object_name: str, *, visible: bool | None = None) -> QQuickItem | None:
    """Find a visual item by objectName.

    Names are not unique: a dock's header and its buttons exist both in the
    group header and as tab-row delegates, only one of which is on screen.
    Pass ``visible=True`` to get the one a user could actually interact with.
    """

    matches = [item for item in descendants(root) if item.objectName() == object_name]
    if visible is not None:
        matches = [item for item in matches if item.property("visible") == visible]
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


def qml_value(value):
    return value.toVariant() if hasattr(value, "toVariant") else value


def center_of(item: QQuickItem) -> QPoint:
    return item.mapToScene(
        QPointF(item.width() / 2, item.height() / 2)
    ).toPoint()


def workspace_center(workspace) -> QPointF:
    return workspace.mapToGlobal(
        QPointF(workspace.width() / 2, workspace.height() / 2)
    )


def tab_drop_point(workspace, index: int) -> QPointF:
    """Global point just inside the rendered tab at insertion ``index``."""
    docks = main_container(saved(workspace))["root"]["docks"]
    tab = find_item(workspace, f"dockDragArea_{docks[index]}", visible=True)
    assert tab is not None
    return tab.mapToGlobal(
        QPointF(1, tab.height() / 2)
    )


def build_split_layout(workspace):
    """`scene` beside a tabbed `inspector`/`outline`, with `console` below.

    The only layout in these tests with both a horizontal and a vertical
    splitter, and an inactive tab.
    """

    assert workspace.splitDock("inspector", "scene", "right")
    assert workspace.splitDock("console", "scene", "bottom")
    assert workspace.dockAsTab("outline", "inspector")
    assert workspace.activateDock("inspector")


def floating_minimum(workspace, dock_id: str) -> tuple[float, float]:
    """The size a single-dock floating window is clamped up to."""

    floor = token(workspace, "floating.minimumSize")
    item = workspace.dockById(dock_id).property("minimumSize")
    return (
        max(floor.width(), item.width()),
        max(floor.height(), item.height() + token(workspace, "header.height")),
    )


# --------------------------------------------------------------------------
# Layout envelope (Python)
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


# --------------------------------------------------------------------------
# Layout algebra (DockLayout.js)
# --------------------------------------------------------------------------


TREE_JS = """
const left = {kind: "tabs", id: "left", docks: ["a", "b"], active: "a"}
const right = {kind: "tabs", id: "right", docks: ["c"], active: "c"}
const original = {
    kind: "split", id: "root", orientation: "horizontal",
    weights: [0.5, 0.5], children: [left, right]
}
"""


@pytest.fixture(scope="module")
def layout_js(qgui_app):
    """Evaluate DockLayout.js in a bare JS engine and return an eval helper."""

    engine = QJSEngine()
    types = (LIBRARY / "DockTypes.js").read_text(encoding="utf-8")
    result = engine.evaluate(types.replace(".pragma library", ""))
    assert not result.isError(), result.toString()
    engine.globalObject().setProperty(
        "DockTypes",
        engine.evaluate(
            "({size, rect, tabsNode, splitNode, mainContainer, floatingContainer, "
            "layoutSnapshot, splitPlacement, nodeHit, dropTarget, dropSurface})"
        ),
    )
    source = (LIBRARY / "DockLayout.js").read_text(encoding="utf-8")
    result = engine.evaluate(
        source.replace(".pragma library", "").replace(
            '.import "DockTypes.js" as DockTypes', ""
        )
    )
    assert not result.isError(), result.toString()

    def evaluate(body: str):
        result = engine.evaluate(
            f"JSON.stringify((function() {{ {TREE_JS}\n{body} }})())"
        )
        assert not result.isError(), result.toString()
        return json.loads(result.toString())

    return evaluate


def test_layout_edits_copy_the_spine_and_share_untouched_subtrees(layout_js):
    assert layout_js(
        """
        const resized = withSplitRatio(original, "root", 0, 0.7)
        const removed = withDockRemoved(original, "b")
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
        const nested = normalize({
            kind: "split", id: "outer", orientation: "horizontal",
            weights: [1, 1], children: [original, right]
        })
        const insertedTabs = {kind: "tabs", id: "inserted", docks: ["d", "e"], active: "e"}
        return {
            // A same-orientation child split is flattened into its parent.
            flattenedChildren: nested.children.length,
            // A dock inserted at the container root takes the given weight.
            rootDockWeight: withDockInsertedAtRoot(original, "d", "left", "new-tabs", "new-root", 0.3).weights[0],
            rootDockFirst: withDockInsertedAtRoot(original, "d", "left", "new-tabs", "new-root", 0.3).children[0].docks[0],
            // A center drop merges the incoming tabs at the given index and
            // adopts the incoming active dock.
            mergedDocks: withNodeInserted(original, "left", insertedTabs, "center", "unused", 1, 0.3).children[0].docks,
            mergedActive: withNodeInserted(original, "left", insertedTabs, "center", "unused", 1, 0.3).children[0].active,
            // A top/bottom drop at the root produces a vertical split.
            rootNodeOrientation: withNodeInsertedAtRoot(original, insertedTabs, "top", "container-root", 0.3).orientation
        }
        """
    )
    assert values.pop("rootDockWeight") == pytest.approx(0.3)
    assert values == {
        "flattenedChildren": 3,
        "rootDockFirst": "d",
        "mergedDocks": ["a", "d", "e", "b"],
        "mergedActive": "e",
        "rootNodeOrientation": "vertical",
    }


def test_layout_size_resolution_accounts_for_headers_and_splitters(layout_js):
    header, splitter, available = 30, 5, 300
    minimums = {"a": (100, 50), "b": (120, 40), "c": (80, 70)}
    values = layout_js(
        f"""
        const minimums = {json.dumps({k: {"width": w, "height": h}
                                      for k, (w, h) in minimums.items()})}
        return {{
            minimum: minimumSizeOf(original, minimums, {header}, {splitter}),
            constrained: constrainedLengths(
                original, {available}, minimums, {header}, {splitter})
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
    assert values["minimum"] == {
        "width": left[0] + right[0] + splitter,
        "height": max(left[1], right[1]),
    }
    # Equal weights, and the available width clears both minimums.
    assert values["constrained"] == [available / 2, available / 2]


# --------------------------------------------------------------------------
# Layout commands
# --------------------------------------------------------------------------


def test_splits_are_nary_and_ratio_changes_are_not_structural(workspace, pump):
    structural: list[bool] = []
    ratios: list[tuple[str, int]] = []
    workspace.layoutChanged.connect(lambda: structural.append(True))
    workspace.splitRatioChanged.connect(
        lambda split_id, index: ratios.append((split_id, index))
    )

    assert workspace.splitDock("inspector", "scene", "right")
    assert workspace.splitDock("outline", "scene", "left")
    assert workspace.dockAsTab("console", "inspector")
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

    assert workspace.setSplitRatio(root["id"], 0, 0.7)
    pump()

    resized = main_container(saved(workspace))["root"]
    pair = resized["weights"][0] + resized["weights"][1]
    assert resized["weights"][0] / pair == pytest.approx(0.7)
    assert outline.property("width") > initial_width
    assert len(structural) == structural_count
    assert ratios == [(root["id"], 0)]


def test_hidden_docks_keep_their_items_and_can_be_restored(workspace):
    assert sorted(qml_value(workspace.dockIds())) == sorted(DOCK_IDS)

    assert workspace.closeDock("outline")
    assert workspace.isHidden("outline")
    assert not workspace.isDockVisible("outline")
    assert "outline" in qml_value(workspace.property("hiddenDocks"))
    assert workspace.dockById("outline") is not None  # item survives hiding

    assert workspace.showDock("outline")
    assert workspace.isDocked("outline")
    assert "scene" in qml_value(workspace.neighborsOf("outline"))
    assert workspace.containerOf("outline") == "main"


def test_dropping_a_sole_group_on_its_own_edge_is_a_successful_no_op(workspace):
    for dock_id in ("outline", "inspector", "console"):
        assert workspace.hideDock(dock_id)

    before = workspace.saveLayout()
    assert workspace.splitDock("scene", "scene", "left")
    assert workspace.saveLayout() == before


def test_undo_and_redo_round_trip_the_layout(workspace):
    original = workspace.saveLayout()
    assert workspace.splitDock("inspector", "scene", "right")
    changed = workspace.saveLayout()
    assert changed != original

    assert workspace.undoLayout()
    assert workspace.saveLayout() == original
    assert workspace.redoLayout()
    assert workspace.saveLayout() == changed


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
    # snapshot never mentions stay in the layout rather than vanishing.
    assert sorted(collect_docks(main["root"])) == ["outline", "scene"]
    assert restored["hidden"] == ["console"]
    assert collect_docks(floating["root"]) == ["inspector"]
    # Untrusted ids are reissued so they cannot collide with live ones.
    assert main["id"] == "main"
    assert main["root"]["id"] != "untrusted-tabs"
    assert floating["id"] != "untrusted-float"
    # An undersized floating rect is clamped up to the dock's own minimum.
    width, height = floating_minimum(workspace, "inspector")
    assert (floating["geometry"]["width"], floating["geometry"]["height"]) == (width, height)
    assert set(activated) >= {"scene", "inspector"}


# --------------------------------------------------------------------------
# Policies and size constraints
# --------------------------------------------------------------------------


def test_central_dock_cannot_be_closed_hidden_or_floated(workspace, pump):
    errors: list[str] = []
    workspace.errorOccurred.connect(lambda code, _message: errors.append(code))

    assert workspace.setProperty("centralDockId", "scene")
    pump()

    assert not workspace.canCloseDock("scene")
    assert not workspace.canFloatDock("scene")
    assert not workspace.closeDock("scene")
    assert not workspace.hideDock("scene")
    assert not workspace.floatDock("scene", None, None, None, None)
    assert errors


def test_dock_item_policies_restrict_zones_and_tabbing(workspace):
    inspector = workspace.dockById("inspector")

    assert inspector.setProperty("allowedZones", ["left"])
    assert not workspace.splitDock("inspector", "scene", "right")
    assert workspace.splitDock("inspector", "scene", "left")

    assert inspector.setProperty("tabbable", False)
    assert not workspace.dockAsTab("inspector", "scene")


def test_size_constraints_bound_docked_and_floating_geometry(workspace, pump):
    inspector = workspace.dockById("inspector")
    minimum, maximum = QSizeF(360, 180), QSizeF(420, 260)
    assert inspector.setProperty("minimumSize", minimum)
    assert inspector.setProperty("maximumSize", maximum)

    assert workspace.splitDock("inspector", "scene", "left")
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
    assert workspace.isFloating("inspector")


# --------------------------------------------------------------------------
# Drag targeting
# --------------------------------------------------------------------------


def test_edge_bands_are_capped_in_pixels_and_outer_bands_are_narrow(workspace):
    fraction = token(workspace, "drag.edge.fraction")
    max_band = token(workspace, "drag.edge.maxBandPixels")
    outer_band = token(workspace, "drag.edge.outerBandPixels")
    # The pixel cap only means something while it is the binding constraint.
    assert workspace.width() * fraction > max_band

    just_outside = workspace.mapToGlobal(
        QPointF(max_band + 1, workspace.height() / 2)
    )
    assert workspace.beginDockDrag("outline", False)
    target = qml_value(workspace.updateDockDrag("outline", just_outside))
    assert target["zone"] == "center"
    assert not target["outer"]
    workspace.cancelDockDrag()

    inside_outer = workspace.mapToGlobal(
        QPointF(outer_band / 2, workspace.height() / 2)
    )
    assert workspace.beginDockDrag("outline", False)
    target = qml_value(workspace.updateDockDrag("outline", inside_outer))
    assert target["zone"] == "left"
    assert target["outer"]
    workspace.cancelDockDrag()


def test_outer_edge_drop_splits_the_root_at_the_style_ratio(workspace, pump):
    ratio = 0.3
    assert workspace.findChild(QObject, "dockStyleSplit").setProperty("defaultRatio", ratio)
    outer_band = token(workspace, "drag.edge.outerBandPixels")

    assert workspace.floatDock("inspector", 1200, 140, 510, 330)
    pump()
    window = workspace.floatingWindowForDock("inspector")
    floating_id = floating_containers(saved(workspace))[0]["id"]

    point = workspace.mapToGlobal(QPointF(outer_band / 2, workspace.height() / 2))
    assert workspace.beginDockDrag("inspector", True)
    target = qml_value(workspace.updateDockDrag("inspector", point))
    assert (target["zone"], target["outer"]) == ("left", True)
    assert workspace.finishFloatingDrag(
        "inspector",
        floating_id,
        point,
        window.property("x"),
        window.property("y"),
        window.property("width"),
        window.property("height"),
    )
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
    assert workspace.beginDockDrag("console", False)
    target = qml_value(workspace.updateDockDrag("console", point))
    assert target["zone"] == "center"
    assert target["tabIndex"] == 1

    indicator = find_item(workspace, "dockDropPreview_main")
    assert indicator is not None
    assert indicator.property("visible")
    assert indicator.property("zone") == "tab"
    assert indicator.width() == token(workspace, "drop.indicator.tabWidth")
    assert indicator.height() < token(workspace, "header.height")
    assert workspace.finishDockedDrag("console", point, 0, 0, 400, 300)

    assert main_container(saved(workspace))["root"]["docks"] == [
        "scene",
        "console",
        "outline",
        "inspector",
    ]

    # Moving right uses a final index calculated without the dragged tab.
    pump()
    last_tab = find_item(workspace, "dockDragArea_inspector", visible=True)
    point = last_tab.mapToGlobal(QPointF(last_tab.width() - 1, last_tab.height() / 2))
    assert workspace.beginDockDrag("scene", False)
    target = qml_value(workspace.updateDockDrag("scene", point))
    assert target["tabIndex"] == 4
    assert workspace.finishDockedDrag("scene", point, 0, 0, 400, 300)
    assert main_container(saved(workspace))["root"]["docks"] == [
        "console",
        "outline",
        "inspector",
        "scene",
    ]


def test_drag_released_outside_any_surface_floats_with_the_given_geometry(workspace):
    geometry = {"x": 2360, "y": 880, "width": 510, "height": 330}
    assert workspace.beginDockDrag("scene", False)
    assert workspace.finishDockedDrag(
        "scene",
        QPointF(2400, 900),
        geometry["x"],
        geometry["y"],
        geometry["width"],
        geometry["height"],
    )

    floating = floating_containers(saved(workspace))
    assert len(floating) == 1
    assert floating[0]["geometry"] == geometry


def test_a_floating_container_is_a_drop_target_with_its_own_overlay(workspace, pump):
    assert workspace.floatDock("inspector", 1200, 140, 510, 330)
    pump()
    window = workspace.floatingWindowForDock("inspector")
    floating_id = floating_containers(saved(workspace))[0]["id"]
    center = QPointF(
        window.property("x") + window.property("width") / 2,
        window.property("y") + window.property("height") / 2,
    )

    assert workspace.beginDockDrag("scene", False)
    target = qml_value(workspace.updateDockDrag("scene", center))
    assert target["containerId"] == floating_id
    # The preview is drawn by the floating window, not through the host.
    preview = find_item(window, f"floatingDropPreview_{floating_id}")
    assert preview is not None and preview.property("visible")

    assert workspace.finishDockedDrag("scene", center, 0, 0, 400, 300)
    pump()
    assert collect_docks(floating_containers(saved(workspace))[0]["root"]) == [
        "inspector",
        "scene",
    ]


def test_tab_and_title_bar_drags_move_different_scopes(workspace, pump):
    assert workspace.floatDock("inspector", 1200, 140, 510, 330)
    assert workspace.dockAsTab("scene", "inspector")
    pump()
    floating_id = floating_containers(saved(workspace))[0]["id"]
    drop_point = workspace_center(workspace)

    # Dragging one tab extracts only that dock.
    assert workspace.beginDockDrag("scene", False)
    assert workspace.finishDockedDrag("scene", drop_point, 0, 0, 400, 300)
    pump()
    state = saved(workspace)
    assert collect_docks(floating_containers(state)[0]["root"]) == ["inspector"]
    assert "scene" in collect_docks(main_container(state)["root"])

    # Dragging the title bar moves the whole container, which then disappears.
    assert workspace.dockAsTab("scene", "inspector")
    pump()
    geometry = floating_containers(saved(workspace))[0]["geometry"]
    assert workspace.beginFloatingContainerDrag(floating_id, "inspector")
    target = qml_value(workspace.updateFloatingContainerDrag(floating_id, drop_point))
    assert target["containerId"] == "main"
    assert workspace.finishFloatingContainerDrag(
        floating_id,
        drop_point,
        geometry["x"],
        geometry["y"],
        geometry["width"],
        geometry["height"],
    )
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
    # A single-dock float has no separate title bar. Its header drags the window.
    assert not window.property("hasDedicatedTitleBar")
    assert find_item(window, "dockHeader_inspector", visible=True).property(
        "windowDragEnabled"
    )

    assert workspace.dockAsTab("scene", "inspector")
    pump()
    floating = floating_containers(saved(workspace))
    assert len(floating) == 1
    assert collect_docks(floating[0]["root"]) == ["inspector", "scene"]
    # The surviving window is the original one, not a replacement.
    assert getCppPointer(workspace.floatingWindowForDock("inspector"))[0] == window_pointer

    # With tabs, a dedicated title bar owns dragging and maximizing.
    floating_id = floating[0]["id"]
    assert window.property("hasDedicatedTitleBar")
    assert find_item(window, f"floatingTitleBar_{floating_id}").property("visible")
    assert find_item(window, f"floatingMaximizeButton_{floating_id}").property("visible")
    for dock_id in ("inspector", "scene"):
        header = find_item(window, f"dockHeader_{dock_id}", visible=True)
        assert header is not None and not header.property("windowDragEnabled")
        assert find_item(window, f"dockMaximizeButton_{dock_id}", visible=True) is None


@pytest.mark.parametrize(
    "edge, delta, expected",
    [
        # Dragging a corner grows the window away from its origin ...
        ("bottomright", QPointF(80, 40), {"width": 80, "height": 40}),
        # ... while dragging the top edge moves the origin and keeps the
        # opposite edge fixed.
        ("top", QPointF(0, 45), {"y": 45, "height": -45}),
    ],
)
def test_floating_resize_is_live_but_committed_once(
    workspace, pump, edge, delta, expected
):
    assert workspace.floatDock("inspector", 120, 140, 510, 330)
    pump()
    window = workspace.floatingWindowForDock("inspector")
    before = floating_containers(saved(workspace))[0]["geometry"]
    after = {**before, **{key: before[key] + d for key, d in expected.items()}}

    window.beginResize(QPointF(0, 0))
    window.continueResize(edge, delta)
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

    window.beginMove(QPointF(400, 300))
    window.continueMove(QPointF(445, 335))
    pump()
    assert floating_containers(saved(workspace))[0]["geometry"] == before["geometry"]

    window.endMove()
    pump()
    moved = floating_containers(saved(workspace))[0]["geometry"]
    assert moved["x"] == before["geometry"]["x"] + 45
    assert moved["y"] == before["geometry"]["y"] + 35

    drop_point = workspace_center(workspace)
    assert workspace.beginDockDrag("inspector", True)
    assert workspace.finishFloatingDrag(
        "inspector",
        before["id"],
        drop_point,
        moved["x"],
        moved["y"],
        moved["width"],
        moved["height"],
    )
    pump()
    state = saved(workspace)
    assert not floating_containers(state)
    assert "inspector" in collect_docks(main_container(state)["root"])


def test_custom_floating_title_bar_delegate_tracks_the_active_dock(load, pump):
    workspace = load(CUSTOM_FLOATING_TITLE_QML, "CustomFloatingTitleTest.qml")
    assert workspace.floatDock("inspector", 120, 140, 510, 330)
    assert workspace.dockAsTab("scene", "inspector")
    pump()

    floating_id = floating_containers(saved(workspace))[0]["id"]
    window = workspace.floatingWindowForDock("inspector")
    title = find_item(window, f"customFloatingTitle_{floating_id}")

    assert title is not None and title.property("visible")
    assert title.property("receivedDockId") == "scene"
    assert title.property("receivedTitle") == "Scene"
    assert title.property("receivedWindow") is not None
    assert not title.property("receivedMaximized")

    assert workspace.activateDock("inspector")
    pump()
    assert title.property("receivedDockId") == "inspector"
    assert title.property("receivedTitle") == "Inspector"

    window.showFullScreen()
    pump()
    assert title.property("receivedMaximized")
    window.showNormal()


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
    workspace.splitRatioChanged.connect(
        lambda split_id, index: commits.append((split_id, index))
    )

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
        QTest.mousePress(
            window, Qt.MouseButton.LeftButton, Qt.KeyboardModifier.NoModifier, start
        )
        QTest.mouseMove(window, start + QPoint(30, 0), 10)
        pump(1)
        preview = workspace.findChild(QObject, "dockDragPreview")
        assert preview is not None and preview.property("visible")
        assert preview.property("dockId") == "scene"

        QTest.mouseRelease(
            window,
            Qt.MouseButton.LeftButton,
            Qt.KeyboardModifier.NoModifier,
            start + QPoint(30, 0),
        )
        pump(1)
        assert not preview.property("visible")

    assert not [message for message in messages if "TypeError" in message]


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
        window,
        Qt.MouseButton.LeftButton,
        Qt.KeyboardModifier.NoModifier,
        center_of(close_button),
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

    overflow = find_items(workspace, "dockOverflowButton_")[0]
    assert overflow.property("visible")
    menu = next(
        item
        for item in workspace.findChildren(QObject)
        if item.objectName().startswith("dockOverflowMenu_")
    )
    assert menu.property("count") == len(DOCK_IDS)


# --------------------------------------------------------------------------
# Engine hygiene
# --------------------------------------------------------------------------


def test_reset_after_float_leaves_no_type_or_binding_loop_warnings(workspace, pump):
    with qml_messages() as messages:
        assert workspace.splitDock("inspector", "scene", "right")
        assert workspace.splitDock("console", "scene", "bottom")
        assert workspace.floatDock("inspector", 100, 100, 360, 240)
        pump()
        workspace.resetLayout()
        assert workspace.splitDock("outline", "scene", "left")
        pump()

    assert not [
        message
        for message in messages
        if "TypeError" in message or "Binding loop" in message
    ]
    assert floating_containers(saved(workspace)) == []
