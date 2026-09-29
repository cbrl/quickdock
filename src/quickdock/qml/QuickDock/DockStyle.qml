pragma ComponentBehavior: Bound

import QtQuick

// Visual tokens shared by every workspace surface, in one level of groups:
// `style.header.height`, `style.colors.accent`, and so on. Behavior settings
// (drag thresholds, split ratios, floating placement) live in
// DockWorkspace.behavior, and components are replaced through the delegate
// properties on DockWorkspace.
QtObject {
    id: root

    enum Preset {
        Dark,
        Light,
        System
    }

    property int preset: DockStyle.Dark
    property SystemPalette systemPalette: SystemPalette {}

    readonly property var _darkPalette: ({
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
    readonly property var _palette: preset === DockStyle.Light ? _lightPalette
                                  : preset === DockStyle.System ? _systemPalette
                                  : _darkPalette

    readonly property DockStyleColors colors: DockStyleColors {
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
        placeholder: Qt.rgba(text.r, text.g, text.b, 0.7)
    }
    readonly property DockStyleHeader header: DockStyleHeader {}
    readonly property DockStyleTab tab: DockStyleTab {
        borderColor: root.colors.border
        activeBorderColor: root.colors.accent
    }
    readonly property DockStyleFrame frame: DockStyleFrame {}
    readonly property DockStyleDrop drop: DockStyleDrop {}
    readonly property DockStyleDragPreview dragPreview: DockStyleDragPreview {}
    readonly property DockStyleFonts fonts: DockStyleFonts {}
    readonly property DockStyleGlyphs glyphs: DockStyleGlyphs {}
    readonly property DockStyleFloating floating: DockStyleFloating {}
}
