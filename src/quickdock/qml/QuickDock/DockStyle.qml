pragma ComponentBehavior: Bound

import QtQuick
import QuickDock.Style 1.0

// Theme and delegate API shared by every workspace surface. Consumers
// can override individual tokens or provide custom visual components.
QtObject {
    id: root
    objectName: "dockStyle"

    enum Preset {
        Dark,
        Light,
        System
    }

    property int preset: DockStyle.Dark
    property SystemPalette systemPalette: SystemPalette {}

    // Palette tables keep preset selection separate from the public color
    // tokens consumed by the rendering components.
    readonly property var _darkPalette: ({
        background: "#171a21",
        panel: "#20242d",
        header: "#292e39",
        activeHeader: "#323947",
        text: "#b9c0cc",
        activeText: "#f4f7fb",
        border: "#414857",
        splitter: "#11141a",
        accent: "#4d9dff",
        hover: "#465064"
    })
    readonly property var _lightPalette: ({
        background: "#f1f3f6",
        panel: "#ffffff",
        header: "#e4e8ee",
        activeHeader: "#d6deea",
        text: "#3b4655",
        activeText: "#111820",
        border: "#aeb7c4",
        splitter: "#c8ced7",
        accent: "#1264c4",
        hover: "#c8d4e4"
    })
    readonly property var _systemPalette: ({
        background: systemPalette.window,
        panel: systemPalette.base,
        header: systemPalette.button,
        activeHeader: systemPalette.highlight,
        text: systemPalette.text,
        activeText: systemPalette.highlightedText,
        border: systemPalette.mid,
        splitter: systemPalette.shadow,
        accent: systemPalette.highlight,
        hover: systemPalette.light
    })

    readonly property var _palette: {
        if (preset === DockStyle.Light) {
            return _lightPalette;
        } else if (preset === DockStyle.System) {
            return _systemPalette;
        } else {
            return _darkPalette;
        }
    }

    // Public style values are grouped by the surface or behavior they affect.
    // These are read-only object properties so QML exposes their sub-properties
    // using standard grouped-property syntax, such as `tab.border.width`.
    readonly property DockStyleColors colors: DockStyleColors {
        background: root._palette.background
        panel: root._palette.panel
        header: root._palette.header
        activeHeader: root._palette.activeHeader
        text: root._palette.text
        activeText: root._palette.activeText
        border: root._palette.border
        splitter: root._palette.splitter
        accent: root._palette.accent
        hover: root._palette.hover
        preview: Qt.rgba(accent.r, accent.g, accent.b, 0.35)
        dragPreviewFallback: Qt.rgba(panel.r, panel.g, panel.b, 0.96)
    }
    readonly property DockStyleHeader header: DockStyleHeader {}
    readonly property DockStyleTab tab: DockStyleTab {
        border.color: root.colors.border
        border.activeColor: root.colors.accent
    }
    readonly property DockStyleFrame frame: DockStyleFrame {}
    readonly property DockStyleSplitter splitter: DockStyleSplitter {}
    readonly property DockStyleSplit split: DockStyleSplit {}
    readonly property DockStyleButton button: DockStyleButton {}
    readonly property DockStyleFonts fonts: DockStyleFonts {}
    readonly property DockStyleDrag drag: DockStyleDrag {}
    readonly property DockStyleDrop drop: DockStyleDrop {}
    readonly property DockStyleFloating floating: DockStyleFloating {}
    readonly property DockStylePlaceholder placeholder: DockStylePlaceholder {}
    readonly property DockStyleGlyphs glyphs: DockStyleGlyphs {}
    readonly property DockStyleDelegates delegates: DockStyleDelegates {
        style: root
    }
}
