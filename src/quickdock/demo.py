"""Standalone demonstration of the Qt Quick docking module."""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Sequence

from PySide6.QtCore import QCoreApplication, Qt, QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuickControls2 import QQuickStyle

from . import install_docking


DEMO_QML = Path(__file__).parent / "demo" / "Main.qml"


def main(argv: Sequence[str] | None = None) -> int:
    """Run the docking demo without constructing a QApplication or QWidget."""
    QQuickStyle.setStyle("Basic")
    app = QGuiApplication(list(argv) if argv is not None else sys.argv)
    QCoreApplication.setOrganizationName("QuickDock")
    QCoreApplication.setApplicationName("Qt Quick Docking Demo")

    engine = QQmlApplicationEngine()
    install_docking(engine)
    engine.objectCreationFailed.connect(
        lambda _url: QCoreApplication.exit(1),
        Qt.ConnectionType.QueuedConnection,
    )
    engine.load(QUrl.fromLocalFile(str(DEMO_QML.resolve())))
    if not engine.rootObjects():
        return 1
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
