pragma ComponentBehavior: Bound

import QtQuick

QtObject {
    property font title: Qt.font({pixelSize: 12})
    property font glyph: Qt.font({pixelSize: 16})
    property font button: Qt.font({family: glyph.family, pixelSize: 13})
    property font closeButton: Qt.font({family: glyph.family, pixelSize: 16})
    property font placeholder: Qt.font({family: title.family, pixelSize: 15})
}
