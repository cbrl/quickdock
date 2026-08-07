"""Reusable Qt Quick docking components.

The implementation is QML-only.  This module only provides the import-path
helper used by Python-hosted Qt Quick applications.
"""

from __future__ import annotations

from pathlib import Path

from PySide6.QtCore import QDir
from PySide6.QtQml import QQmlEngine

from .layout import LAYOUT_VERSION, containers_of, decode_layout, docks_in


QML_IMPORT_PATH = Path(__file__).parent / "qml"


def install_docking(engine: QQmlEngine) -> None:
    """Make ``QuickDock`` available to a caller-owned QML engine."""
    if not isinstance(engine, QQmlEngine):
        raise TypeError("engine must be a QQmlEngine")

    import_path = QDir.fromNativeSeparators(str(QML_IMPORT_PATH))
    if import_path not in engine.importPathList():
        engine.addImportPath(import_path)


__all__ = [
    "LAYOUT_VERSION",
    "QML_IMPORT_PATH",
    "containers_of",
    "decode_layout",
    "docks_in",
    "install_docking",
]
