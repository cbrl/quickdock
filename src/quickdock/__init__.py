"""Reusable Qt Quick docking components.

The implementation is QML-only.  This module only provides the import-path
helper used by Python-hosted Qt Quick applications.
"""

from pathlib import Path

from PySide6.QtCore import QDir, QFile
from PySide6.QtQml import QQmlEngine

try:
    import quickdock.resources_rc as _resources_rc
    assert _resources_rc
except ImportError:
    _resources_rc = None

from .layout import LAYOUT_VERSION, containers_of, decode_layout, docks_in


_QML_RESOURCE_PATH = "qrc:/quickdock/qml"
_QML_SOURCE_PATH = Path(__file__).parent / "qml"
QML_IMPORT_PATH = (
    _QML_RESOURCE_PATH
    if QFile.exists(":/quickdock/qml/QuickDock/qmldir")
    else QDir.fromNativeSeparators(str(_QML_SOURCE_PATH))
)


def install_docking(engine: QQmlEngine) -> None:
    """Make ``QuickDock`` available to a caller-owned QML engine."""
    if not isinstance(engine, QQmlEngine):
        raise TypeError("engine must be a QQmlEngine")

    if QML_IMPORT_PATH not in engine.importPathList():
        engine.addImportPath(QML_IMPORT_PATH)


__all__ = [
    "LAYOUT_VERSION",
    "QML_IMPORT_PATH",
    "containers_of",
    "decode_layout",
    "docks_in",
    "install_docking",
]
