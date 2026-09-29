"""Decode and inspect QuickDock layout snapshots."""

from __future__ import annotations

import json
from collections.abc import Mapping
from typing import Any


# The saved-layout format version. It must match `layoutVersion` in
# qml/QuickDock/DockLayout.js, which the test suite checks.
LAYOUT_VERSION = 2


def _decode_envelope(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict):
        raise ValueError("invalid docking layout: expected a JSON object")
    version = value.get("version")
    if type(version) is not int or version != LAYOUT_VERSION:
        raise ValueError(f"unsupported docking layout version: {version!r}")
    if not isinstance(value.get("containers"), list):
        raise ValueError("invalid docking layout: containers must be an array")
    if not isinstance(value.get("hidden"), list):
        raise ValueError("invalid docking layout: hidden must be an array")
    return value


def decode_layout(state: str | bytes | bytearray) -> dict[str, Any]:
    """Decode the envelope returned by ``saveLayout()``.

    This checks only JSON, version, and top-level collection types. QML's
    ``restoreLayout()`` handles layout sanitization.
    """

    try:
        value = json.loads(state)
    except (json.JSONDecodeError, TypeError, UnicodeDecodeError) as error:
        raise ValueError("invalid docking layout JSON") from error
    return _decode_envelope(value)


def _docks_in_node(node: Any) -> tuple[str, ...]:
    if not isinstance(node, Mapping):
        return ()
    if node.get("kind") == "tabs":
        docks = node.get("docks")
        if not isinstance(docks, list):
            return ()
        return tuple(dock_id for dock_id in docks if isinstance(dock_id, str))
    if node.get("kind") != "split":
        return ()
    children = node.get("children")
    if not isinstance(children, list):
        return ()
    return tuple(
        dock_id
        for child in children
        for dock_id in _docks_in_node(child)
    )


def docks_in(value: Any) -> tuple[str, ...]:
    """Return dock ids in tree order from a node, container, or snapshot.

    For a complete snapshot, visible docks are followed by hidden docks.
    """

    if not isinstance(value, Mapping):
        return ()
    if "containers" in value:
        hidden = value.get("hidden")
        visible = tuple(
            dock_id
            for container in containers_of(value)
            for dock_id in _docks_in_node(container.get("root"))
        )
        hidden_docks = tuple(
            dock_id
            for dock_id in hidden if isinstance(dock_id, str)
        ) if isinstance(hidden, list) else ()
        return visible + hidden_docks
    if "root" in value:
        return _docks_in_node(value.get("root"))
    return _docks_in_node(value)


def containers_of(layout: Any, dock_id: str | None = None) -> tuple[Mapping[str, Any], ...]:
    """Return containers, optionally restricted to those containing a dock."""

    if not isinstance(layout, Mapping):
        return ()
    containers = layout.get("containers")
    if not isinstance(containers, list):
        return ()
    result = tuple(
        container for container in containers if isinstance(container, Mapping)
    )
    if dock_id is None:
        return result
    return tuple(container for container in result if dock_id in docks_in(container))


__all__ = ["LAYOUT_VERSION", "containers_of", "decode_layout", "docks_in"]
